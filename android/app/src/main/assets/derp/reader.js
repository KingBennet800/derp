"use strict";
// Reader view: the article from the page you were on, without the clutter.
// The app hands over the page's HTML; Readability finds the article in an
// inert copy, and only text, links, pictures and plain formatting are kept
// (never scripts, styles, frames or forms).
const KEEP = new Set([
  "P", "BR", "HR", "H1", "H2", "H3", "H4", "H5", "H6", "A", "IMG", "PICTURE", "FIGURE", "FIGCAPTION",
  "UL", "OL", "LI", "DL", "DT", "DD", "BLOCKQUOTE", "PRE", "CODE", "KBD", "EM", "STRONG", "B", "I", "U", "S",
  "SMALL", "SUB", "SUP", "MARK", "Q", "CITE", "ABBR", "TIME", "TABLE", "THEAD", "TBODY", "TFOOT", "TR",
  "TH", "TD", "CAPTION", "SPAN", "DIV", "SECTION", "ARTICLE", "ASIDE", "DETAILS", "SUMMARY",
]);
const DROP = new Set([
  "SCRIPT", "STYLE", "NOSCRIPT", "IFRAME", "FRAME", "OBJECT", "EMBED", "FORM", "INPUT", "BUTTON", "SELECT",
  "TEXTAREA", "SVG", "MATH", "TEMPLATE", "LINK", "META", "BASE", "VIDEO", "AUDIO", "SOURCE", "TRACK", "CANVAS",
]);

/** Only web addresses, made whole against the page's address. */
function web(url, base) {
  try {
    const whole = new URL(url, base);
    return /^https?:$/.test(whole.protocol) ? whole.href : null;
  } catch {
    return null;
  }
}

/** Copies what's worth keeping from [from] into [into]. */
function clean(from, into, base) {
  for (const node of from.childNodes) {
    if (node.nodeType === Node.TEXT_NODE) {
      into.append(node.data);
      continue;
    }
    if (node.nodeType !== Node.ELEMENT_NODE || DROP.has(node.tagName)) continue;
    if (!KEEP.has(node.tagName)) {
      clean(node, into, base);
      continue;
    }
    const copy = document.createElement(node.tagName);
    if (node.tagName === "A") {
      const href = web(node.getAttribute("href"), base);
      if (href) copy.href = href;
    } else if (node.tagName === "IMG") {
      const src = web(node.getAttribute("src"), base);
      if (!src) continue;
      Object.assign(copy, { src, alt: node.getAttribute("alt") || "", loading: "lazy", referrerPolicy: "no-referrer" });
    }
    for (const name of ["title", "colspan", "rowspan", "datetime", "start"]) {
      if (node.hasAttribute(name)) copy.setAttribute(name, node.getAttribute(name));
    }
    clean(node, copy, base);
    into.append(copy);
  }
}

(async () => {
  const page = await derp({ type: "reader.get" });
  let article = null;
  if (page?.html) {
    const doc = new DOMParser().parseFromString(page.html, "text/html");
    const base = doc.createElement("base");
    base.href = page.url;
    doc.head.prepend(base);
    try {
      article = new Readability(doc).parse();
    } catch (e) {
      console.warn("Reader view:", e);
    }
  }
  if (!article?.content) {
    document.getElementById("empty").hidden = false;
    return;
  }
  document.title = article.title || hostOf(page.url);
  if (article.lang) document.documentElement.lang = article.lang;
  if (article.dir) document.documentElement.dir = article.dir;
  const source = document.getElementById("source");
  source.textContent = article.siteName || hostOf(page.url);
  source.href = web(page.url) || "#";
  document.getElementById("title").textContent = article.title || "";
  const byline = document.getElementById("byline");
  byline.textContent = article.byline || "";
  byline.hidden = !article.byline;
  document.getElementById("head").hidden = false;
  const content = new DOMParser().parseFromString(article.content, "text/html");
  clean(content.body, document.getElementById("article"), page.url);
})();
