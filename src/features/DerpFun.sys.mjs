/* Just for fun: joke settings, all off by default (Settings → Derp → Just for
 * fun), alongside Duck mode (DerpDuck.sys.mjs).
 *
 * - Snail mode: when a page takes more than 3 seconds, a snail crawls along
 *   the loading bar, and zooms off once the page is there.
 * - Peekaboo: now and then (1 in 6 new tabs) your dork peeks up from the
 *   bottom of the window, waves, and ducks back down.
 * - Party mode: confetti when you bookmark a page.
 * - Sleepy tabs: tabs Memory Saver has put to sleep snore (💤).
 * - Power typing: sparks fly from the address bar as you type.
 * - Hiccups: now and then (1 in 12 pages) a page gets the hiccups. Hic!
 * - Tab ghosts: a tab you close drifts away as a little ghost.
 * - Rainbow mode: the loading bar is a rainbow.
 * - Seasons: when a window opens (and now and then a new tab), the season
 *   drifts down over the toolbar: snow, blossoms, sunshine or leaves, hearts
 *   for Valentine's Day and pumpkins for Halloween.
 * - Download duck: a duck carries each new download along the toolbar to the
 *   downloads button. */

const HTML = "http://www.w3.org/1999/xhtml";
const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  Downloads: "resource://gre/modules/Downloads.sys.mjs",
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

/** A closed tab's ghost. The Android app draws the same one. */
export const GHOST_URL =
  "data:image/svg+xml;charset=utf-8," +
  encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <path d="M6 15a10 10 0 0 1 20 0v13l-3.3-2.5-3.4 2.5-3.3-2.5-3.3 2.5-3.4-2.5L6 28z" fill="#fff" stroke="#c9cbd6" stroke-width="1.2" stroke-linejoin="round"/>
  <circle cx="12.5" cy="15" r="1.8" fill="#222"/>
  <circle cx="19.5" cy="15" r="1.8" fill="#222"/>
  <ellipse cx="16" cy="20.2" rx="1.6" ry="2" fill="#222"/>
</svg>`);

const svg = s => "data:image/svg+xml;charset=utf-8," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">${s}</svg>`);

/** Seasons' things that fall. The Android app draws the same ones. */
export const SEASON_ART = {
  snow: svg(`<g stroke="#9cc4ff" stroke-width="2.4" stroke-linecap="round" fill="none"><path d="M16 3v26M4.7 9.5l22.6 13M4.7 22.5l22.6-13"/><path d="M12 5l4 3.5L20 5M12 27l4-3.5 4 3.5M4.6 14.4l5.2-1 -1.7-5M27.4 17.6l-5.2 1 1.7 5M4.6 17.6l5.2 1-1.7 5M27.4 14.4l-5.2-1 1.7-5"/></g>`),
  blossom: svg(`<g fill="#ffb3cf">${[0, 72, 144, 216, 288].map(a => `<ellipse cx="16" cy="8.5" rx="5" ry="7" transform="rotate(${a} 16 16)"/>`).join("")}</g><circle cx="16" cy="16" r="3.4" fill="#ffd84d"/>`),
  sun: svg(`<path d="M16 2l3 10 10 4-10 3-3 11-3-11-10-3 10-4z" fill="#ffd43b"/><circle cx="16" cy="16" r="3" fill="#fff6c2"/>`),
  leaf: svg(`<path d="M5 27C5 13 13 5 27 5c0 14-8 22-22 22z" fill="#f08c2e"/><path d="M5 27L20 12" stroke="#b5571a" stroke-width="1.6" stroke-linecap="round"/>`),
  redLeaf: svg(`<path d="M5 27C5 13 13 5 27 5c0 14-8 22-22 22z" fill="#d9472b"/><path d="M5 27L20 12" stroke="#93281a" stroke-width="1.6" stroke-linecap="round"/>`),
  heart: svg(`<path d="M16 28S3 20 3 11.5A6.5 6.5 0 0 1 16 8.6 6.5 6.5 0 0 1 29 11.5C29 20 16 28 16 28z" fill="#ff5d8f"/>`),
  pumpkin: svg(`<path d="M15 8c0-3 2-5 4-5" stroke="#4f8a2b" stroke-width="2.4" stroke-linecap="round" fill="none"/><ellipse cx="11" cy="18" rx="7" ry="9" fill="#f07a1a"/><ellipse cx="21" cy="18" rx="7" ry="9" fill="#f07a1a"/><ellipse cx="16" cy="18" rx="6.5" ry="9.5" fill="#ff922e"/><path d="M11.5 16l2 2.5h-4zM20.5 16l2 2.5h-4zM11 22q5 3 10 0" fill="#7a3a00"/>`),
};

