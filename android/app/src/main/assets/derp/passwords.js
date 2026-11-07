"use strict";
// Passwords: sites and usernames; showing or copying a password asks for
// your screen lock first (the app does that).
const list = document.getElementById("list");
const empty = document.getElementById("empty");
const search = document.getElementById("q");
const offer = document.getElementById("offer");
const HIDDEN = "••••••••";

function row(item) {
  const site = hostOf(item.origin);
  const secret = el("span", { className: "lib-secret", textContent: HIDDEN });
  const status = el("span", { className: "lib-flash", role: "status" });
  const show = el("button", { className: "lib-chip", type: "button", textContent: "Show" });
  const copy = el("button", { className: "lib-chip", type: "button", textContent: "Copy" });
  let hideAgain;
  show.addEventListener("click", async () => {
    if (secret.textContent !== HIDDEN) {
      secret.textContent = HIDDEN;
      show.textContent = "Show";
      return;
    }
    const answer = await derp({ type: "logins.reveal", guid: item.guid });
    if (answer?.password == null) {
      if (!answer?.cancelled) flash(status, "Couldn’t show it");
      return;
    }
    secret.textContent = answer.password;
    show.textContent = "Hide";
    clearTimeout(hideAgain);
    hideAgain = setTimeout(() => {
      secret.textContent = HIDDEN;
      show.textContent = "Show";
    }, 30000);
  });
  copy.addEventListener("click", async () => {
    const answer = await derp({ type: "logins.copy", guid: item.guid });
    if (answer?.ok) flash(status, "Copied");
    else if (!answer?.cancelled) flash(status, "Couldn’t copy it");
  });
  const li = el("li", { className: "lib-login" },
    el("span", { className: "lib-main" },
      siteTile(item.origin, site),
      el("span", { className: "lib-text" },
        el("span", { className: "lib-title", textContent: site }),
        el("span", { className: "lib-sub", textContent: item.username || "No username" }),
        el("span", { className: "lib-pw" }, secret, show, copy, status))),
    removeButton("Remove password", async () => {
      if (!confirm(`Remove your saved password for ${site}?`)) return;
      await derp({ type: "logins.remove", guid: item.guid });
      li.remove();
      if (!list.children.length) render();
    }));
  return li;
}

function flash(node, text) {
  node.textContent = text;
  setTimeout(() => (node.textContent = ""), 2000);
}

async function render() {
  const query = search.value.trim();
  const answer = await derp({ type: "logins.list", query });
  const items = answer?.items || [];
  offer.checked = answer?.save !== false;
  list.replaceChildren(...items.map(row));
  empty.hidden = items.length > 0;
  empty.textContent = query
    ? `No saved passwords match “${query}”.`
    : "No saved passwords yet. When you sign in to a site, Derp offers to save your password. You can also import them from another browser.";
}

offer.addEventListener("change", () => derp({ type: "logins.offer", on: offer.checked }));
search.addEventListener("input", render);
render();
