"use strict";
// Derp's pages (derp://pages/…, the same pages Derp for Android shows) talk
// to the app the way they do there, with browser.runtime.sendNativeMessage;
// here it goes through WebKit's message handler, which answers with a promise.
(() => {
  if (location.protocol !== "derp:") return;
  const handler = window.webkit?.messageHandlers?.derp;
  if (!handler) return;

  // The dork is drawn by the page (dork-art.js), so its pictures are made here too.
  async function picture(svg, size) {
    const img = new Image();
    img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
    await img.decode();
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = size;
    canvas.getContext("2d").drawImage(img, 0, 0, size, size);
    return canvas.toDataURL("image/png");
  }

  async function send(message) {
    if (message?.type === "setDork" && typeof draw === "function") {
      try {
        const png = await picture(draw(message.dork, 256), 256);
        const sleepyPng = await picture(draw({ ...message.dork, eyes: "sleepy" }, 256), 256);
        message = { ...message, png, sleepyPng };
      } catch (e) {
        console.warn("Derp: couldn't draw your dork", e);
      }
    }
    return handler.postMessage(message);
  }

  window.browser = { runtime: { sendNativeMessage: (_app, message) => send(message) } };
})();
