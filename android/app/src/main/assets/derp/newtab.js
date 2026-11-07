"use strict";
// Your dork lives in the toolbar; make sure there is one (a random one until you make yours).
myDork();
// The search box is a shortcut to the address bar.
document.getElementById("search").addEventListener("click", () => derp({ type: "focusUrl" }));
// Poke Derp and it wiggles, like on desktop.
const mark = document.getElementById("mark");
mark.addEventListener("click", () => {
  mark.classList.remove("poked");
  void mark.offsetWidth;
  mark.classList.add("poked");
});
// Your newest bookmarks, under the shortcuts.
(async () => {
  const items = (await derp({ type: "bookmarks.list", limit: 8 }))?.items || [];
  if (!items.length) return;
  document.getElementById("mark-tiles").replaceChildren(
    ...items.map(item => {
      const title = item.title || hostOf(item.url);
      return el("a", { href: webURL(item.url) }, siteTile(item.url, title, "b"), el("span", { textContent: title }));
    })
  );
  document.getElementById("marks").hidden = false;
})();
