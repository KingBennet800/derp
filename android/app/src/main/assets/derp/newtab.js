"use strict";
(async () => {
  const { dork } = await myDork();
  document.getElementById("me").src = dorkURL(dork, 128);
  if (dork.name) document.getElementById("hi").textContent = `Hi, ${dork.name}`;
})();
// The search box is a shortcut to the address bar.
document.getElementById("search").addEventListener("click", () => derp({ type: "focusUrl" }));
