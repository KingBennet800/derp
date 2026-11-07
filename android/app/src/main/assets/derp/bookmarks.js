"use strict";
// Bookmarks: newest first, searchable; tap one to go there.
const list = document.getElementById("list");
const empty = document.getElementById("empty");
const search = document.getElementById("q");

function row(item) {
  const title = item.title || hostOf(item.url);
  const li = el("li", {},
    el("a", { className: "lib-main", href: webURL(item.url) },
      siteTile(item.url, title),
      el("span", { className: "lib-text" },
        el("span", { className: "lib-title", textContent: title }),
        el("span", { className: "lib-sub", textContent: hostOf(item.url) }))),
    removeButton("Remove bookmark", async () => {
      await derp({ type: "bookmarks.remove", url: item.url });
      li.remove();
      if (!list.children.length) show();
    }));
  return li;
}

async function show() {
  const query = search.value.trim();
  const items = (await derp({ type: "bookmarks.list", query }))?.items || [];
  list.replaceChildren(...items.map(row));
  empty.hidden = items.length > 0;
  empty.textContent = query
    ? `No bookmarks match “${query}”.`
    : "No bookmarks yet. On any page, open the ⋮ menu and tap ☆ to add one, or import them from another browser.";
}

search.addEventListener("input", show);
show();
