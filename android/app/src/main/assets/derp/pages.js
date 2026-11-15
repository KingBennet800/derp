"use strict";
// Shared by Derp's pages: talking to the app, and drawing dorks (dork-art.js).

/** Ask the Derp app something; the app keeps your dork and settings. */
async function derp(message) {
  try {
    const answer = await browser.runtime.sendNativeMessage("derp", message);
    return typeof answer === "string" ? JSON.parse(answer) : answer;
  } catch (e) {
    console.warn(`Derp app didn't answer ${message.type}:`, e);
    return null;
  }
}

const dorkURL = (dork, size = 256) => "data:image/svg+xml;charset=utf-8," + encodeURIComponent(draw(dork, size));

/** Your dork from the app, or a new random one (saved, so it sticks).
 * [petDays]: your days together, if your dork is a pet (Just for fun). */
async function myDork() {
  const state = (await derp({ type: "getState" })) || {};
  const petDays = typeof state.petDays === "number" ? state.petDays : null;
  if (state.dork) {
    const dork = normalizeDork(state.dork);
    // Older Derps saved no napping picture for the dork pet.
    if (!state.sleepy) saveDork(dork);
    return { dork, made: !!state.made, petDays };
  }
  const dork = randomDork();
  await saveDork(dork);
  return { dork, made: false, petDays };
}

/** Saves your dork, as drawn in the toolbar (and napping, eyes shut). */
function saveDork(dork) {
  return derp({ type: "setDork", dork, svg: draw(dork, 128), sleepy: draw({ ...dork, eyes: "sleepy" }, 128) });
}

// The look you picked (⋮ → Look): its accent on Derp's pages.
derp({ type: "getState" }).then(state => {
  const [light, dark] = state?.accent || [];
  if (!light || !dark) return;
  const style = document.createElement("style");
  style.textContent = `:root { --accent: ${light}; } @media (prefers-color-scheme: dark) { :root { --accent: ${dark}; } }`;
  document.head.append(style);
});

// ── For the bookmarks, history, passwords and import pages ────────────────

/** A web address's site, for showing ("en.wikipedia.org"). */
function hostOf(url) {
  try {
    return new URL(url).host.replace(/^www\./, "");
  } catch {
    return url;
  }
}

/** Only web addresses become links. */
const webURL = url => (/^https?:\/\//i.test(url) ? url : "#");

/** Builds an element: el("li", { className: "row" }, child, "text"). */
function el(tag, props = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children.filter(child => child != null && child !== false));
  return node;
}

/** A site's first letter on a color picked from its address. */
function siteTile(url, title, tag = "span") {
  const host = hostOf(url);
  const letter = [...(title || host).trim()][0]?.toUpperCase() || "?";
  let hash = 0;
  for (const ch of host) hash = (hash * 31 + ch.codePointAt(0)) | 0;
  const tile = el(tag, { className: "site", textContent: letter });
  tile.style.setProperty("--hue", String(Math.abs(hash) % 360));
  return tile;
}

/** Small icons, in the style of Derp's toolbar. */
function icon(name) {
  const paths = {
    close: '<path d="m4.75 4.75 6.5 6.5M11.25 4.75l-6.5 6.5"/>',
    search: '<circle cx="7.25" cy="7.25" r="4.25"/><path d="m10.4 10.4 2.6 2.6"/>',
  };
  const box = document.createElement("span");
  box.innerHTML = `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name]}</svg>`;
  return box.firstChild;
}

/** A round × button. */
function removeButton(label, onClick) {
  const button = el("button", { className: "lib-x", type: "button", title: label }, icon("close"));
  button.setAttribute("aria-label", label);
  button.addEventListener("click", onClick);
  return button;
}

const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
