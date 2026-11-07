"use strict";
// History: newest first, by day, searchable, 200 at a time.
const list = document.getElementById("list");
const empty = document.getElementById("empty");
const search = document.getElementById("q");
const more = document.getElementById("more");
const PAGE = 200;
let oldest = Infinity;
let lastDay = "";

function day(time) {
  const date = new Date(time);
  const midnight = d => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const daysAgo = Math.round((midnight(new Date()) - midnight(date)) / 86400000);
  if (daysAgo === 0) return "Today";
  if (daysAgo === 1) return "Yesterday";
  const sameYear = date.getFullYear() === new Date().getFullYear();
  return date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric", year: sameYear ? undefined : "numeric" });
}

function row(item) {
  const title = item.title || hostOf(item.url);
  const time = new Date(item.visited).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  const li = el("li", {},
    el("a", { className: "lib-main", href: webURL(item.url) },
      siteTile(item.url, title),
      el("span", { className: "lib-text" },
        el("span", { className: "lib-title", textContent: title }),
        el("span", { className: "lib-sub", textContent: `${time} · ${hostOf(item.url)}` }))),
    removeButton("Remove from history", async () => {
      await derp({ type: "history.remove", url: item.url });
      for (const other of [...list.querySelectorAll("li[data-url]")]) {
        if (other.dataset.url === item.url) other.remove();
      }
    }));
  li.dataset.url = item.url;
  return li;
}

async function load(reset) {
  if (reset) {
    oldest = Infinity;
    lastDay = "";
    list.replaceChildren();
  }
  const query = search.value.trim();
  const items = (await derp({ type: "history.list", query, before: Number.isFinite(oldest) ? oldest : undefined, limit: PAGE }))?.items || [];
  for (const item of items) {
    const label = day(item.visited);
    if (label !== lastDay) {
      list.append(el("li", { className: "lib-day", textContent: label }));
      lastDay = label;
    }
    list.append(row(item));
    oldest = Math.min(oldest, item.visited);
  }
  more.hidden = items.length < PAGE;
  empty.hidden = list.children.length > 0;
  empty.textContent = query ? `Nothing in your history matches “${query}”.` : "No history yet. The pages you visit show up here.";
}

search.addEventListener("input", () => load(true));
more.addEventListener("click", () => load(false));
document.getElementById("clear").addEventListener("click", async () => {
  if (!confirm("Clear all your history? Your bookmarks and passwords stay.")) return;
  await derp({ type: "history.clear" });
  load(true);
});
load(true);
