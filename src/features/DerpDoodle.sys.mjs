/* Doodle: Derp's search engine (by policy in config/policies.json, and the
 * default), with its results from Google or DuckDuckGo, as you pick: right
 * after you make your dork when you first start Derp, or later in Settings →
 * Derp → Doodle. Doodle's address is Google's, marked doodle=1 (its
 * suggestions' too); with DuckDuckGo picked, Derp sends those to DuckDuckGo
 * instead, before anything reaches Google, with Doodle's colors in the
 * address, light or dark as Derp is. Doodle's look (doodle-look/) dresses
 * both. Derp also tells Google whether it's light or dark, the way Chrome
 * does (its Sec-CH-Prefers-Color-Scheme hint, which Google doesn't get from
 * Firefox otherwise), so Google's pages come in Derp's theme. */

const HTML = "http://www.w3.org/1999/xhtml";

// DuckDuckGo's settings for Doodle: links and addresses in Derp's colors,
// light and dark (DuckDuckGo stays light unless asked). They mark its pages
// as Doodle's, for Doodle's look (doodle-ddg.js). Derp for Android's are the
// same (Browser.kt).
export const DDG_LIGHT = "k9=2f6feb&kaa=7a52c7&kx=0f8a74";
export const DDG_DARK = "kae=d&k9=86b1ff&kaa=a98bf0&kx=34c6a0";

/** Doodle's logo (brand/doodle.svg). */
const LOGO =
  "data:image/svg+xml;charset=utf-8," +
  encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="6 6 268 84">
  <defs><linearGradient id="ink" x1="10" y1="0" x2="270" y2="0" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#7CC242"/><stop offset=".45" stop-color="#1FB5A0"/><stop offset="1" stop-color="#2F6FEB"/>
  </linearGradient></defs>
  <g fill="none" stroke="url(#ink)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="30" cy="61" r="17"/><path d="M47 14V80"/><circle cx="170" cy="61" r="17"/>
    <path d="M187 14V80M208 14V71q0 9 8 9"/><path d="M229 61H262A17 17 0 1 0 256 74"/>
  </g>
  <g stroke="#18181B" stroke-width="5"><circle cx="78" cy="61" r="19" fill="#fff"/><circle cx="124" cy="61" r="19" fill="#fff"/></g>
  <g fill="#18181B"><circle cx="82" cy="66" r="8"/><circle cx="128" cy="66" r="8"/></g>
