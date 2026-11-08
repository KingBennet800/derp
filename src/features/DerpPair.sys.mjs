/* Your devices: pair Derp on your computer with Derp on your phone, and they
 * share bookmarks, passwords and open tabs. There's still no account: the
 * computer makes a secret and shows it as a QR code; the phone's camera reads
 * it and opens it in Derp. Both derive keys from it and pass encrypted
 * snapshots through a small relay (relay/derp-relay.php) that only ever sees
 * encrypted bytes. tests/pairing.py has the same protocol in Python.
 *
 * Each device keeps a ledger: every bookmark and password it knows, with when
 * it last changed and whether it's gone. Passwords stay in the password
 * manager; the ledger keeps only a keyed hash of each, to notice changes. A
 * sync notes local changes, takes newer changes from the other devices'
 * snapshots, then uploads its own snapshot. Bookmarks from other devices land
 * in "Mobile Bookmarks". */

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  CustomizableUI: "moz-src:///browser/components/customizableui/CustomizableUI.sys.mjs",
  PanelMultiView: "moz-src:///browser/components/customizableui/PanelMultiView.sys.mjs",
  PlacesUtils: "resource://gre/modules/PlacesUtils.sys.mjs",
  PrivateBrowsingUtils: "resource://gre/modules/PrivateBrowsingUtils.sys.mjs",
  QR: "moz-src:///toolkit/components/qrcode/encoder.mjs",
  clearTimeout: "resource://gre/modules/Timer.sys.mjs",
  setTimeout: "resource://gre/modules/Timer.sys.mjs",
});

const XHTML = "http://www.w3.org/1999/xhtml";
const VIEW = "derp-devices-view";
const DORK_WIDGET = "derp-dork-button";
export const RELAY_PREF = "derp.pair.relay";
const RELAY = "https://bennettholland.com/derp-relay.php";
const LINK = "https://kingbennet800.github.io/derp/pair/#";
const DAY = 24 * 60 * 60 * 1000;
const FORGET_GONE = 90 * DAY;
const EVERY = 10 * 60 * 1000;
const TABS = 50;
const MAX_TEXT = 4096;

const encoder = new TextEncoder();
const hex = bytes => Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, "0")).join("");
const b64url = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const fromB64url = text => Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
const fromB64 = text => Uint8Array.from(atob(text), c => c.charCodeAt(0));
const isText = (value, max = MAX_TEXT) => typeof value == "string" && value.length <= max;
const isWeb = url => isText(url) && /^https?:\/\/[^\s]+$/i.test(url);
const loginKey = l => `${l.origin}\n${l.realm || ""}\n${l.username}`;
const originOf = url => {
  try {
    return new URL(url).origin;
  } catch {
    return null;
  }
};

async function gzip(bytes, compress) {
  const stream = new Blob([bytes]).stream().pipeThrough(compress ? new CompressionStream("gzip") : new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** The keys a pair secret gives (see tests/pairing.py). */
async function keysFor(secret) {
  const base = await crypto.subtle.importKey("raw", secret, "HKDF", false, ["deriveBits"]);
  const bits = info =>
    crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(), info: encoder.encode(info) }, base, 256);
  return {
    box: hex(await bits("derp pair box")),
    token: hex(await bits("derp pair write")),
    key: await crypto.subtle.importKey("raw", await bits("derp pair key"), "AES-GCM", false, ["encrypt", "decrypt"]),
    hash: await crypto.subtle.importKey("raw", await bits("derp pair hash"), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]),
  };
}

