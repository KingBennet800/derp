/* What's new: after an update brings something new, the first window shows
 * what came with it (whatsnew.json, which Derp for Android shows too), each
 * with where to find it. Settings → Derp → Updates shows it again. A new Derp
 * (still making its dork) needs no telling, and updates with nothing listed
 * (the weekly engine updates) pass quietly. */

const HTML = "http://www.w3.org/1999/xhtml";

/** Whether version [a] (like "2.1.0") is newer than [b]. */
export function newer(a, b) {
  const pa = String(a).split(".").map(Number);
  const pb = String(b).split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] || 0) - (pb[i] || 0);
    if (diff) {
      return diff > 0;
    }
  }
  return false;
}

export const DerpWhatsNew = {
  // The newest version whose news you've seen.
  PREF: "derp.whatsNew.seen",

  init({ cssURL, dataURL, dork, updates }) {
    this.cssURL = cssURL;
    this.dataURL = dataURL;
    this.dork = dork;
    this.updates = updates;
    const greet = win => {
      Services.obs.removeObserver(greet, "browser-delayed-startup-finished");
      this.check(win).catch(console.error);
    };
    Services.obs.addObserver(greet, "browser-delayed-startup-finished");
  },

  async releases() {
    return (await fetch(this.dataURL)).json();
  },

  /** Anything new since you last looked? Shows it, after the window settles. */
  async check(win) {
    const version = await this.updates.version();
    if (!version) {
      return;
    }
    const seen = Services.prefs.getStringPref(this.PREF, "");
    const done = () => Services.prefs.setStringPref(this.PREF, version);
    if (!this.dork.made || (seen && !newer(version, seen))) {
      done();
      return;
    }
    // Updating from before Derp kept track (2.0.x): this version's news.
    const fresh = (await this.releases()).filter(r =>
      seen ? newer(r.version, seen) && !newer(r.version, version) : r.version === version
    );
    if (!fresh.length) {
      done();
      return;
    }
    // Seen once it's shown (not if the window closes first).
    win.setTimeout(() => {
      if (!win.closed) {
        this.show(win, fresh, version);
        done();
      }
    }, 1500);
  },

  /** This version's news, from Settings (Updates → What's new). */
  async showCurrent(win) {
    const version = await this.updates.version();
    const releases = await this.releases();
    const fresh = releases.filter(r => !newer(r.version, version)).slice(0, 1);
    if (fresh.length) {
      this.show(win, fresh, fresh[0].version);
    }
  },

  /** A card over the window: your dork, "What's new in Derp 2.1.0", the new things. */
  show(win, releases, version) {
    const doc = win.document;
    if (doc.querySelector(".derp-whatsnew")) {
      return;
    }
    if (!win.derpWhatsNew) {
      win.derpWhatsNew = true;
      win.MozXULElement.insertFTLIfNeeded("derp/whatsnew.ftl");
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
    const title = h("h2", { id: "derp-whatsnew-title" });
    doc.l10n.setAttributes(title, "derp-whatsnew-title", { version });
    const list = h("div", { class: "derp-whatsnew-list" });
    for (const release of releases) {
      if (releases.length > 1) {
        const label = h("p", { class: "derp-whatsnew-version" });
        doc.l10n.setAttributes(label, "derp-whatsnew-version", { version: release.version, title: release.title });
        list.append(label);
      }
      for (const item of release.items) {
        list.append(
          h(
            "div",
            { class: "derp-whatsnew-item" },
            h("span", { class: "derp-whatsnew-icon", "aria-hidden": "true" }, item.icon),
            h(
              "div",
              {},
              h("strong", {}, item.title),
              h("p", {}, item.text),
              item.desktop ? h("p", { class: "derp-whatsnew-where" }, item.desktop) : ""
            )
          )
        );
      }
    }
    const done = h("button", { class: "derp-whatsnew-done" });
    doc.l10n.setAttributes(done, "derp-whatsnew-done");
    const card = h(
      "div",
      { class: "derp-whatsnew-card", role: "dialog", "aria-modal": "true", "aria-labelledby": "derp-whatsnew-title", tabindex: "-1" },
      h(
        "div",
        { class: "derp-whatsnew-head" },
        h("img", { src: this.dork.dataURL(undefined, 128), alt: "" }),
        h("div", {}, title, h("p", {}, releases[0].title))
      ),
      list,
      h("div", { class: "derp-whatsnew-actions" }, done)
    );
    const overlay = h("div", { class: "derp-whatsnew" }, card);
    const close = () => {
      overlay.classList.add("derp-whatsnew-gone");
      win.setTimeout(() => overlay.remove(), 220);
    };
    done.addEventListener("click", close);
    overlay.addEventListener("pointerdown", e => e.target === overlay && close());
    card.addEventListener("keydown", e => e.key === "Escape" && close());
    (doc.body ?? doc.documentElement).append(overlay);
    done.focus();
  },
};