</svg>`);

export const DerpDoodle = {
  // "google" or "duckduckgo": where Doodle's results come from.
  PREF: "derp.doodle.results",
  MADE_PREF: "derp.dork.made",

  init({ cssURL }) {
    this.cssURL = cssURL;
    Services.obs.addObserver(this, "http-on-modify-request");
    // Making your dork is the first step of starting Derp; picking Doodle's
    // results is the next.
    Services.prefs.addObserver(this.MADE_PREF, () => {
      const win = Services.wm.getMostRecentWindow("navigator:browser");
      if (Services.prefs.getBoolPref(this.MADE_PREF, false) && !this.picked && win) {
        win.setTimeout(() => this.ask(win), 400);
      }
    });
  },

  get source() {
    return Services.prefs.getStringPref(this.PREF, "google") === "duckduckgo" ? "duckduckgo" : "google";
  },

  get picked() {
    return Services.prefs.prefHasUserValue(this.PREF);
  },

  // Settings → Website appearance: dark, light, or (2) following the theme.
  dark() {
    const appearance = Services.prefs.getIntPref("layout.css.prefers-color-scheme.content-override", 2);
    return appearance === 2 ? Services.appinfo.contentThemeDerivedColorSchemeIsDark : appearance === 0;
  },

  /** A Doodle search on DuckDuckGo for [query]. */
  duckURL(query) {
    return `https://duckduckgo.com/?q=${encodeURIComponent(query)}&${this.dark() ? DDG_DARK : DDG_LIGHT}&kt=system-ui&ka=system-ui`;
  },

  observe(subject) {
    const channel = subject.QueryInterface(Ci.nsIHttpChannel);
    const host = channel.URI.host;
    if (host !== "www.google.com" && host !== "duckduckgo.com") {
      return;
    }
    const page = channel.loadInfo.externalContentPolicyType === Ci.nsIContentPolicy.TYPE_DOCUMENT;
    const url = URL.parse(channel.URI.spec);
    if (!url) {
      return;
    }
    if (host === "duckduckgo.com") {
      // A Doodle search on DuckDuckGo, in the colors for Derp's theme now.
      const [from, to] = this.dark() ? [DDG_LIGHT, DDG_DARK] : [DDG_DARK, DDG_LIGHT];
      if (page && url.search.includes(from)) {
        channel.redirectTo(Services.io.newURI(channel.URI.spec.replace(from, to)));
      }
      return;
    }
    if (this.source === "duckduckgo" && url.searchParams.get("doodle") === "1") {
      const query = url.searchParams.get("q") ?? "";
      if (page && url.pathname === "/search") {
        channel.redirectTo(Services.io.newURI(this.duckURL(query)));
        return;
      }
      if (url.pathname === "/complete/search") {
        channel.redirectTo(Services.io.newURI(`https://duckduckgo.com/ac/?q=${encodeURIComponent(query)}&type=list`));
        return;
      }
    }
    if (page) {
      channel.setRequestHeader("Sec-CH-Prefers-Color-Scheme", this.dark() ? "dark" : "light", false);
    }
  },

  /** "Where should Doodle's results come from?": Google or DuckDuckGo, as a
   * card over the window. Closing it without picking keeps Google. */
  ask(win) {
    const doc = win.document;
    if (win.closed || doc.querySelector(".derp-doodle-ask")) {
      return;
    }
    win.MozXULElement.insertFTLIfNeeded("derp/doodle.ftl");
    if (!win.derpDoodleStyled) {
      win.derpDoodleStyled = true;
      win.windowUtils.loadSheetUsingURIString(this.cssURL, win.windowUtils.AUTHOR_SHEET);
    }
    const h = (tag, attrs = {}, ...children) => {
      const el = doc.createElementNS(HTML, tag);
      for (const [k, v] of Object.entries(attrs)) {
        el.setAttribute(k, v);
      }
      el.append(...children);
      return el;
    };
    const say = (el, id) => {
      doc.l10n.setAttributes(el, id);
      return el;
    };
    const option = (source, icon) =>
      h(
        "button",
        { class: "derp-doodle-option", "data-source": source },
        h("span", { class: "derp-doodle-icon", "aria-hidden": "true" }, icon),
        h("span", {}, say(h("strong"), `derp-doodle-${source}`), say(h("span"), `derp-doodle-${source}-about`))
      );
    const card = h(
      "div",
      { class: "derp-doodle-card", role: "dialog", "aria-modal": "true", "aria-labelledby": "derp-doodle-title" },
      h("img", { class: "derp-doodle-logo", src: LOGO, alt: "Doodle" }),
      say(h("h2", { id: "derp-doodle-title" }), "derp-doodle-ask"),
      say(h("p"), "derp-doodle-ask-about"),
      h("div", { class: "derp-doodle-options" }, option("google", "🌍"), option("duckduckgo", "🦆")),
      say(h("p", { class: "derp-doodle-later" }), "derp-doodle-later")
    );
    const overlay = h("div", { class: "derp-doodle-ask" }, card);
    const pick = source => {
      Services.prefs.setStringPref(this.PREF, source);
      overlay.classList.add("derp-doodle-gone");
      win.setTimeout(() => overlay.remove(), 220);
    };
    card.addEventListener("click", e => {
      const button = e.target.closest("[data-source]");
      if (button) {
        pick(button.dataset.source);
      }
    });
    overlay.addEventListener("pointerdown", e => e.target === overlay && pick(this.source));
    card.addEventListener("keydown", e => e.key === "Escape" && pick(this.source));
    (doc.body ?? doc.documentElement).append(overlay);
    card.querySelector("button")?.focus();
  },
};
