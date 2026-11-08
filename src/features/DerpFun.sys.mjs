/* Just for fun: joke settings, all off by default (Settings → Derp → Just for
 * fun), alongside Duck mode (DerpDuck.sys.mjs).
 *
 * - Snail mode: when a page takes more than 3 seconds, a snail crawls along
 *   the loading bar, and zooms off once the page is there.
 * - Peekaboo: now and then (1 in 6 new tabs) your dork peeks up from the
 *   bottom of the window, waves, and ducks back down.
 * - Party mode: confetti when you bookmark a page.
 * - Sleepy tabs: tabs Memory Saver has put to sleep snore (💤). */

const HTML = "http://www.w3.org/1999/xhtml";
const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  PlacesUtils: "resource://gre/modules/PlacesUtils.sys.mjs",
});

/** The snail, facing right (the way it crawls). The Android app draws the same one. */
export const SNAIL_URL =
  "data:image/svg+xml;charset=utf-8," +
  encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <path d="M3 26h22c3 0 5-2 5-5v-6c0-1.7-1.3-3-3-3s-3 1.3-3 3v4H6c-1.7 0-3 1.6-3 3.5z" fill="#9BD77B"/>
  <path d="M26 12.5 24.6 7.5M28 12.5l1.6-4.7" fill="none" stroke="#6BAF4F" stroke-width="1.4" stroke-linecap="round"/>
  <circle cx="24.5" cy="7.2" r="1.4" fill="#222"/>
  <circle cx="29.7" cy="7.5" r="1.4" fill="#222"/>
  <circle cx="14" cy="13.5" r="8.5" fill="#F4A259"/>
  <path d="M12.8 13.5a1.2 1.2 0 1 1 1.2 1.2 3 3 0 1 1-3-3 4.8 4.8 0 1 1 4.8 4.8 6.4 6.4 0 1 1-6.4-6.4" fill="none" stroke="#B5651D" stroke-width="1.3" stroke-linecap="round"/>
