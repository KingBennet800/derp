/* Dork pet, a Just for fun setting (off by default): your dork as a little
 * pet. Each day you use Derp is a day together, and some days unlock an
 * outfit for it (DerpDork's UNLOCKS), announced next to its button. It naps
 * there while you're away from the computer, and wiggles, happy, when you
 * point at it. It's all kept in this profile's prefs, like your dork. */

const HTML = "http://www.w3.org/1999/xhtml";
const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  CustomizableUI: "moz-src:///browser/components/customizableui/CustomizableUI.sys.mjs",
  setInterval: "resource://gre/modules/Timer.sys.mjs",
});

const BUTTON = "derp-dork-button";

export const DerpPet = {
  PREF: "derp.pet.enabled",
  DAYS: "derp.pet.days",
  LAST_DAY: "derp.pet.lastDay",
  // The most days together whose unlocks have been announced.
  SHOWN: "derp.pet.shown",
  // Away this long (seconds), your dork naps.
  NAP_AFTER: 5 * 60,

  init({ cssURL, dork }) {
    this.cssURL = cssURL;
    this.dork = dork;
    Services.obs.addObserver(win => this.watch(win), "browser-delayed-startup-finished");
    Services.prefs.addObserver(this.PREF, () => {
      if (this.on) {
        this.count();
      } else {
        this.nap(false);
      }
    });
    Cc["@mozilla.org/widget/useridleservice;1"].getService(Ci.nsIUserIdleService).addIdleObserver(this, this.NAP_AFTER);
    // A session can run past midnight: that's another day together.
    lazy.setInterval(() => this.count(), 60 * 60 * 1000);
  },

  get on() {
    return Services.prefs.getBoolPref(this.PREF, false);
  },

  get days() {
    return Services.prefs.getIntPref(this.DAYS, 0);
  },

  watch(win) {
    if (win.derpPet) {
      return;
    }
    win.derpPet = { toast: null };
    win.MozXULElement.insertFTLIfNeeded("derp/fun.ftl");
    win.windowUtils.loadSheetUsingURIString(this.cssURL, win.windowUtils.AUTHOR_SHEET);
    // Pointing at your dork makes it happy.
    win.addEventListener("mouseover", event => {
      const node = event.target.closest?.(`#${BUTTON}`);
      if (node && !node.contains(event.relatedTarget) && this.on && !this.dork.mood) {
        node.setAttribute("image", this.dork.dataURL({ ...this.dork.get(), eyes: "happy" }, 48));
        node.setAttribute("derp-petted", "");
      }
    });
    win.addEventListener("mouseout", event => {
      const node = event.target.closest?.(`#${BUTTON}`);
      if (node?.hasAttribute("derp-petted") && !node.contains(event.relatedTarget)) {
        node.removeAttribute("derp-petted");
        this.dork.paintButton(node);
      }
    });
    this.count();
  },

  button(win) {
    return lazy.CustomizableUI.getWidget(BUTTON)?.forWindow(win)?.node ?? null;
  },

  /** Today counts as a day together (once), which may unlock an outfit. */
  count() {
    if (!this.on) {
      return;
    }
    const now = new Date();
    const today = `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}`;
    if (Services.prefs.getStringPref(this.LAST_DAY, "") !== today) {
      Services.prefs.setStringPref(this.LAST_DAY, today);
      Services.prefs.setIntPref(this.DAYS, this.days + 1);
    }
    const win = Services.wm.getMostRecentWindow("navigator:browser");
    const shown = Services.prefs.getIntPref(this.SHOWN, 0);
    const earned = this.dork.UNLOCKS.filter(u => u.days > shown && u.days <= this.days);
    if (win?.derpPet && earned.length) {
      Services.prefs.setIntPref(this.SHOWN, this.days);
      this.announce(win, earned.at(-1)).catch(console.error);
    }
  },

  /** "Your dork unlocked a crown!", by its button, with your dork wearing it. */
  async announce(win, unlock) {
    const doc = win.document;
    win.derpPet.toast?.remove();
    const h = (tag, attrs = {}, ...children) => {
      const el = doc.createElementNS(HTML, tag);
      for (const [k, v] of Object.entries(attrs)) {
        el.setAttribute(k, v);
      }
      el.append(...children);
      return el;
    };
    const dork = this.dork.get();
    const wearing = { ...dork, [unlock.part]: unlock.value };
    const what = await doc.l10n.formatValue(`derp-pet-${unlock.value}`);
    const text = h("p", { class: "derp-pet-text" });
    doc.l10n.setAttributes(text, dork.name ? "derp-pet-unlocked-named" : "derp-pet-unlocked", { name: dork.name, what });
    const together = h("p", { class: "derp-pet-days" });
    doc.l10n.setAttributes(together, "derp-pet-days", { days: unlock.days });
    const tryOn = h("button", { class: "primary", "data-l10n-id": "derp-pet-try" });
    const later = h("button", { "data-l10n-id": "derp-pet-later" });
    const toast = h(
      "div",
      { class: "derp-pet-toast", role: "status" },
      h("img", { src: this.dork.dataURL(wearing, 128), alt: "" }),
      h("div", {}, text, together, h("div", { class: "derp-pet-actions" }, later, tryOn))
    );
    const close = () => {
      toast.classList.add("derp-pet-gone");
      win.setTimeout(() => toast.remove(), 300);
      if (win.derpPet.toast === toast) {
        win.derpPet.toast = null;
      }
    };
    tryOn.addEventListener("click", () => {
      this.dork.set({ [unlock.part]: unlock.value });
      close();
    });
    later.addEventListener("click", close);
    win.setTimeout(close, 20000);
    // Under your dork's button, or the window's top corner if it's not there.
    const at = this.button(win)?.getBoundingClientRect();
    toast.style.top = `${at?.height ? at.bottom + 8 : 8}px`;
    toast.style.insetInlineEnd = `${at?.height ? Math.max(8, win.innerWidth - at.right) : 8}px`;
    (doc.body ?? doc.documentElement).append(toast);
    win.derpPet.toast = toast;
  },

  // Away and back: the user idle service.
  observe(subject, topic) {
    if (topic === "idle" || topic === "active") {
      this.nap(topic === "idle" && this.on);
    }
  },

  /** Your dork naps (sleepy eyes, Zzz) or wakes up (with a little hop). */
  nap(asleep) {
    if (!!this.dork.mood === asleep) {
      return;
    }
    this.dork.mood = asleep ? "sleepy" : null;
    this.dork.refresh();
    for (const win of Services.wm.getEnumerator("navigator:browser")) {
      const node = this.button(win);
      if (!node) {
        continue;
      }
      node.toggleAttribute("derp-napping", asleep);
      if (!asleep) {
        node.setAttribute("derp-waking", "");
        win.setTimeout(() => node.removeAttribute("derp-waking"), 700);
      }
    }
  },
};
