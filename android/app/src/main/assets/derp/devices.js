"use strict";
// Your devices: the Derps this phone is paired with, and their open tabs.
// Pairing starts on your computer (its QR code); the app does the syncing.
const lede = document.getElementById("lede");
const devices = document.getElementById("devices");
const problem = document.getElementById("problem");
const sync = document.getElementById("sync");

function ago(at) {
  const minutes = Math.round((Date.now() - at) / 60000);
  if (!at) return "not yet";
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 48) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  return `${Math.round(hours / 24)} days ago`;
}

function show(state) {
  const paired = !!state?.paired;
  document.getElementById("unpaired").hidden = paired;
  document.getElementById("actions").hidden = !paired;
  lede.textContent = paired
    ? `Bookmarks, passwords and open tabs, shared with your other Derps. Synced ${ago(state.syncedAt)}.`
    : "Pair Derp on your computer with this phone, and your bookmarks, passwords and open tabs follow you between them.";
  problem.hidden = !state?.problem;
  problem.textContent = state?.problem ? `Couldn’t sync just now (${state.problem}). Derp tries again in a few minutes.` : "";
  const list = paired ? state.devices || [] : [];
  devices.replaceChildren(
    ...(paired && !list.length ? [el("p", { className: "lib-empty", textContent: "Your computer shows up here once it syncs." })] : []),
    ...list.map(device =>
      el(
        "section",
        { className: "dev-card" },
        el("h2", { textContent: device.name }),
        el("p", { className: "lib-sub", textContent: `Synced ${ago(device.at)}` }),
        device.tabs?.length
          ? el(
              "ul",
              { className: "lib-list" },
              ...device.tabs.map(tab =>
                el(
                  "li",
                  {},
                  el(
                    "a",
                    { className: "lib-main", href: webURL(tab.url) },
                    siteTile(tab.url, tab.title),
                    el("span", { className: "lib-text" },
                      el("span", { className: "lib-title", textContent: tab.title || hostOf(tab.url) }),
                      el("span", { className: "lib-sub", textContent: hostOf(tab.url) }))
                  )
                )
              )
            )
          : el("p", { className: "lib-sub", textContent: "No open tabs." })
      )
    )
  );
}

sync.addEventListener("click", async () => {
  sync.disabled = true;
  sync.textContent = "Syncing…";
  const answer = await derp({ type: "devices.sync" });
  sync.disabled = false;
  sync.textContent = "Sync now";
  if (answer?.devices) show(answer.devices);
});

document.getElementById("leave").addEventListener("click", async () => {
  if (!confirm("Stop syncing? This phone leaves the pair. Its bookmarks and passwords stay here, and your other devices keep theirs.")) return;
  const answer = await derp({ type: "devices.leave" });
  show(answer?.devices || { paired: false });
});

(async () => show((await derp({ type: "devices.get" }))?.devices))();