</svg>`);

const NEW_TAB_PAGES = ["about:newtab", "about:home", "about:privatebrowsing"];
const CONFETTI = ["#c6f57e", "#2fd6be", "#2f6feb", "#ffd43b", "#ff6b9a", "#b8a4ff"];

export const DerpFun = {
  PREFS: {
    snail: "derp.fun.snail",
    peekaboo: "derp.fun.peekaboo",
    party: "derp.fun.party",
    sleepy: "derp.fun.sleepy",
  },
  PEEK_CHANCE: 1 / 6,
  SLOW: 3000,

  init({ cssURL, dork }) {
    this.cssURL = cssURL;
    this.dork = dork;
    Services.obs.addObserver(win => this.watch(win), "browser-delayed-startup-finished");
    Services.prefs.addObserver(this.PREFS.sleepy, () => {
      for (const win of Services.wm.getEnumerator("navigator:browser")) {
        this.paintSleepy(win);
      }
    });
    lazy.PlacesUtils.observers.addListener(["bookmark-added"], events => this.onBookmarks(events));
  },

  on(name) {
    return Services.prefs.getBoolPref(this.PREFS[name], false);
  },

  watch(win) {
    if (win.derpFun) {
      return;
    }
    win.derpFun = { snail: null, slow: 0, peeking: false };
    win.MozXULElement.insertFTLIfNeeded("derp/fun.ftl");
    win.windowUtils.loadSheetUsingURIString(this.cssURL, win.windowUtils.AUTHOR_SHEET);
    this.paintSleepy(win);
    const tabs = win.gBrowser.tabContainer;
    // A tab is loading while it has the "busy" attribute.
    new win.MutationObserver(() => this.checkSnail(win)).observe(tabs, { subtree: true, attributeFilter: ["busy"] });
    tabs.addEventListener("TabSelect", () => this.checkSnail(win));
    // A new tab page (Ctrl+T, the + button) shows up a moment after the tab.
    tabs.addEventListener("TabOpen", event => win.setTimeout(() => this.maybePeek(win, event.target), 600));
  },

  /** Over the window's chrome, above pages. */
  layer(doc) {
    return doc.body ?? doc.documentElement;
  },

  still(win) {
    return win.matchMedia("(prefers-reduced-motion: reduce)").matches;
  },

  // ── Snail mode ─────────────────────────────────────────────────────────

  checkSnail(win) {
    win.clearTimeout(win.derpFun.slow);
    if (!win.gBrowser.selectedTab.hasAttribute("busy")) {
      this.snailAway(win);
      return;
    }
    if (win.derpFun.snail || !this.on("snail")) {
      return;
    }
    win.derpFun.slow = win.setTimeout(() => {
      if (win.gBrowser.selectedTab.hasAttribute("busy") && !win.derpFun.snail) {
        this.snailCrawl(win);
      }
    }, this.SLOW);
  },

  /** Over the window, straddling the loading bar along the toolbar's bottom edge. */
  snailCrawl(win) {
    const doc = win.document;
    const bar = doc.getElementById("nav-bar").getBoundingClientRect();
    const snail = doc.createElementNS(HTML, "img");
    snail.className = "derp-snail";
    snail.src = SNAIL_URL;
    snail.alt = "";
    snail.style.top = `${bar.bottom - 17}px`;
    snail.style.setProperty("--from", `${bar.left + 6}px`);
    snail.style.setProperty("--to", `${bar.right - 30}px`);
    snail.style.setProperty("--away", `${bar.right + 30}px`);
    this.layer(doc).append(snail);
    win.derpFun.snail = snail;
  },

  /** The page is there: the snail speeds off. */
  snailAway(win) {
    const snail = win.derpFun.snail;
    if (!snail) {
      return;
    }
    win.derpFun.snail = null;
    const at = win.getComputedStyle(snail).left;
    snail.style.animation = "none";
    snail.style.left = at;
    snail.getBoundingClientRect();
    snail.classList.add("derp-snail-done");
    win.setTimeout(() => snail.remove(), 600);
  },

  // ── Peekaboo ───────────────────────────────────────────────────────────

  maybePeek(win, tab) {
    if (
      !this.on("peekaboo") ||
      win.derpFun.peeking ||
      this.still(win) ||
      win.gBrowser.selectedTab !== tab ||
      !NEW_TAB_PAGES.includes(tab.linkedBrowser.currentURI.spec) ||
      Math.random() >= this.PEEK_CHANCE
    ) {
      return;
    }
    this.peek(win);
  },

  peek(win) {
    const doc = win.document;
    const box = doc.createElementNS(HTML, "div");
    box.className = "derp-peek";
    const hi = doc.createElementNS(HTML, "span");
    hi.className = "derp-peek-hi";
    doc.l10n.setAttributes(hi, "derp-peek-hi");
    const img = doc.createElementNS(HTML, "img");
    img.src = this.dork.dataURL(undefined, 192);
    img.alt = "";
    box.append(hi, img);
    this.layer(doc).append(box);
    win.derpFun.peeking = true;
    box.addEventListener("animationend", event => {
      if (event.animationName === "derp-peek") {
        box.remove();
        win.derpFun.peeking = false;
      }
    });
  },

  // ── Party mode ─────────────────────────────────────────────────────────

  /** Bookmarking the page you're on (not imports or sync) sets off confetti. */
  onBookmarks(events) {
    if (!this.on("party")) {
      return;
    }
    const { bookmarks } = lazy.PlacesUtils;
    for (const event of events) {
      if (event.itemType !== bookmarks.TYPE_BOOKMARK || event.isTagging || event.source !== bookmarks.SOURCES.DEFAULT) {
        continue;
      }
      const win = Services.wm.getMostRecentWindow("navigator:browser");
      if (win && !this.still(win) && win.gBrowser.currentURI.spec === event.url) {
        this.confetti(win);
        return;
      }
    }
  },

  confetti(win) {
    const doc = win.document;
    const star = doc.getElementById("star-button-box")?.getBoundingClientRect();
    const x = star?.width ? star.left + star.width / 2 : win.innerWidth / 2;
    const y = star?.height ? star.top + star.height / 2 : 60;
    const layer = doc.createElementNS(HTML, "div");
    layer.className = "derp-confetti";
    this.layer(doc).append(layer);
    let left = 60;
    for (let i = 0; i < 60; i++) {
      const bit = doc.createElementNS(HTML, "span");
      bit.style.left = `${x}px`;
      bit.style.top = `${y}px`;
      bit.style.background = CONFETTI[i % CONFETTI.length];
      layer.append(bit);
      const angle = Math.random() * Math.PI * 2;
      const speed = 60 + Math.random() * 200;
      const dx = Math.cos(angle) * speed;
      const dy = Math.sin(angle) * speed * 0.6 + 40;
      const fall = 220 + Math.random() * 260;
      bit
        .animate(
          [
            { transform: "translate(0, 0) rotate(0deg)", opacity: 1 },
            { transform: `translate(${dx}px, ${dy}px) rotate(${Math.random() * 360}deg)`, opacity: 1, offset: 0.3 },
            { transform: `translate(${dx * 1.4}px, ${dy + fall}px) rotate(${Math.random() * 720}deg)`, opacity: 0 },
          ],
          { duration: 1300 + Math.random() * 700, easing: "cubic-bezier(0.2, 0.6, 0.4, 1)" }
        )
        .finished.then(() => {
          if (--left === 0) {
            layer.remove();
          }
        });
    }
  },

  // ── Sleepy tabs ────────────────────────────────────────────────────────

  paintSleepy(win) {
    win.document.documentElement.toggleAttribute("derp-sleepy", this.on("sleepy"));
  },
};