/** What falls on [date]: hearts the week before Valentine's Day, pumpkins
 * and leaves the week before Halloween, and otherwise the (northern) season's. */
export function seasonOf(date) {
  const month = date.getMonth() + 1;
  const day = date.getDate();
  if (month === 2 && day >= 7 && day <= 14) {
    return ["heart"];
  }
  if (month === 10 && day >= 24) {
    return ["pumpkin", "leaf", "redLeaf"];
  }
  if (month === 12 || month <= 2) {
    return ["snow"];
  }
  if (month <= 5) {
    return ["blossom"];
  }
  if (month <= 8) {
    return ["sun"];
  }
  return ["leaf", "redLeaf"];
}

/** A parcel, which the download duck carries. */
const PARCEL_URL = svg(
  `<path d="M4 11 16 5.5 28 11v12.5L16 29 4 23.5z" fill="#d9a066"/><path d="M4 11l12 5.5L28 11M16 16.5V29" fill="none" stroke="#b07b45" stroke-width="1.5" stroke-linejoin="round"/><path d="M9.5 8.3l12 5.6v4.5" fill="none" stroke="#f4d9b0" stroke-width="2.6"/>`
);

const NEW_TAB_PAGES = ["about:newtab", "about:home", "about:privatebrowsing"];
const CONFETTI = ["#c6f57e", "#2fd6be", "#2f6feb", "#ffd43b", "#ff6b9a", "#b8a4ff"];

