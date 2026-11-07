/* Duck mode: a joke setting, off by default (Settings → Derp → Just for fun).
 * 1 in 10 times you press Enter in the address bar, a duck waddles across it
 * and eats what you typed, instead of taking you there. */

const HTML = "http://www.w3.org/1999/xhtml";

/** The duck, facing left (the way it walks). The Android app draws the same one. */
export const DUCK_URL =
  "data:image/svg+xml;charset=utf-8," +
  encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <path d="M26 17c3-2 4.2-5 3.2-7.4C28 12.6 26 14 24 14z" fill="#FFD43B"/>
  <ellipse cx="18" cy="21" rx="10" ry="7" fill="#FFD43B"/>
  <circle cx="11" cy="11" r="6" fill="#FFD43B"/>
  <path d="M6 10.4c-2.2 0-4.6.7-5.2 1.7.7 1.1 3.2 1.7 5.4 1.4z" fill="#FF8A1F"/>
  <circle cx="9.8" cy="9.4" r="1.3" fill="#222"/>
  <path d="M14 21c2.5 2.5 6 2.8 9 1" fill="none" stroke="#E0A800" stroke-width="1.6" stroke-linecap="round"/>
  <path d="M14.5 28v2.5H12M20.5 28v2.5H18" fill="none" stroke="#FF8A1F" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`);

export const DerpDuck = {
  PREF: "derp.duck.enabled",
  CHANCE: 0.1,

  init({ cssURL }) {
    this.cssURL = cssURL;
    Services.obs.addObserver(win => this.watch(win), "browser-delayed-startup-finished");
  },

  watch(win) {
    if (win.derpDuck) {
      return;
    }
    win.derpDuck = { busy: false };
    win.MozXULElement.insertFTLIfNeeded("derp/duck.ftl");
    win.windowUtils.loadSheetUsingURIString(this.cssURL, win.windowUtils.AUTHOR_SHEET);
    // On the window, capturing: this runs before the address bar's own Enter.
    win.addEventListener("keydown", event => this.onKey(win, event), true);
  },

  onKey(win, event) {
    if (event.key !== "Enter" || event.isComposing || !event.target?.closest?.("#urlbar")) {
      return;
    }
    const urlbar = win.gURLBar;
    if (win.derpDuck.busy) {
      // The duck is still eating.
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    const text = urlbar?.value ?? "";
    if (!text.trim() || !Services.prefs.getBoolPref(this.PREF, false) || Math.random() >= this.CHANCE) {
      return;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    this.waddle(win, urlbar, text);
  },

  /** The duck walks in from the end of the address bar, eating as it goes, and quacks. */
  waddle(win, urlbar, text) {
    win.derpDuck.busy = true;
    urlbar.view?.close();
    const doc = win.document;
    const bar = doc.getElementById("urlbar");
    const duck = doc.createElementNS(HTML, "div");
    duck.className = "derp-duck";
    const img = doc.createElementNS(HTML, "img");
    img.src = DUCK_URL;
    img.alt = "";
    const quack = doc.createElementNS(HTML, "span");
    quack.className = "derp-duck-quack";
    doc.l10n.setAttributes(quack, "derp-duck-quack");
    duck.append(img, quack);
    bar.append(duck);

    // The duck stands at the end of what's left of the text: measure it.
    const input = urlbar.inputField ?? bar.querySelector("input");
    const style = win.getComputedStyle(input);
    const ruler = doc.createElementNS(HTML, "canvas").getContext("2d");
    ruler.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const box = bar.getBoundingClientRect();
    const origin = input.getBoundingClientRect().left - box.left + (parseFloat(style.paddingInlineStart) || 0);
    const room = Math.max(0, box.width - 40);
    const at = kept => Math.min(room, origin + ruler.measureText(text.slice(0, kept)).width);

    const still = win.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const duration = still ? 0 : Math.min(2400, 900 + text.length * 45);
    const start = win.performance.now();
    const step = now => {
      const t = duration ? Math.min(1, (now - start) / duration) : 1;
      const kept = Math.round(text.length * (1 - t));
      urlbar.value = text.slice(0, kept);
      duck.style.insetInlineStart = `${at(kept)}px`;
      if (t < 1) {
        win.requestAnimationFrame(step);
        return;
      }
      urlbar.value = "";
      duck.classList.add("derp-duck-done");
      win.setTimeout(() => {
        duck.remove();
        win.derpDuck.busy = false;
        urlbar.focus();
      }, 1100);
    };
    win.requestAnimationFrame(step);
  },
};
