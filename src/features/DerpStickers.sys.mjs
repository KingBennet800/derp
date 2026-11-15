/* Screenshot with stickers: in a page's context menu, it takes a picture of
 * what you see of the page and opens the sticker editor (stickers.js) over
 * the window, with your dork and Derp's critters among the stickers. Save
 * puts the picture in your Downloads folder; Copy puts it on the clipboard.
 * Derp for Android has the same editor (⋮ → Screenshot with stickers). */

const HTML = "http://www.w3.org/1999/xhtml";
const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  Downloads: "resource://gre/modules/Downloads.sys.mjs",
});

export const DerpStickers = {
  init({ cssURL, scriptURL, dork, critters }) {
    this.cssURL = cssURL;
    this.scriptURL = scriptURL;
    this.dork = dork;
    this.critters = critters;
    Services.obs.addObserver(win => this.watch(win), "browser-delayed-startup-finished");
  },

  watch(win) {
    const doc = win.document;
    const menu = doc.getElementById("contentAreaContextMenu");
    if (!menu || doc.getElementById("derp-stickers-menuitem")) {
      return;
    }
    win.MozXULElement.insertFTLIfNeeded("derp/stickers.ftl");
    const item = doc.createXULElement("menuitem");
    item.id = "derp-stickers-menuitem";
    doc.l10n.setAttributes(item, "derp-stickers-menu");
    const screenshot = doc.getElementById("context-take-screenshot");
    if (screenshot) {
      screenshot.after(item);
    } else {
      menu.append(item);
    }
    item.addEventListener("command", () => this.open(win).catch(console.error));
  },

  /** A picture of what you see of the current page, as a blob: URL. */
  async capture(win) {
    const global = win.gBrowser.selectedBrowser.browsingContext.currentWindowGlobal;
    const bitmap = await global.drawSnapshot(null, win.devicePixelRatio, "white");
    const canvas = win.document.createElementNS(HTML, "canvas");
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    canvas.getContext("2d").drawImage(bitmap, 0, 0);
    bitmap.close();
    const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"));
    return win.URL.createObjectURL(blob);
  },

  async open(win) {
    const doc = win.document;
    if (doc.querySelector(".derp-stickers")) {
      return;
    }
    if (!win.DerpStickerEditor) {
      win.windowUtils.loadSheetUsingURIString(this.cssURL, win.windowUtils.AUTHOR_SHEET);
      Services.scriptloader.loadSubScript(this.scriptURL, win);
    }
    const image = await this.capture(win);
    const [title, hint, save, copy, cancel, remove, you] = await doc.l10n.formatValues(
      ["title", "hint", "save", "copy", "cancel", "remove", "you"].map(id => `derp-stickers-${id}`)
    );
    const dork = this.dork.get();
    const stickers = [
      { id: "dork", url: this.dork.dataURL(dork, 256), label: dork.name || you },
      ...Object.entries(this.critters).map(([id, url]) => ({ id, url })),
    ];
    const overlay = doc.createElementNS(HTML, "div");
    overlay.className = "derp-stickers";
    (doc.body ?? doc.documentElement).append(overlay);
    const close = () => {
      overlay.remove();
      win.URL.revokeObjectURL(image);
      win.gBrowser.selectedBrowser.focus();
    };
    // Clicking the dimmed window around the editor closes it too.
    overlay.addEventListener("pointerdown", e => {
      if (e.target === overlay) {
        close();
      }
    });
    await win.DerpStickerEditor.open({
      root: overlay,
      image,
      stickers,
      labels: { title, hint, save, copy, cancel, remove },
      onSave: async blob => {
        const path = await this.saveFile(blob);
        close();
        this.note(win, "derp-stickers-saved", path);
      },
      onCopy: async blob => {
        await win.navigator.clipboard.write([new win.ClipboardItem({ "image/png": blob })]);
        close();
        this.note(win, "derp-stickers-copied");
      },
      onClose: close,
    });
    overlay.querySelector(".derp-st")?.focus();
  },

  /** Saves into Downloads as "Derp screenshot 2026-11-14 at 10.20.30.png". */
  async saveFile(blob) {
    const dir = await lazy.Downloads.getPreferredDownloadsDirectory();
    const now = new Date();
    const two = n => String(n).padStart(2, "0");
    const stamp = `${now.getFullYear()}-${two(now.getMonth() + 1)}-${two(now.getDate())} at ${two(now.getHours())}.${two(now.getMinutes())}.${two(now.getSeconds())}`;
    let path = PathUtils.join(dir, `Derp screenshot ${stamp}.png`);
    for (let n = 2; await IOUtils.exists(path); n++) {
      path = PathUtils.join(dir, `Derp screenshot ${stamp} (${n}).png`);
    }
    await IOUtils.write(path, new Uint8Array(await blob.arrayBuffer()), { mode: "create" });
    return path;
  },

  /** "Saved to Downloads [Show]" or "Copied", for a few seconds. */
  note(win, l10nId, path = null) {
    const doc = win.document;
    const note = doc.createElementNS(HTML, "div");
    note.className = "derp-st-note";
    note.setAttribute("role", "status");
    const text = doc.createElementNS(HTML, "span");
    doc.l10n.setAttributes(text, l10nId);
    note.append(text);
    if (path) {
      const show = doc.createElementNS(HTML, "button");
      doc.l10n.setAttributes(show, "derp-stickers-show");
      show.addEventListener("click", () => {
        const file = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
        file.initWithPath(path);
        file.reveal();
        note.remove();
      });
      note.append(show);
    }
    (doc.body ?? doc.documentElement).append(note);
    win.setTimeout(() => note.remove(), 5000);
  },
};
