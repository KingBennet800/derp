"use strict";
// Runs in every web page you open (Derp's built-in extension), apart from the
// page's own scripts: it tells Derp whether the page reads well as an article
// (Reader view) and which icon the site has (Add to home screen), and hands
// Derp the page when you open Reader view.
(() => {
  if (window !== window.top || !/^https?:$/.test(location.protocol)) return;

  /** Like Firefox's check: enough paragraphs of real text, outside of menus,
   * comments and sidebars. */
  function readable() {
    const unlikely = /-ad-|ai2html|banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote/i;
    const likely = /and|article|body|column|content|main|shadow/i;
    let score = 0;
    for (const node of document.querySelectorAll("p, pre, article")) {
      const style = getComputedStyle(node);
      if (style.display === "none" || style.visibility === "hidden" || node.hidden) continue;
      const names = `${node.className} ${node.id}`;
      if (unlikely.test(names) && !likely.test(names)) continue;
      if (node.matches("li p")) continue;
      const length = node.textContent.trim().length;
      if (length < 140) continue;
      score += Math.sqrt(length - 140);
      if (score > 20) return true;
    }
    return false;
  }

  /** The site's biggest icon: its home-screen icon if it has one. */
  function icon() {
    let best = null;
    let bestSize = -1;
    for (const link of document.querySelectorAll('link[rel~="icon" i], link[rel="apple-touch-icon" i], link[rel="apple-touch-icon-precomposed" i]')) {
      if (!link.href || !/^https?:/.test(link.href)) continue;
      const sizes = (link.getAttribute("sizes") || "").split(/\s+/).map(size => parseInt(size, 10) || 0);
      const touch = /apple-touch-icon/i.test(link.rel);
      const size = Math.max(touch ? 180 : 16, ...sizes, /\.svg(\?|$)/i.test(link.href) ? 512 : 0);
      if (size > bestSize) {
        best = link.href;
        bestSize = size;
      }
    }
    return best || new URL("/favicon.ico", location.href).href;
  }

  const port = browser.runtime.connectNative("derp");
  port.onMessage.addListener(message => {
    if (message?.type === "reader") {
      port.postMessage({ type: "reader.page", url: location.href, html: document.documentElement.outerHTML });
    }
  });
  port.postMessage({ type: "page", url: location.href, readable: readable(), icon: icon() });
})();
