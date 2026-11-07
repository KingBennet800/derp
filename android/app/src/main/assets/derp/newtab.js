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
