"use strict";
// Import data: the app opens Android's file picker and reads the file.
for (const button of document.querySelectorAll("[data-kind]")) {
  button.addEventListener("click", async () => {
    const kind = button.dataset.kind;
    const out = document.getElementById(`${kind}-result`);
    button.disabled = true;
    out.textContent = "";
    const answer = await derp({ type: "import", kind });
    button.disabled = false;
    if (!answer || answer.cancelled) return;
    if (!answer.ok) {
      out.textContent = `That file couldn’t be read${answer.error ? ` (${answer.error})` : ""}.`;
    } else if (!answer.found) {
      out.textContent = kind === "bookmarks"
        ? "No bookmarks in that file. Choose the .html file your other browser exported."
        : "No passwords in that file. Choose the .csv file your other browser exported.";
    } else if (kind === "bookmarks") {
      const had = answer.found - answer.added;
      out.textContent = answer.added
        ? `Added ${plural(answer.added, "bookmark")}${had ? `; you already had ${had}` : ""}.`
        : "You already have all of those bookmarks.";
    } else {
      const parts = [];
      if (answer.added) parts.push(`added ${plural(answer.added, "password")}`);
      if (answer.updated) parts.push(`updated ${answer.updated}`);
      out.textContent = parts.length ? `Done: ${parts.join(", ")}.` : "You already have all of those passwords.";
    }
  });
}
