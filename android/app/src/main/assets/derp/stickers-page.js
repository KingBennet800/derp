"use strict";
// Screenshot with stickers (⋮ → Screenshot with stickers): the app takes the
// picture and opens this page, which puts desktop Derp's sticker editor
// (stickers.js) on it. Save sends the finished picture back to the app,
// which keeps it in Pictures/Derp and closes this tab; so does Cancel.

const blobToDataURL = blob =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });

(async () => {
  const state = (await derp({ type: "stickers.get" })) || {};
  // Restored after Derp was closed, the picture is gone: say so, and let it close.
  if (!state.image) {
    document.getElementById("empty").hidden = false;
    document.getElementById("close").addEventListener("click", () => derp({ type: "stickers.close" }));
    return;
  }
  const dork = state.dork ? normalizeDork(state.dork) : null;
  const stickers = [
    ...(dork ? [{ id: "dork", url: dorkURL(dork, 256), label: dork.name || "Your dork" }] : []),
    ...Object.entries(CRITTERS).map(([id, url]) => ({ id, url })),
  ];
  await DerpStickerEditor.open({
    root: document.getElementById("editor"),
    image: state.image,
    stickers,
    labels: {
      title: "Screenshot with stickers",
      hint: "Tap a sticker to add it. Drag it to move it; drag its round handle to resize and turn it.",
      save: "Save",
      cancel: "Cancel",
      remove: "Remove sticker",
    },
    onSave: async blob => {
      await derp({ type: "stickers.save", png: await blobToDataURL(blob) });
    },
    onClose: () => derp({ type: "stickers.close" }),
  });
})();