export const DerpFun = {
  PREFS: {
    snail: "derp.fun.snail",
    peekaboo: "derp.fun.peekaboo",
    party: "derp.fun.party",
    sleepy: "derp.fun.sleepy",
    power: "derp.fun.power",
    hiccups: "derp.fun.hiccups",
    ghosts: "derp.fun.ghosts",
    rainbow: "derp.fun.rainbow",
    seasons: "derp.fun.seasons",
    downloadDuck: "derp.fun.downloadDuck",
  },
  /** Gags that are just a style on the window: pref → attribute on its root. */
  FLAGS: { sleepy: "derp-sleepy", rainbow: "derp-rainbow" },
  PEEK_CHANCE: 1 / 6,
  HICCUP_CHANCE: 1 / 12,
  SEASON_CHANCE: 1 / 5,
  SLOW: 3000,

  init({ cssURL, dork, duckURL }) {
    this.cssURL = cssURL;
    this.dork = dork;
    this.duckURL = duckURL;
    Services.obs.addObserver(win => this.watch(win), "browser-delayed-startup-finished");
    for (const name of Object.keys(this.FLAGS)) {
      Services.prefs.addObserver(this.PREFS[name], () => {
        for (const win of Services.wm.getEnumerator("navigator:browser")) {
          this.paintFlags(win);
        }
      });
    }
    lazy.PlacesUtils.observers.addListener(["bookmark-added"], events => this.onBookmarks(events));
    // Downloads already listed are reported as they're added to the view;
    // only ones after that are new.
    let ready = false;
    lazy.Downloads.getList(lazy.Downloads.ALL)
      .then(list =>
        list.addView({
          onDownloadAdded: () => {
            const win = Services.wm.getMostRecentWindow("navigator:browser");
            if (ready && win?.derpFun && this.on("downloadDuck") && !this.still(win)) {
              this.carry(win);
            }
          },
        })
      )
      .then(() => (ready = true), console.error);
  },

  on(name) {
    return Services.prefs.getBoolPref(this.PREFS[name], false);
  },

  watch(win) {
    if (win.derpFun) {
      return;
    }
    win.derpFun = { snail: null, slow: 0, peeking: false, sparked: 0, ghosts: 0 };
    win.MozXULElement.insertFTLIfNeeded("derp/fun.ftl");
    win.windowUtils.loadSheetUsingURIString(this.cssURL, win.windowUtils.AUTHOR_SHEET);
    this.paintFlags(win);
    const tabs = win.gBrowser.tabContainer;
    // A tab is loading while it has the "busy" attribute.
    new win.MutationObserver(changes => {
      this.checkSnail(win);
      for (const change of changes) {
        const tab = change.target;
        if (change.oldValue !== null && !tab.hasAttribute("busy") && tab.selected) {
          this.maybeHiccup(win);
        }
      }
    }).observe(tabs, { subtree: true, attributeFilter: ["busy"], attributeOldValue: true });
    tabs.addEventListener("TabSelect", () => this.checkSnail(win));
    // A new tab page (Ctrl+T, the + button) shows up a moment after the tab.
    tabs.addEventListener("TabOpen", event =>
      win.setTimeout(() => {
        this.maybePeek(win, event.target);
        if (Math.random() < this.SEASON_CHANCE) {
          this.flurry(win);
        }
      }, 600)
    );
    win.setTimeout(() => this.flurry(win), 1200);
    tabs.addEventListener("TabClose", event => this.ghost(win, event.target));
    // Typing in the address bar.
    win.addEventListener("input", event => {
      if (event.target?.closest?.("#urlbar")) {
        this.sparks(win, event.target);
      }
    }, true);
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

  // ── Sleepy tabs and Rainbow mode: styles on the window ─────────────────

  paintFlags(win) {
    for (const [name, attribute] of Object.entries(this.FLAGS)) {
      win.document.documentElement.toggleAttribute(attribute, this.on(name));
    }
  },

  // ── Power typing ───────────────────────────────────────────────────────

  /** A few sparks from where you're typing (at most every 30ms). */
  sparks(win, input) {
    const now = win.performance.now();
    if (!this.on("power") || this.still(win) || now - win.derpFun.sparked < 30 || input.localName !== "input") {
      return;
    }
    win.derpFun.sparked = now;
    const doc = win.document;
    const bar = doc.getElementById("urlbar");
    const box = bar.getBoundingClientRect();
    const field = input.getBoundingClientRect();
    const style = win.getComputedStyle(input);
    this.ruler ??= doc.createElementNS(HTML, "canvas").getContext("2d");
    this.ruler.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const caret = this.ruler.measureText(input.value.slice(0, input.selectionStart ?? input.value.length)).width;
    const x = Math.min(field.right, field.left + (parseFloat(style.paddingInlineStart) || 0) + caret - input.scrollLeft) - box.left;
    const y = field.top + field.height / 2 - box.top;
    for (let i = 0; i < 7; i++) {
      const spark = doc.createElementNS(HTML, "span");
      spark.className = "derp-spark";
      spark.style.left = `${x}px`;
      spark.style.top = `${y}px`;
      spark.style.background = CONFETTI[Math.floor(Math.random() * CONFETTI.length)];
      bar.append(spark);
      const angle = -Math.PI * (0.1 + Math.random() * 0.8);
      const reach = 10 + Math.random() * 18;
      spark
        .animate(
          [
            { transform: "translate(0, 0) scale(1)", opacity: 1 },
            { transform: `translate(${Math.cos(angle) * reach}px, ${Math.sin(angle) * reach}px) scale(0.3)`, opacity: 0 },
          ],
          { duration: 320 + Math.random() * 200, easing: "cubic-bezier(0.2, 0.7, 0.4, 1)" }
        )
        .finished.then(() => spark.remove());
    }
  },

  // ── Hiccups ────────────────────────────────────────────────────────────

  maybeHiccup(win) {
    const uri = win.gBrowser.currentURI;
    if (
      !this.on("hiccups") ||
      this.still(win) ||
      !(uri.schemeIs("https") || uri.schemeIs("http")) ||
      Math.random() >= this.HICCUP_CHANCE
    ) {
      return;
    }
    this.hiccup(win);
  },

  /** The page hops (twice), with a "hic!". */
  hiccup(win) {
    const doc = win.document;
    const browser = win.gBrowser.selectedBrowser;
    const page = browser.closest(".browserStack") ?? browser;
    page.animate(
      [
        { translate: "0 0" },
        { translate: "0 -14px", offset: 0.22 },
        { translate: "0 0", offset: 0.45 },
        { translate: "0 -6px", offset: 0.65 },
        { translate: "0 0" },
      ],
      { duration: 650, easing: "ease-out" }
    );
    const area = page.getBoundingClientRect();
    const hic = doc.createElementNS(HTML, "span");
    hic.className = "derp-hic";
    doc.l10n.setAttributes(hic, "derp-hic");
    hic.style.left = `${area.left + 24}px`;
    hic.style.top = `${area.top + 18}px`;
    hic.addEventListener("animationend", () => hic.remove());
    this.layer(doc).append(hic);
  },

  // ── Tab ghosts ─────────────────────────────────────────────────────────

  /** A closing tab leaves a ghost that drifts down over the page and fades (five at a time at most). */
  ghost(win, tab) {
    if (!this.on("ghosts") || this.still(win) || win.derpFun.ghosts >= 5) {
      return;
    }
    const where = tab.getBoundingClientRect();
    if (!where.width) {
      return;
    }
    const doc = win.document;
    const ghost = doc.createElementNS(HTML, "img");
    ghost.className = "derp-ghost";
    ghost.src = GHOST_URL;
    ghost.alt = "";
    ghost.style.left = `${where.left + where.width / 2 - 18}px`;
    ghost.style.top = `${where.top + where.height / 2 - 18}px`;
    win.derpFun.ghosts++;
    ghost.addEventListener("animationend", () => {
      ghost.remove();
      win.derpFun.ghosts--;
    });
    this.layer(doc).append(ghost);
  },

  // ── Seasons ────────────────────────────────────────────────────────────

  /** A flurry of the season's things, drifting down over the toolbar. */
  flurry(win) {
    if (!this.on("seasons") || this.still(win) || win.derpFun.flurry) {
      return;
    }
    const doc = win.document;
    const kinds = seasonOf(new Date());
    const box = doc.createElementNS(HTML, "div");
    box.className = "derp-flurry";
    for (let i = 0; i < 18; i++) {
      const bit = doc.createElementNS(HTML, "img");
      bit.alt = "";
      bit.src = SEASON_ART[kinds[i % kinds.length]];
      const size = 12 + Math.random() * 12;
      bit.style.cssText =
        `left: ${Math.random() * 100}%; width: ${size}px; height: ${size}px;` +
        `--drift: ${Math.round(Math.random() * 120 - 60)}px; --spin: ${Math.round(Math.random() * 540 - 270)}deg;` +
        `animation-duration: ${(2.8 + Math.random() * 2).toFixed(2)}s; animation-delay: ${(Math.random() * 1.4).toFixed(2)}s;`;
      box.append(bit);
    }
    win.derpFun.flurry = box;
    win.setTimeout(() => {
      box.remove();
      win.derpFun.flurry = null;
    }, 6500);
    this.layer(doc).append(box);
  },

  // ── Download duck ──────────────────────────────────────────────────────

  /** A duck carries the download along the toolbar to the downloads button,
   * drops it in, and waddles off. */
  carry(win) {
    const doc = win.document;
    const bar = doc.getElementById("nav-bar")?.getBoundingClientRect();
    if (!bar?.width || win.derpFun.carrying) {
      return;
    }
    const duck = doc.createElementNS(HTML, "div");
    duck.className = "derp-carry";
    for (const [cls, src] of [["derp-carry-duck", this.duckURL], ["derp-carry-parcel", PARCEL_URL]]) {
      const img = doc.createElementNS(HTML, "img");
      img.className = cls;
      img.src = src;
      img.alt = "";
      duck.append(img);
    }
    const from = doc.getElementById("urlbar-container")?.getBoundingClientRect() ?? bar;
    duck.style.top = `${bar.bottom - 30}px`;
    duck.style.left = `${from.left + 8}px`;
    win.derpFun.carrying = duck;
    this.layer(doc).append(duck);
    // The downloads button appears as the download starts: find it then.
    win.setTimeout(() => {
      const button = doc.getElementById("downloads-button")?.getBoundingClientRect();
      const to = button?.width ? button.left + button.width / 2 - 34 : bar.right - 60;
      duck.style.setProperty("--to", `${to}px`);
      duck.classList.add("derp-carry-go");
    }, 250);
    duck.addEventListener("animationend", event => {
      if (event.animationName === "derp-carry-walk") {
        duck.classList.add("derp-carry-drop");
      } else if (event.animationName === "derp-carry-off") {
        duck.remove();
        win.derpFun.carrying = null;
      }
    });
  },
};