export const DerpPair = {
  cssURL: null,
  dork: null,
  state: null,
  keys: null,
  running: null,
  again: false,
  timer: null,
  pairing: null,
  problem: "",

  init({ cssURL, dork }) {
    this.cssURL = cssURL;
    this.dork = dork;
    this.load()
      .then(() => {
        if (this.paired) {
          this.soon(15000);
        }
      })
      .catch(console.error);
    // Your changes go out a few seconds after you make them; tabs, within a minute.
    lazy.PlacesUtils.observers.addListener(
      ["bookmark-added", "bookmark-removed", "bookmark-title-changed", "bookmark-url-changed"],
      () => this.paired && this.soon(5000)
    );
    Services.obs.addObserver(() => this.paired && this.soon(5000), "passwordmgr-storage-changed");
    Services.obs.addObserver(win => this.watch(win), "browser-delayed-startup-finished");
    for (const win of Services.wm.getEnumerator("navigator:browser")) {
      this.watch(win);
    }
  },

  watch(win) {
    if (lazy.PrivateBrowsingUtils.isWindowPrivate(win)) {
      return;
    }
    const tabsChanged = () => this.paired && this.soon(60000, { onlyIfIdle: true });
    for (const event of ["TabOpen", "TabClose"]) {
      win.gBrowser.tabContainer.addEventListener(event, tabsChanged);
    }
    win.gBrowser.addTabsProgressListener({
      onLocationChange(browser, progress, request, location, flags) {
        if (progress.isTopLevel && !(flags & Ci.nsIWebProgressListener.LOCATION_CHANGE_SAME_DOCUMENT)) {
          tabsChanged();
        }
      },
    });
  },

  get paired() {
    return !!this.state?.secret;
  },

  // ── State, kept in the profile (no passwords in it) ─────────────────────

  get file() {
    return PathUtils.join(PathUtils.profileDir, "derp-devices.json");
  },

  async load() {
    try {
      this.state = await IOUtils.readJSON(this.file);
      this.keys = await keysFor(fromB64url(this.state.secret));
    } catch {
      this.state = null;
      this.keys = null;
    }
  },

  async save() {
    if (this.state) {
      await IOUtils.writeJSON(this.file, this.state, { tmpPath: this.file + ".tmp" });
      await IOUtils.setPermissions(this.file, 0o600).catch(() => {});
    }
    Services.obs.notifyObservers(null, "derp-pair-changed");
  },

  /** This computer's name for the others. */
  get name() {
    const os = { WINNT: "Windows", Darwin: "macOS", Linux: "Linux" }[Services.appinfo.OS] ?? Services.appinfo.OS;
    return `Derp on ${os}`;
  },

  /** The pairing link (the QR code's): the secret, and the relay if it isn't the usual one. */
  get link() {
    if (!this.paired) {
      return "";
    }
    const relay = this.state.relay === RELAY ? "" : `~${encodeURIComponent(this.state.relay)}`;
    return LINK + this.state.secret + relay;
  },

  /** Starts a pair (a new secret), or keeps the one there is. */
  async begin() {
    if (!this.paired) {
      const secret = crypto.getRandomValues(new Uint8Array(32));
      this.state = {
        secret: b64url(secret),
        relay: Services.prefs.getStringPref(RELAY_PREF, RELAY),
        device: hex(crypto.getRandomValues(new Uint8Array(16))),
        ledger: { bookmarks: {}, logins: {} },
        devices: {},
        etag: "",
        pushed: "",
        pushedAt: 0,
        syncedAt: 0,
      };
      this.keys = await keysFor(secret);
      await this.save();
    }
    await this.sync();
    if (!this.timer) {
      this.soon(EVERY);
    }
  },

  /** Stop syncing: this computer leaves the pair (its bookmarks and passwords stay). */
  async leave() {
    if (!this.paired) {
      return;
    }
    const { relay, device } = this.state;
    try {
      await this.request(relay, "POST", { "X-Derp-Token": this.keys.token, "X-Derp-Device": device, "X-Derp-Delete": "1" });
    } catch (e) {
      console.warn("Derp devices: couldn't leave the relay", e);
    }
    lazy.clearTimeout(this.timer);
    this.state = null;
    this.keys = null;
    this.problem = "";
    await IOUtils.remove(this.file, { ignoreAbsent: true });
    Services.obs.notifyObservers(null, "derp-pair-changed");
  },

  // ── Syncing ──────────────────────────────────────────────────────────────

  /** Sync in [delay] ms (sooner wins), then every ten minutes. */
  soon(delay = 0, { onlyIfIdle = false } = {}) {
    if (onlyIfIdle && this.timer && this.dueAt - Date.now() < delay) {
      return;
    }
    lazy.clearTimeout(this.timer);
    this.dueAt = Date.now() + delay;
    this.timer = lazy.setTimeout(() => {
      this.timer = null;
      this.sync()
        .catch(e => console.warn("Derp devices: sync failed", e))
        .finally(() => this.paired && !this.timer && this.soon(EVERY));
    }, delay);
  },

  async sync() {
    if (this.running) {
      this.again = true;
      return this.running;
    }
    this.running = (async () => {
      do {
        this.again = false;
        await this.syncOnce();
      } while (this.again && this.paired);
    })();
    try {
      await this.running;
    } finally {
      this.running = null;
    }
  },

  async syncOnce() {
    if (!this.paired) {
      return;
    }
    const state = this.state;
    const local = await this.readLocal();
    await this.noteLocal(local);

    let changes = 0;
    let failed = null;
    try {
      const slots = await this.pull();
      if (slots) {
        const seen = {};
        for (const [device, slot] of Object.entries(slots)) {
          if (device === state.device || !/^[0-9a-f]{32}$/.test(device)) {
            continue;
          }
          let snapshot;
          try {
            snapshot = await this.unseal(fromB64(slot.data), device);
          } catch (e) {
            console.warn("Derp devices: a slot didn't decrypt", e);
            continue;
          }
          seen[device] = {
            name: isText(snapshot.name, 80) ? snapshot.name : "Derp",
            kind: ["phone", "tablet", "desktop"].includes(snapshot.kind) ? snapshot.kind : "desktop",
            at: Number(snapshot.at) || 0,
            tabs: (Array.isArray(snapshot.tabs) ? snapshot.tabs : [])
              .filter(t => isWeb(t?.url))
              .slice(0, TABS)
              .map(t => ({ url: t.url, title: isText(t.title, 300) ? t.title : "" })),
          };
          changes += await this.merge(snapshot, local);
        }
        state.devices = seen;
      }
      this.forgetOld();
      await this.push(local);
      state.syncedAt = Date.now();
    } catch (e) {
      failed = e;
    }
    this.problem = failed ? String(failed.message || failed) : "";
    await this.save();
    if (changes) {
      console.info(`Derp devices: ${changes} change(s) from your other devices`);
    }
    if (failed) {
      throw failed;
    }
  },

  async request(relay, method, headers = {}, body = null) {
    const response = await fetch(relay, {
      method,
      body,
      headers: { "X-Derp-Box": this.keys.box, ...headers },
      cache: "no-store",
      credentials: "omit",
    });
    if (!response.ok && response.status !== 304) {
      const why = await response.json().catch(() => ({}));
      throw new Error(`relay ${response.status}${why.error ? `: ${why.error}` : ""}`);
    }
    return response;
  },

  /** The other devices' slots, or null if nothing changed since last time. */
  async pull() {
    const response = await this.request(this.state.relay, "GET", this.state.etag ? { "If-None-Match": this.state.etag } : {});
    if (response.status === 304) {
      return null;
    }
    const { slots } = await response.json();
    this.state.etag = response.headers.get("ETag") || "";
    return slots || {};
  },

  /** Uploads this computer's snapshot when it changed (or once a week, so the relay keeps it). */
  async push(local) {
    const snapshot = await this.snapshot(local);
    const body = JSON.stringify(snapshot);
    const fingerprint = hex(await crypto.subtle.digest("SHA-256", encoder.encode(body)));
    if (fingerprint === this.state.pushed && Date.now() - this.state.pushedAt < 7 * DAY) {
      return;
    }
    const sealed = await this.seal({ ...snapshot, at: Date.now() });
    await this.request(this.state.relay, "POST", {
      "X-Derp-Token": this.keys.token,
      "X-Derp-Device": this.state.device,
      "Content-Type": "application/octet-stream",
    }, sealed);
    this.state.pushed = fingerprint;
    this.state.pushedAt = Date.now();
    this.state.etag = "";
  },

  async seal(snapshot) {
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const body = await gzip(encoder.encode(JSON.stringify(snapshot)), true);
    const additionalData = encoder.encode(`derp pair v1 ${this.state.device}`);
    const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData }, this.keys.key, body));
    const blob = new Uint8Array(1 + 12 + sealed.length);
    blob[0] = 1;
    blob.set(nonce, 1);
    blob.set(sealed, 13);
    return blob;
  },

  async unseal(blob, device) {
    if (blob[0] !== 1) {
      throw new Error("unknown slot version");
    }
    const additionalData = encoder.encode(`derp pair v1 ${device}`);
    const body = await crypto.subtle.decrypt({ name: "AES-GCM", iv: blob.subarray(1, 13), additionalData }, this.keys.key, blob.subarray(13));
    return JSON.parse(new TextDecoder().decode(await gzip(new Uint8Array(body), false)));
  },

  async passwordHash(password) {
    return hex(await crypto.subtle.sign("HMAC", this.keys.hash, encoder.encode(password))).slice(0, 32);
  },

  // ── This computer's bookmarks, passwords and tabs ───────────────────────

  async readLocal() {
    const db = await lazy.PlacesUtils.promiseDBConnection();
    const rows = await db.execute(
      `SELECT h.url, b.title FROM moz_bookmarks b
         JOIN moz_places h ON h.id = b.fk
         JOIN moz_bookmarks p ON p.id = b.parent
       WHERE b.type = 1 AND p.parent <> (SELECT id FROM moz_bookmarks WHERE guid = 'tags________')
       ORDER BY b.dateAdded`
    );
    const bookmarks = new Map();
    for (const row of rows) {
      const url = row.getResultByName("url");
      if (isWeb(url) && !bookmarks.has(url)) {
        bookmarks.set(url, row.getResultByName("title") || "");
      }
    }
    // Passwords only when they can be read without asking (no locked Primary Password).
    let logins = null;
    if (Services.logins.isLoggedIn) {
      logins = new Map();
      for (const login of await Services.logins.getAllLogins()) {
        if (!isWeb(login.origin) || !isText(login.username) || !isText(login.password)) {
          continue;
        }
        const entry = { origin: login.origin, realm: login.httpRealm || "", form: login.formActionOrigin || "", username: login.username, login };
        logins.set(loginKey(entry), entry);
      }
    }
    return { bookmarks, logins, tabs: this.readTabs() };
  },

  readTabs() {
    const tabs = [];
    for (const win of Services.wm.getEnumerator("navigator:browser")) {
      if (win.closed || lazy.PrivateBrowsingUtils.isWindowPrivate(win)) {
        continue;
      }
      for (const tab of win.gBrowser.tabs) {
        const url = tab.linkedBrowser?.currentURI?.spec;
        if (isWeb(url)) {
          tabs.push({ url, title: tab.label.slice(0, 300), seen: tab.lastAccessed || 0 });
        }
      }
    }
    return tabs.sort((a, b) => b.seen - a.seen).slice(0, TABS).map(({ url, title }) => ({ url, title }));
  },

  /** Your changes since the last sync go in the ledger, as of now. */
  async noteLocal(local) {
    const now = Date.now();
    const { bookmarks, logins } = this.state.ledger;
    for (const [url, title] of local.bookmarks) {
      const known = bookmarks[url];
      if (!known || known.gone || known.title !== title) {
        bookmarks[url] = { title, at: now, gone: false };
      }
    }
    for (const [url, known] of Object.entries(bookmarks)) {
      if (!known.gone && !local.bookmarks.has(url)) {
        bookmarks[url] = { title: known.title, at: now, gone: true };
      }
    }
    if (!local.logins) {
      return;
    }
    for (const [key, entry] of local.logins) {
      const hash = await this.passwordHash(entry.login.password);
      const known = logins[key];
      if (!known || known.gone || known.hash !== hash) {
        logins[key] = { origin: entry.origin, realm: entry.realm, form: entry.form, username: entry.username, hash, at: now, gone: false };
      }
    }
    for (const [key, known] of Object.entries(logins)) {
      if (!known.gone && !local.logins.has(key)) {
        logins[key] = { ...known, hash: "", at: now, gone: true };
      }
    }
  },

  /** Takes another device's newer changes; returns how many. The ledger
   * only takes a change once it's made here, so one that fails is tried again
   * next time (rather than looking like a change made here). */
  async merge(snapshot, local) {
    let changes = 0;
    const { bookmarks, logins } = this.state.ledger;
    for (const [url, theirs] of Object.entries(snapshot.bookmarks || {})) {
      const at = Number(theirs?.at);
      if (!isWeb(url) || !Number.isFinite(at) || (bookmarks[url] && bookmarks[url].at >= at)) {
        continue;
      }
      const title = isText(theirs.title, 1000) ? theirs.title : "";
      try {
        if (theirs.gone) {
          if (local.bookmarks.delete(url)) {
            await this.unbookmark(url);
            changes++;
          }
        } else if (!local.bookmarks.has(url)) {
          await lazy.PlacesUtils.bookmarks.insert({ parentGuid: lazy.PlacesUtils.bookmarks.mobileGuid, url, title });
          Services.prefs.setBoolPref("browser.bookmarks.showMobileBookmarks", true);
          local.bookmarks.set(url, title);
          changes++;
        } else if (local.bookmarks.get(url) !== title) {
          await this.retitle(url, title);
          local.bookmarks.set(url, title);
          changes++;
        }
        bookmarks[url] = { title, at, gone: !!theirs.gone };
      } catch (e) {
        console.warn("Derp devices: couldn't apply a bookmark", e);
      }
    }
    if (!local.logins) {
      return changes;
    }
    for (const theirs of Object.values(snapshot.logins || {})) {
      const at = Number(theirs?.at);
      const origin = isWeb(theirs?.origin) ? originOf(theirs.origin) : null;
      if (!origin || !isText(theirs.username) || !Number.isFinite(at)) {
        continue;
      }
      const entry = {
        origin,
        realm: isText(theirs.realm, 1000) ? theirs.realm : "",
        form: isText(theirs.form, 1000) ? theirs.form : "",
        username: theirs.username,
      };
      const key = loginKey(entry);
      if (logins[key] && logins[key].at >= at) {
        continue;
      }
      if (!theirs.gone && !isText(theirs.password)) {
        continue;
      }
      try {
        const mine = local.logins.get(key);
        if (theirs.gone) {
          if (mine) {
            await Services.logins.removeLoginAsync(mine.login);
            local.logins.delete(key);
            changes++;
          }
          logins[key] = { ...entry, hash: "", at, gone: true };
          continue;
        }
        const hash = await this.passwordHash(theirs.password);
        if (mine) {
          if ((await this.passwordHash(mine.login.password)) !== hash) {
            const bag = Cc["@mozilla.org/hash-property-bag;1"].createInstance(Ci.nsIWritablePropertyBag2);
            bag.setPropertyAsAString("password", theirs.password);
            await Services.logins.modifyLoginAsync(mine.login, bag);
            changes++;
          }
        } else {
          const login = Cc["@mozilla.org/login-manager/loginInfo;1"].createInstance(Ci.nsILoginInfo);
          login.init(entry.origin, entry.realm ? null : entry.form || entry.origin, entry.realm || null, entry.username, theirs.password, "", "");
          const added = await Services.logins.addLoginAsync(login);
          local.logins.set(key, { ...entry, login: added });
          changes++;
        }
        logins[key] = { ...entry, hash, at, gone: false };
      } catch (e) {
        console.warn("Derp devices: couldn't apply a password", e);
      }
    }
    return changes;
  },

  async unbookmark(url) {
    const guids = [];
    await lazy.PlacesUtils.bookmarks.fetch({ url }, bookmark => guids.push(bookmark.guid));
    for (const guid of guids) {
      await lazy.PlacesUtils.bookmarks.remove(guid);
    }
  },

  async retitle(url, title) {
    const guids = [];
    await lazy.PlacesUtils.bookmarks.fetch({ url }, bookmark => guids.push(bookmark.guid));
    for (const guid of guids) {
      await lazy.PlacesUtils.bookmarks.update({ guid, title });
    }
  },

  /** Deletions are remembered for 90 days, so other devices hear of them. */
  forgetOld() {
    const old = Date.now() - FORGET_GONE;
    for (const list of Object.values(this.state.ledger)) {
      for (const [key, entry] of Object.entries(list)) {
        if (entry.gone && entry.at < old) {
          delete list[key];
        }
      }
    }
  },

  async snapshot(local) {
    const logins = {};
    for (const [key, known] of Object.entries(this.state.ledger.logins)) {
      const { origin, realm, form, username, at, gone } = known;
      if (gone) {
        logins[key] = { origin, realm, form, username, at, gone: true };
        continue;
      }
      const mine = local.logins?.get(key);
      if (mine) {
        logins[key] = { origin, realm, form, username, password: mine.login.password, at, gone: false };
      }
    }
    return {
      v: 1,
      device: this.state.device,
      name: this.name,
      kind: "desktop",
      tabs: local.tabs,
      bookmarks: this.state.ledger.bookmarks,
      logins,
    };
  },

  // ── The panel: pair a phone, your devices and their tabs ────────────────

  prepare(doc) {
    let view = lazy.PanelMultiView.getViewNode(doc, VIEW);
    if (view) {
      return view;
    }
    const win = doc.defaultView;
    win.MozXULElement.insertFTLIfNeeded("derp/pair.ftl");
    win.windowUtils.loadSheetUsingURIString(this.cssURL, win.windowUtils.AUTHOR_SHEET);
    view = doc.createXULElement("panelview");
    view.id = VIEW;
    view.className = "PanelUI-subView";
    const body = doc.createXULElement("vbox");
    body.className = "panel-subview-body";
    body.append(doc.createElementNS(XHTML, "div"));
    body.firstChild.className = "derp-devices";
    view.append(body);
    doc.getElementById("appMenu-viewCache").content.append(view);

    const changed = () => view.closest("panel")?.state === "open" && this.render(view);
    Services.obs.addObserver(changed, "derp-pair-changed");
    win.addEventListener("unload", () => Services.obs.removeObserver(changed, "derp-pair-changed"), { once: true });
    view.addEventListener("ViewShowing", () => {
      this.render(view);
      if (this.paired) {
        this.sync().catch(() => {});
      }
    });
    view.addEventListener("ViewHiding", () => this.stopWaiting());
    view.addEventListener("click", e => this.clicked(view, e));
    return view;
  },

  /** Opens "Your devices" in a browser window, from your dork if it's in the toolbar. */
  open(win, { pair = false } = {}) {
    const view = this.prepare(win.document);
    view.removeAttribute("pairing");
    const node = lazy.CustomizableUI.getWidget(DORK_WIDGET)?.forWindow(win)?.node;
    const anchor = node?.checkVisibility() ? node : win.document.getElementById("PanelUI-menu-button");
    win.PanelUI.showSubView(VIEW, anchor);
    if (pair) {
      this.startPairing(view);
    }
  },

  /** Shows the QR code (making a pair first if need be), and waits for the phone. */
  async startPairing(view) {
    view.setAttribute("pairing", "");
    this.render(view);
    try {
      await this.begin();
    } catch (error) {
      this.problem = String(error.message || error);
    }
    this.render(view);
    this.wait(view);
  },

  /** While the QR code shows, look for the phone every few seconds. */
  wait(view) {
    if (this.pairing) {
      return;
    }
    const before = new Set(Object.keys(this.state?.devices || {}));
    const started = Date.now();
    const look = async () => {
      this.pairing = null;
      if (!this.paired || Date.now() - started > 10 * 60 * 1000) {
        return;
      }
      await this.sync().catch(() => {});
      const fresh = Object.keys(this.state?.devices || {}).find(id => !before.has(id));
      if (fresh) {
        view.removeAttribute("pairing");
        view.dataset.fresh = fresh;
        this.render(view);
        return;
      }
      this.pairing = lazy.setTimeout(look, 3000);
    };
    this.pairing = lazy.setTimeout(look, 3000);
  },

  stopWaiting() {
    lazy.clearTimeout(this.pairing);
    this.pairing = null;
  },

  async clicked(view, e) {
    const button = e.target.closest("button, a");
    if (!button) {
      return;
    }
    const win = view.ownerGlobal;
    switch (button.dataset.action) {
      case "pair":
        await this.startPairing(view);
        break;
      case "done":
        this.stopWaiting();
        view.removeAttribute("pairing");
        this.render(view);
        break;
      case "sync":
        await this.sync().catch(() => {});
        break;
      case "leave": {
        const [title, message] = await win.document.l10n.formatValues(["derp-devices-leave-title", "derp-devices-leave-message"]);
        if (Services.prompt.confirm(win, title, message)) {
          this.stopWaiting();
          await this.leave();
          view.removeAttribute("pairing");
          this.render(view);
        }
        break;
      }
      case "tab":
        e.preventDefault();
        win.openTrustedLinkIn(button.dataset.url, "tab");
        view.closest("panel")?.hidePopup();
        break;
    }
  },

  render(view) {
    const doc = view.ownerDocument;
    const h = (tag, attrs = {}, ...children) => {
      const el = doc.createElementNS(XHTML, tag);
      for (const [k, v] of Object.entries(attrs)) {
        if (k === "l10n") {
          doc.l10n.setAttributes(el, v[0], v[1]);
        } else {
          el.setAttribute(k, v);
        }
      }
      el.append(...children);
      return el;
    };
    const root = view.querySelector(".derp-devices");
    const parts = [h("h2", { l10n: ["derp-devices-title"] })];

    if (view.hasAttribute("pairing")) {
      if (this.paired) {
        parts.push(
          h("div", { class: "derp-devices-qr" }, this.qr(doc)),
          h(
            "ol",
            { class: "derp-devices-steps" },
            h("li", { l10n: ["derp-devices-step-install"] }),
            h("li", { l10n: ["derp-devices-step-scan"] }),
            h("li", { l10n: ["derp-devices-step-open"] })
          ),
          h("p", { class: "derp-devices-waiting", l10n: ["derp-devices-waiting"] }),
          h("p", { class: "derp-devices-note", l10n: ["derp-devices-private"] }),
          h("div", { class: "derp-devices-actions" }, h("button", { "data-action": "done", l10n: ["derp-devices-cancel"] }))
        );
      } else {
        parts.push(h("p", { class: "derp-devices-waiting", l10n: ["derp-devices-making"] }));
      }
    } else if (!this.paired) {
      parts.push(
        h("p", { l10n: ["derp-devices-intro"] }),
        h("p", { class: "derp-devices-note", l10n: ["derp-devices-private"] }),
        h("div", { class: "derp-devices-actions" }, h("button", { class: "primary", "data-action": "pair", l10n: ["derp-devices-pair"] }))
      );
    } else {
      const devices = Object.entries(this.state.devices || {});
      if (view.dataset.fresh && this.state.devices[view.dataset.fresh]) {
        parts.push(h("p", { class: "derp-devices-hello", l10n: ["derp-devices-paired", { name: this.state.devices[view.dataset.fresh].name }] }));
        delete view.dataset.fresh;
      }
      if (!devices.length) {
        parts.push(h("p", { l10n: ["derp-devices-alone"] }));
      }
      for (const [, device] of devices) {
        const tabs = device.tabs.map(tab =>
          h("a", { class: "derp-devices-tab", href: tab.url, "data-action": "tab", "data-url": tab.url, title: tab.url }, tab.title || tab.url)
        );
        parts.push(
          h(
            "section",
            { class: "derp-devices-device", kind: device.kind },
            h("h3", {}, device.name),
            h("p", { class: "derp-devices-note", l10n: ["derp-devices-seen", { when: this.ago(device.at) }] }),
            tabs.length ? h("div", { class: "derp-devices-tabs" }, ...tabs) : h("p", { class: "derp-devices-note", l10n: ["derp-devices-no-tabs"] })
          )
        );
      }
      if (this.problem) {
        parts.push(h("p", { class: "derp-devices-problem", l10n: ["derp-devices-problem", { problem: this.problem }] }));
      }
      parts.push(
        h(
          "div",
          { class: "derp-devices-actions" },
          h("button", { "data-action": "leave", l10n: ["derp-devices-leave"] }),
          h("button", { "data-action": "sync", l10n: ["derp-devices-sync"] }),
          h("button", { class: "primary", "data-action": "pair", l10n: ["derp-devices-pair-another"] })
        )
      );
    }
    root.replaceChildren(...parts);
  },

  /** "5 minutes ago" and the like. */
  ago(at) {
    const formatter = new Intl.RelativeTimeFormat(Services.locale.appLocalesAsBCP47, { numeric: "auto" });
    const minutes = Math.round((at - Date.now()) / 60000);
    if (Math.abs(minutes) < 60) {
      return formatter.format(minutes, "minute");
    }
    const hours = Math.round(minutes / 60);
    return Math.abs(hours) < 48 ? formatter.format(hours, "hour") : formatter.format(Math.round(hours / 24), "day");
  },

  /** The pairing link as a QR code, your dork in the middle. */
  qr(doc) {
    const ns = "http://www.w3.org/2000/svg";
    const make = (tag, attrs) => {
      const el = doc.createElementNS(ns, tag);
      for (const [k, v] of Object.entries(attrs)) {
        el.setAttribute(k, v);
      }
      return el;
    };
    const { matrix, dotCount } = lazy.QR.encodeToMatrix(this.link, "H");
    const size = dotCount + 8;
    let path = "";
    matrix.forEach((row, y) =>
      row.forEach((dark, x) => {
        if (dark) {
          path += `M${x + 4} ${y + 4}h1v1h-1z`;
        }
      })
    );
    // Your dork, on a white spot in the middle (high error correction leaves room).
    const spot = Math.round(dotCount * 0.22);
    const at = (size - spot) / 2;
    const svg = make("svg", { viewBox: `0 0 ${size} ${size}`, role: "img", "shape-rendering": "crispEdges" });
    svg.append(
      make("rect", { width: size, height: size, fill: "#fff" }),
      make("path", { d: path, fill: "#18181b" }),
      make("rect", { x: at - 0.5, y: at - 0.5, width: spot + 1, height: spot + 1, rx: 1.5, fill: "#fff" }),
      make("image", { x: at, y: at, width: spot, height: spot, href: this.dork.dataURL(undefined, 128) })
    );
    doc.l10n.setAttributes(svg, "derp-devices-qr");
    return svg;
  },
};
