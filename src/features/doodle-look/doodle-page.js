"use strict";
// Doodle's look for DuckDuckGo's results, on Doodle searches only (the ones
// whose address carries Doodle's colors). Doodle's header, its logo and a
// search box, takes the place of DuckDuckGo's, crediting DuckDuckGo with
// their own logo; results sit on cards in Derp's colors (doodle-page.css).
// DuckDuckGo's ads stay as they are. It's a content script: in desktop Derp's
// built-in Doodle's look extension (this folder), and in Derp for Android's.
(() => {
  const DOODLE = /[?&]k9=(2f6feb|86b1ff)(&|$)/;
  if (!DOODLE.test(location.search) || document.getElementById("doodle-bar")) {
    return;
  }
  const params = new URLSearchParams(location.search);
  document.documentElement.dataset.doodle = params.get("kae") === "d" ? "dark" : "light";

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
    const header = document.querySelector("[data-testid=header], #header_wrapper");
    if (!header || document.getElementById("doodle-bar")) {
      return !!header;
    }
    const logo = make("a", { className: "doodle-logo", href: HOME, title: "Doodle" });
    logo.append(document.importNode(new DOMParser().parseFromString(LOGO, "image/svg+xml").documentElement, true));

    // A search here stays a Doodle search: it keeps Doodle's settings.
    const input = make("input", {
      type: "search",
      name: "q",
      value: params.get("q") || "",
      placeholder: "Search with Doodle",
      autocomplete: "off",
    });
    input.setAttribute("aria-label", "Search with Doodle");
    const form = make("form", { className: "doodle-search", action: "/", method: "get", role: "search" }, input);
    for (const [name, value] of params) {
      if (/^k/.test(name)) {
        form.append(make("input", { type: "hidden", name, value }));
      }
    }
    form.append(make("button", { type: "submit", textContent: "Search" }));

    // Credit where it's due: DuckDuckGo's own logo link, moved into Doodle's header.
    const credit = make("span", { className: "doodle-credit" }, "Results from");
    const theirs = document.querySelector("[data-testid=header-logo]") || make("a", { href: "https://duckduckgo.com/" });
    // (Their link already says "DuckDuckGo" to screen readers.)
    const name = make("span", { className: "doodle-ddg", textContent: "DuckDuckGo" });
    name.setAttribute("aria-hidden", "true");
    theirs.append(name);
    theirs.removeAttribute("tabindex");
    credit.append(theirs);

    header.prepend(make("div", { id: "doodle-bar" }, logo, form, credit));
    return true;
  }

  // DuckDuckGo draws its header as the page loads; wait for it if need be.
  if (!build()) {
    const watch = new MutationObserver(() => build() && watch.disconnect());
    watch.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(() => watch.disconnect(), 10000);
  }
})();
