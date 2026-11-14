"use strict";
// Doodle's look for Google's results, on Doodle searches only: ones whose
// address says doodle=1, and the Google pages you go on to from there in the
// same tab (Images, News, the next page). Doodle's header, its logo and a
// search box, takes the place of Google's logo and search box, crediting
// Google; results sit on cards in Derp's colors (doodle-page.css), and the
// page is dark while Derp is. Google's AI (its AI Overview and AI Mode) and
// Sign in go; its ads and its legal links stay.
// It's a content script: in desktop Derp's built-in Doodle's look extension
// (this folder), and in Derp for Android's.
(() => {
  const params = new URLSearchParams(location.search);
  let doodle = false;
  try {
    if (params.get("doodle") === "1") {
      sessionStorage.setItem("doodle", "1");
    }
    doodle = sessionStorage.getItem("doodle") === "1";
  } catch {
    doodle = params.get("doodle") === "1";
  }
  if (!doodle || location.pathname !== "/search" || document.getElementById("doodle-bar")) {
    return;
  }
  const root = document.documentElement;

  // Light or dark, as Derp is. Google gives Derp its light page, so while
  // Derp is dark the stylesheet turns it dark, pictures excepted. (If you
  // set Google itself to dark, its page is dark already, and Doodle's header
  // is dark to match.)
  const darkMode = matchMedia("(prefers-color-scheme: dark)");
  const lightPage = () => {
    const [r, g, b, a = 1] = (getComputedStyle(document.body).backgroundColor.match(/[\d.]+/g) || [255, 255, 255]).map(Number);
    return a === 0 || 0.2126 * r + 0.7152 * g + 0.0722 * b > 128;
  };
  const paint = () => {
    root.removeAttribute("data-doodle-invert");
    const light = !document.body || lightPage();
    root.dataset.doodle = darkMode.matches || !light ? "dark" : "light";
    root.toggleAttribute("data-doodle-invert", darkMode.matches && light);
  };
  paint();
  darkMode.addEventListener("change", paint);

  // Doodle's logo (brand/doodle.svg), with its own ids.
  const LOGO = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="6 6 268 84" role="img" aria-label="Doodle">
  <defs><linearGradient id="doodle-ink" x1="10" y1="0" x2="270" y2="0" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#7CC242"/><stop offset=".45" stop-color="#1FB5A0"/><stop offset="1" stop-color="#2F6FEB"/>
  </linearGradient></defs>
  <g fill="none" stroke="url(#doodle-ink)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="30" cy="61" r="17"/><path d="M47 14V80"/><circle cx="170" cy="61" r="17"/>
    <path d="M187 14V80M208 14V71q0 9 8 9"/><path d="M229 61H262A17 17 0 1 0 256 74"/>
  </g>
  <g class="eyes" stroke="#18181B" stroke-width="5"><circle cx="78" cy="61" r="19" fill="#fff"/><circle cx="124" cy="61" r="19" fill="#fff"/></g>
  <g fill="#18181B"><circle class="pupil" cx="82" cy="66" r="8"/><circle class="pupil" cx="128" cy="66" r="8"/></g>
</svg>`;
  const HOME = "https://kingbennet800.github.io/derp/doodle/";

  const make = (tag, props = {}, ...children) => {
    const node = Object.assign(document.createElement(tag), props);
    node.append(...children);
    return node;
  };

  function build() {
    if (document.getElementById("doodle-bar")) {
      return true;
    }
    // Google's search box (its logo is in there too, or beside it).
    const theirs = document.getElementById("tsf") || document.querySelector("form[role=search], form[action='/search']");
    if (!theirs) {
      return false;
    }
    paint();
    const drawing = () => new DOMParser().parseFromString(LOGO, "image/svg+xml").documentElement;
    const logo = make("a", { className: "doodle-logo", href: HOME, title: "Doodle" });
    logo.append(drawing());

    // A search here stays a Doodle search.
    const input = make("input", {
      type: "search",
      name: "q",
      value: params.get("q") || theirs.querySelector("[name=q]")?.value || "",
      placeholder: "Search with Doodle",
      autocomplete: "off",
      spellcheck: false,
    });
    input.setAttribute("aria-label", "Search with Doodle");
    const form = make(
      "form",
      { className: "doodle-search", action: "/search", method: "get", role: "search" },
      input,
      make("input", { type: "hidden", name: "doodle", value: "1" }),
      make("button", { type: "submit", textContent: "Search" })
    );

    // Credit where it's due: Google's "G" and name, linking to them.
    const google = make(
      "a",
      { className: "doodle-source", href: "https://www.google.com/" },
      make("img", { src: "https://www.google.com/favicon.ico", alt: "", width: 18, height: 18 }),
      "Google"
    );
    const credit = make("span", { className: "doodle-credit" }, "Results from", google);

    const bar = make("div", { id: "doodle-bar" }, logo, form, credit);
    theirs.before(bar);
    theirs.dataset.doodleGone = "";

    // Google's logo, where it's apart from its search box: on phones it has a
    // row of its own, and Doodle's takes its place there; a small one (its
    // "G", in a side bar) just goes.
    const home = [...document.querySelectorAll("a[href]")].find(a => {
      const url = new URL(a.href, location.href);
      return (
        url.host === location.host &&
        /^\/(webhp)?$/.test(url.pathname) &&
        a.querySelector("svg, img") &&
        !theirs.contains(a) &&
        !bar.contains(a)
      );
    });
    if (home?.getBoundingClientRect().width >= 80) {
      home.replaceChildren(drawing());
      home.href = HOME;
      home.setAttribute("aria-label", "Doodle");
      home.classList.add("doodle-logo", "doodle-home");
      bar.classList.add("doodle-logo-up");
    } else if (home) {
      home.dataset.doodleHidden = "";
    }
    return true;
  }

  // Google draws its page as it loads; wait for its search box if need be.
  if (!build()) {
    const watch = new MutationObserver(() => build() && watch.disconnect());
    watch.observe(root, { childList: true, subtree: true });
    setTimeout(() => watch.disconnect(), 15000);
  }
  addEventListener("DOMContentLoaded", paint);
})();
