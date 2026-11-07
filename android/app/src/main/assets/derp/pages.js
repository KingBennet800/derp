"use strict";
// Shared by Derp's pages: talking to the app, and drawing dorks (dork-art.js).

/** Ask the Derp app something; the app keeps your dork and settings. */
async function derp(message) {
  try {
    return await browser.runtime.sendNativeMessage("derp", message);
  } catch (e) {
    console.warn(`Derp app didn't answer ${message.type}:`, e);
    return null;
  }
}

const dorkURL = (dork, size = 256) => "data:image/svg+xml;charset=utf-8," + encodeURIComponent(draw(dork, size));

/** Your dork from the app, or a new random one (saved, so it sticks). */
async function myDork() {
  const state = (await derp({ type: "getState" })) || {};
  if (state.dork) return { dork: normalizeDork(state.dork), made: !!state.made };
  const dork = randomDork();
  await saveDork(dork);
  return { dork, made: false };
}

function saveDork(dork) {
  return derp({ type: "setDork", dork, svg: draw(dork, 128) });
}
