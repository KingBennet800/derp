#!/usr/bin/env python3
"""Derp's pairing protocol in Python: the reference the tests check desktop
and Android Derp against, playing "the other device".

Paired Derps share a 32-byte secret, in the pairing QR code's link after the
# (base64url), optionally followed by "~" and the relay's address
(URL-encoded) when it isn't the usual one. From it, with HKDF-SHA256 (no
salt), each derives:

    "derp pair box"    the box's name on the relay (hex)
    "derp pair write"  the token the relay wants for writes (hex)
    "derp pair key"    the AES-256-GCM key for the snapshots

Each device keeps one slot in the box: 0x01, a 12-byte nonce, then its
snapshot (gzipped JSON), encrypted and tied to the device's id (the AAD is
"derp pair v1 <device>"). A snapshot is the device's name and kind, when it
was made, its open tabs, and its bookmarks and passwords with a time and a
"gone" flag for each, so the newest change to anything wins everywhere.

    python3 tests/pairing.py new [--relay URL]
    python3 tests/pairing.py push <link> --device <hex> --name NAME [--snapshot FILE]
    python3 tests/pairing.py pull <link>
    python3 tests/pairing.py leave <link> --device <hex>
    python3 tests/pairing.py relay [--port 8124]   a relay for tests, like derp-relay.php

Needs the cryptography package (not for "relay").
"""
import argparse
import base64
import gzip
import hashlib
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

RELAY = "https://bennettholland.com/derp-relay.php"
LINK = "https://kingbennet800.github.io/derp/pair/#"
AGENT = "Derp-pairing-test/1"


def derive(secret, info):
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF

    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=info.encode()).derive(secret)


class Pair:
    def __init__(self, secret, relay=RELAY):
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        self.secret = secret
        self.relay = relay
        self.box = derive(secret, "derp pair box").hex()
        self.token = derive(secret, "derp pair write").hex()
        self.key = AESGCM(derive(secret, "derp pair key"))

    @classmethod
    def from_link(cls, link):
        code, _, relay = link.split("#", 1)[-1].partition("~")
        return cls(base64.urlsafe_b64decode(code + "=" * (-len(code) % 4)), urllib.parse.unquote(relay) or RELAY)

    @property
    def link(self):
        code = base64.urlsafe_b64encode(self.secret).decode().rstrip("=")
        return LINK + code + ("" if self.relay == RELAY else "~" + urllib.parse.quote(self.relay, safe=""))

    def seal(self, snapshot, device):
        nonce = secrets.token_bytes(12)
        body = gzip.compress(json.dumps(snapshot).encode())
        return b"\x01" + nonce + self.key.encrypt(nonce, body, f"derp pair v1 {device}".encode())

    def open(self, blob, device):
        if blob[:1] != b"\x01":
            raise ValueError("unknown slot version")
        body = self.key.decrypt(blob[1:13], blob[13:], f"derp pair v1 {device}".encode())
        return json.loads(gzip.decompress(body))

    def _request(self, method, data=None, headers=None):
        request = urllib.request.Request(self.relay, data=data, method=method, headers={
            "User-Agent": AGENT, "X-Derp-Box": self.box, **(headers or {})})
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read()

    def push(self, device, snapshot):
        blob = self.seal(snapshot, device)
        return self._request("POST", blob, {"X-Derp-Token": self.token, "X-Derp-Device": device,
                                            "Content-Type": "application/octet-stream"})[0]

    def pull(self):
        status, body = self._request("GET")
        slots = json.loads(body)["slots"]
        return {device: self.open(base64.b64decode(slot["data"]), device) for device, slot in slots.items()}

    def leave(self, device):
        return self._request("POST", b"", {"X-Derp-Token": self.token, "X-Derp-Device": device,
                                           "X-Derp-Delete": "1"})[0]


def snapshot(device, name, kind="desktop", tabs=(), bookmarks=None, logins=None):
    return {"v": 1, "device": device, "name": name, "kind": kind, "at": int(time.time() * 1000),
            "tabs": list(tabs), "bookmarks": bookmarks or {}, "logins": logins or {}}


def serve(port):
    """A relay for tests: derp-relay.php's protocol (no limits), in memory."""
    import http.server
    import threading

    boxes = {}  # box -> {"token": sha256, "slots": {device: (at, bytes)}}
    lock = threading.Lock()

    class Relay(http.server.BaseHTTPRequestHandler):
        def reply(self, code, body=None, headers=()):
            data = json.dumps(body).encode() if body is not None else b""
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            for name, value in headers:
                self.send_header(name, value)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            box = (self.headers.get("X-Derp-Box") or "").lower()
            if not box:
                return self.reply(200, {"relay": "derp", "version": 1})
            with lock:
                slots = {d: {"at": at, "data": base64.b64encode(b).decode()}
                         for d, (at, b) in sorted(boxes.get(box, {}).get("slots", {}).items())}
            etag = '"' + hashlib.sha256(json.dumps(slots).encode()).hexdigest() + '"'
            if (self.headers.get("If-None-Match") or "").strip() == etag:
                return self.reply(304, headers=[("ETag", etag)])
            self.reply(200, {"slots": slots}, [("ETag", etag)])

        def do_POST(self):
            box = (self.headers.get("X-Derp-Box") or "").lower()
            device = (self.headers.get("X-Derp-Device") or "").lower()
            token = hashlib.sha256((self.headers.get("X-Derp-Token") or "").lower().encode()).hexdigest()
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
            with lock:
                entry = boxes.setdefault(box, {"token": token, "slots": {}})
                if entry["token"] != token:
                    return self.reply(403, {"error": "token"})
                if self.headers.get("X-Derp-Delete") == "1":
                    entry["slots"].pop(device, None)
                else:
                    entry["slots"][device] = (int(time.time()), body)
            print(f"relay: {'leave' if not body else 'slot'} {device[:8]} in {box[:8]}", flush=True)
            self.reply(204)

        def log_message(self, *args):
            pass

    print(f"relay on http://127.0.0.1:{port}/", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Relay).serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    new = sub.add_parser("new")
    new.add_argument("--relay", default=RELAY)
    relay = sub.add_parser("relay")
    relay.add_argument("--port", type=int, default=8124)
    push = sub.add_parser("push")
    push.add_argument("link")
    push.add_argument("--device", default=secrets.token_hex(16))
    push.add_argument("--name", default="Derp on a test machine")
    push.add_argument("--snapshot", help="a JSON file with tabs, bookmarks and logins")
    pull = sub.add_parser("pull")
    pull.add_argument("link")
    leave = sub.add_parser("leave")
    leave.add_argument("link")
    leave.add_argument("--device", required=True)
    args = parser.parse_args()

    if args.command == "new":
        print(Pair(secrets.token_bytes(32), args.relay).link)
        return 0
    if args.command == "relay":
        serve(args.port)
        return 0
    pair = Pair.from_link(args.link)
    try:
        if args.command == "push":
            extra = json.load(open(args.snapshot)) if args.snapshot else {}
            print(pair.push(args.device, snapshot(args.device, args.name, **extra)))
        elif args.command == "pull":
            print(json.dumps(pair.pull(), indent=2))
        else:
            print(pair.leave(args.device))
    except urllib.error.HTTPError as e:
        print(f"relay said {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
