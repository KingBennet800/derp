#!/usr/bin/env python3
"""Derp for iOS's ad blocker: Adblock Plus-style filter lists (EasyList,
EasyPrivacy, the lists uBlock Origin starts with) turned into WebKit content
blocker rules, which Derp compiles on the device. WebKit can't run uBlock
Origin, so this keeps what its rule format can say and leaves the rest out:

- ||example.com^, |https://…, plain patterns with * and ^ → "block", with
  $third-party, $domain=, $match-case and resource types;
- ##selector and example.com##selector (plain CSS) → "css-display-none";
- @@ exceptions → "ignore-previous-rules", after everything they could undo.

Anything else (scriptlets, extended CSS, redirects, $csp, $removeparam…) is
skipped. A rule WebKit can't compile would sink the whole list, so selectors
and patterns are checked conservatively.

    python3 ios/blocklist.py easylist.txt easyprivacy.txt > blocklist.json
"""
import json
import re
import sys

# A small set for builds without the real lists (and for the tests).
SAMPLE = """! Derp test rules
||ads.example.com^
||tracker.example.net^$third-party
/banner-ad/*$image
##.derp-test-ad
example.org##.sponsored
@@||ads.example.com/allowed/*
"""

# WebKit's resource types for filter options.
TYPES = {
    "script": "script",
    "image": "image",
    "stylesheet": "style-sheet",
    "css": "style-sheet",
    "font": "font",
    "media": "media",
    "xmlhttprequest": "raw",
    "xhr": "raw",
    "websocket": "websocket",
    "ping": "ping",
    "other": "other",
    "popup": "popup",
    "subdocument": "document",
    "frame": "document",
}
# Options that only narrow a rule, which can be dropped without blocking more.
HARMLESS = {"important", "~important", "all"}
# Characters a selector may use; anything fancier (:has, :-abp-…) is skipped.
SELECTOR = re.compile(r"^[A-Za-z0-9_\-\.#\[\]=\"'~\^\$\*\|:\(\)\s>+,]+$")
PSEUDO = re.compile(r":(?!not\(|nth-child\(|nth-of-type\(|first-child|last-child|first-of-type|last-of-type|only-child|empty\b)")
DOMAIN = re.compile(r"^[a-z0-9.\-]+$")
CHUNK = 250


def _pattern(text, anchored_domain):
    """An ABP pattern as WebKit's url-filter regex, or None."""
    if not text or len(text) > 400:
        return None
    start = ""
    end = ""
    if anchored_domain:
        start = r"^[^:]+://+([^:/]+\.)?"
    elif text.startswith("|"):
        start = "^"
        text = text[1:]
    if text.endswith("|"):
        end = "$"
        text = text[:-1]
    out = []
    for ch in text:
        if ch == "*":
            out.append(".*")
        elif ch == "^":
            out.append("[/:?=&]")
        elif ch in ".+?$()[]{}\\|":
            out.append("\\" + ch)
        elif ch.isascii() and ch.isprintable():
            out.append(ch)
        else:
            return None
    # (WebKit has no alternation, so a separator can't also mean the end of
    # the address; addresses always have a path, so ||site^ still matches.)
    pattern = start + "".join(out) + end
    if pattern in ("", "^", ".*", "^.*") or "{" in pattern:
        return None
    return pattern


def _domains(value):
    """$domain=a.com|~b.com → (if, unless), or None if unusable."""
    yes, no = [], []
    for d in value.split("|"):
        neg = d.startswith("~")
        d = d.lstrip("~").lower()
        if not d or not DOMAIN.match(d) or "*" in d:
            return None
        (no if neg else yes).append("*" + d)
    return yes, no


def _network(line):
    """A blocking or exception rule, or None."""
    exception = line.startswith("@@")
    if exception:
        line = line[2:]
    # Regular expression filters (/…/, maybe with options) are skipped.
    if line.startswith("/") and re.search(r"/(\$[^/]*)?$", line[1:]):
        return None
    options = []
    if "$" in line:
        line, _, opts = line.rpartition("$")
        options = [o.strip() for o in opts.split(",") if o.strip()]
    trigger = {}
    types = []
    for option in options:
        name, _, value = option.partition("=")
        name = name.lower()
        if name in ("third-party", "3p"):
            trigger["load-type"] = ["third-party"]
        elif name in ("~third-party", "first-party", "1p"):
            trigger["load-type"] = ["first-party"]
        elif name == "domain":
            domains = _domains(value)
            if domains is None:
                return None
            yes, no = domains
            if yes:
                trigger["if-domain"] = yes
            elif no:
                trigger["unless-domain"] = no
        elif name == "match-case":
            trigger["url-filter-is-case-sensitive"] = True
        elif name in TYPES:
            types.append(TYPES[name])
        elif name == "document" and exception:
            types.append("document")
        elif name in HARMLESS:
            continue
        else:
            return None
    anchored = line.startswith("||")
    pattern = _pattern(line[2:] if anchored else line, anchored)
    if pattern is None:
        return None
    trigger = {"url-filter": pattern, **trigger}
    if types:
        trigger["resource-type"] = sorted(set(types))
        if "document" in types and not exception:
            trigger["load-context"] = ["child-frame"]
    return {"trigger": trigger, "action": {"type": "ignore-previous-rules" if exception else "block"}}


def _selector_ok(selector):
    return len(selector) < 500 and SELECTOR.match(selector) and not PSEUDO.search(selector) and selector.count("(") == selector.count(")")


def convert(texts):
    """WebKit rules from the given filter lists' texts."""
    block, exceptions = [], []
    generic, by_domain = [], {}
    seen = set()
    for text in texts:
        for raw in text.splitlines():
            line = raw.strip()
            if not line or line.startswith("!") or line.startswith("["):
                continue
            if line in seen:
                continue
            seen.add(line)
            if "##" in line and "#?#" not in line and "#$#" not in line and "#@#" not in line:
                domains, _, selector = line.partition("##")
                if selector.startswith("+js(") or not _selector_ok(selector):
                    continue
                if not domains:
                    generic.append(selector)
                    continue
                names = domains.split(",")
                if any(n.startswith("~") or not DOMAIN.match(n.lower()) for n in names):
                    continue
                key = tuple(sorted("*" + n.lower() for n in names))
                by_domain.setdefault(key, []).append(selector)
                continue
            if "#" in line and re.search(r"#[@?$%]#", line):
                continue
            rule = _network(line)
            if rule is None:
                continue
            (exceptions if rule["action"]["type"] == "ignore-previous-rules" else block).append(rule)
    rules = list(block)
    for i in range(0, len(generic), CHUNK):
        rules.append({"trigger": {"url-filter": ".*"}, "action": {"type": "css-display-none", "selector": ", ".join(generic[i:i + CHUNK])}})
    for domains, selectors in by_domain.items():
        for i in range(0, len(selectors), CHUNK):
            rules.append({"trigger": {"url-filter": ".*", "if-domain": list(domains)},
                          "action": {"type": "css-display-none", "selector": ", ".join(selectors[i:i + CHUNK])}})
    rules.extend(exceptions)
    # WebKit's limit for one list.
    return rules[:149_000]


if __name__ == "__main__":
    texts = [open(path, encoding="utf-8", errors="replace").read() for path in sys.argv[1:]] or [SAMPLE]
    json.dump(convert(texts), sys.stdout, separators=(",", ":"))
