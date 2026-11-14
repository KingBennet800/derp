"use strict";
// Tells Google whether Derp is light or dark, the way Chrome does (its
// Sec-CH-Prefers-Color-Scheme hint, which Google doesn't get from Firefox's
// engine otherwise), so Google's pages, Doodle's results among them, come in
// Derp's theme.
const dark = matchMedia("(prefers-color-scheme: dark)");
browser.webRequest.onBeforeSendHeaders.addListener(
  ({ requestHeaders }) => {
    const headers = requestHeaders.filter(h => h.name.toLowerCase() !== "sec-ch-prefers-color-scheme");
    headers.push({ name: "Sec-CH-Prefers-Color-Scheme", value: dark.matches ? "dark" : "light" });
    return { requestHeaders: headers };
  },
  { urls: ["https://www.google.com/*"], types: ["main_frame"] },
  ["blocking", "requestHeaders"]
);
