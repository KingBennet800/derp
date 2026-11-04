/* Your dork: Derp's own account. It's a cartoon you design (face, eyes,
 * mouth, hair or hat, extras, backdrop) plus a name. It's kept in this
 * profile's prefs (derp.dork) and never leaves the device: no sign-in, no
 * servers.
 *
 * It shows as the avatar button at the end of the tab strip, which opens the
 * editor, and on the "You and your dork" page in Settings. */

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  CustomizableUI: "moz-src:///browser/components/customizableui/CustomizableUI.sys.mjs",
  PanelMultiView: "moz-src:///browser/components/customizableui/PanelMultiView.sys.mjs",
});

const PREF = "derp.dork";
const WIDGET = "derp-dork-button";
const VIEW = "PanelUI-derp-dork";
const XHTML = "http://www.w3.org/1999/xhtml";
const NAME_MAX = 24;

// ── The parts ──────────────────────────────────────────────────────────────

export const PARTS = {
  skin: {
    lime: "#b8ef62",
    teal: "#36d6bf",
    sky: "#6aa2ff",
    grape: "#a985ff",
    bubblegum: "#ff93c4",
    tangerine: "#ffa552",
    lemon: "#ffd94f",
    mint: "#93efc9",
    porcelain: "#ffe3cc",
    sand: "#f4c9a1",
    honey: "#dea274",
    caramel: "#bf7f50",
    cocoa: "#8c5a3c",
    espresso: "#5c3b29",
  },
  eyes: ["googly", "round", "happy", "sleepy", "wink", "hearts", "startled"],
  mouth: ["derp", "grin", "smile", "buck", "blep", "o", "smirk"],
  hair: ["none", "sprout", "bowl", "swoop", "spiky", "curly", "mohawk", "bun", "long", "beanie", "cap", "party"],
  hairColor: {
    ink: "#2a2423",
    chestnut: "#5a3a26",
    toffee: "#9a6431",
    blond: "#efc75e",
    ginger: "#cf4f2c",
    silver: "#d9d9e1",
    pink: "#ff6fa0",
    blue: "#3b74f0",
    teal: "#22bfa8",
    purple: "#8f62f0",
  },
  extras: ["none", "nerd", "round", "shades", "freckles", "blush", "bandage", "headphones"],
  backdrop: {
    derp: "linear-gradient(135deg, #c6f57e, #2fd6be 45%, #2f6feb)",
    sky: "#dce8ff",
    lavender: "#ebe0ff",
    mint: "#d6f5ea",
    peach: "#ffe4cc",
    rose: "#ffe0ea",
    butter: "#fff2c2",
    fog: "#e5e5ea",
    night: "#262833",
    none: "transparent",
  },
};

// The editor's tabs: each picks options (drawn as your dork wearing them)
// and/or colors.
const TABS = [
  { id: "face", colors: "skin" },
  { id: "eyes", options: "eyes" },
  { id: "mouth", options: "mouth" },
  { id: "hair", options: "hair", colors: "hairColor" },
  { id: "extras", options: "extras" },
  { id: "backdrop", colors: "backdrop" },
];

const isColorPart = part => !Array.isArray(PARTS[part]);
const choices = part => (isColorPart(part) ? Object.keys(PARTS[part]) : PARTS[part]);
const pick = list => list[Math.floor(Math.random() * list.length)];

// ── Drawing ────────────────────────────────────────────────────────────────

const INK = "#1d2030";
// Line features (smiles, closed eyes) on the darkest faces, where ink vanishes.
const INK_ON_DARK = "#fde3d2";
const TONGUE = "#ff6f91";
const HEAD = { x: 256, y: 284, r: 172 };
const EYES = [
  { x: 198, y: 262 },
  { x: 316, y: 256 },
];
const MOUTH = { x: 257, y: 360 };
const CHEEKS = [
  { x: 146, y: 330 },
  { x: 368, y: 322 },
];

const round1 = n => Math.round(n * 10) / 10;
// A point on a circle around the head, at an angle in degrees (0 = right,
// -90 = top).
function headPoint(deg, r = HEAD.r) {
  const a = (deg * Math.PI) / 180;
  return [round1(HEAD.x + r * Math.cos(a)), round1(HEAD.y + r * Math.sin(a))];
}
const onHead = (deg, r) => headPoint(deg, r).join(" ");
// Half the width of a circle around the head at height y.
const halfWidth = (y, r) => round1(Math.sqrt(r * r - (HEAD.y - y) ** 2));
// The top of the head down to height y, as a closed shape (hair, hats).
function cap(y, r = HEAD.r + 6) {
  const dx = halfWidth(y, r);
  return `M${HEAD.x - dx} ${y} A${r} ${r} 0 0 1 ${HEAD.x + dx} ${y} Z`;
}
// A crown of spikes standing on the head between two angles.
function spikes(from, to, count, height) {
  const step = (to - from) / count;
  let d = `M${onHead(from)}`;
  for (let i = 0; i < count; i++) {
    d += ` L${onHead(from + step * (i + 0.5), HEAD.r + height)} L${onHead(from + step * (i + 1))}`;
  }
  return `${d} A${HEAD.r} ${HEAD.r} 0 0 0 ${onHead(from)} Z`;
}

function eye({ x, y }, r, pupil = null) {
  let s = `<circle cx="${x}" cy="${y}" r="${r}" fill="#fff"/>`;
  s += `<circle cx="${x}" cy="${y}" r="${r}" fill="none" stroke="${INK}" stroke-opacity=".12" stroke-width="5"/>`;
  if (pupil) {
    const [dx, dy, pr] = pupil;
    s += `<circle cx="${x + dx}" cy="${y + dy}" r="${pr}" fill="${INK}"/>`;
    s += `<circle cx="${round1(x + dx - pr * 0.35)}" cy="${round1(y + dy - pr * 0.38)}" r="${round1(pr * 0.3)}" fill="#fff"/>`;
  }
  return s;
}
const arcEye = ({ x, y }, ink) =>
  `<path d="M${x - 30} ${y + 8} Q${x} ${y - 32} ${x + 30} ${y + 8}" fill="none" stroke="${ink}" stroke-width="13" stroke-linecap="round"/>`;

// Is a face color dark enough that ink lines won't show on it?
function isDark(hex) {
  const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.4;
}

function drawEyes(kind, skin, ink) {
  const [L, R] = EYES;
  switch (kind) {
    case "googly":
      return eye(L, 48, [14, -12, 21]) + eye(R, 56, [-16, 18, 24]);
    case "happy":
      return arcEye(L, ink) + arcEye(R, ink);
    case "sleepy":
      return [L, R]
        .map(
          e =>
            eye(e, 42, [0, 17, 18]) +
            `<path d="M${e.x - 45} ${e.y + 2} A45 45 0 0 1 ${e.x + 45} ${e.y + 2} Z" fill="${skin}"/>` +
            `<path d="M${e.x - 42} ${e.y + 2} H${e.x + 42}" stroke="${ink}" stroke-width="9" stroke-linecap="round"/>`
        )
        .join("");
    case "wink":
      return eye(L, 44, [2, 4, 19]) + arcEye(R, ink);
    case "hearts":
      return [L, R]
        .map(
          ({ x, y }) =>
            `<path d="M${x} ${y + 30} C${x - 52} ${y - 2} ${x - 32} ${y - 50} ${x} ${y - 22} C${x + 32} ${y - 50} ${x + 52} ${y - 2} ${x} ${y + 30} Z" fill="#ff4f7b"/>` +
            `<circle cx="${x - 18}" cy="${y - 18}" r="7" fill="#fff" opacity=".7"/>`
        )
        .join("");
    case "startled":
      return eye(L, 56, [0, 0, 10]) + eye(R, 58, [0, 0, 10]);
    default: // round
      return eye(L, 42, [0, 4, 19]) + eye(R, 42, [0, 4, 19]);
  }
}

function drawMouth(kind, ink) {
  const x = MOUTH.x;
  const stroke = (d, w = 12) =>
    `<path d="${d}" fill="none" stroke="${ink}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
  // Open mouths stay dark inside; on dark faces they get a light rim.
  const rim = ink === INK ? "" : ` stroke="${ink}" stroke-width="5" stroke-linejoin="round"`;
  const open = (d, inside) =>
    `<clipPath id="mouth"><path d="${d}"/></clipPath><path d="${d}" fill="${INK}"/><g clip-path="url(#mouth)">${inside}</g><path d="${d}" fill="none"${rim}/>`;
  switch (kind) {
    case "derp":
      return open(
        `M${x - 58} 344 C${x - 36} 398 ${x + 44} 406 ${x + 62} 338 C${x + 26} 356 ${x - 22} 358 ${x - 58} 344 Z`,
        `<ellipse cx="${x + 10}" cy="390" rx="28" ry="19" fill="${TONGUE}"/>`
      );
    case "grin":
      return open(
        `M${x - 64} 338 Q${x} 430 ${x + 64} 338 Z`,
        `<rect x="${x - 70}" y="330" width="140" height="22" fill="#fff"/><ellipse cx="${x}" cy="398" rx="32" ry="18" fill="${TONGUE}"/>`
      );
    case "smile":
      return stroke(`M${x - 46} 346 Q${x} 388 ${x + 46} 346`, 13);
    case "buck":
      return (
        stroke(`M${x - 46} 344 Q${x} 382 ${x + 46} 344`) +
        `<rect x="${x - 18}" y="358" width="17" height="25" rx="4" fill="#fff" stroke="${INK}" stroke-width="5"/>` +
        `<rect x="${x + 1}" y="358" width="17" height="25" rx="4" fill="#fff" stroke="${INK}" stroke-width="5"/>`
      );
    case "blep":
      return (
        `<path d="M${x - 15} 358 v14 a15 15 0 0 0 30 0 v-14 Z" fill="${TONGUE}" stroke="${INK}" stroke-width="5" stroke-linejoin="round"/>` +
        stroke(`M${x - 34} 350 Q${x} 374 ${x + 34} 350`, 11)
      );
    case "o":
      return `<ellipse cx="${x}" cy="368" rx="20" ry="26" fill="${INK}"${rim}/>`;
    default: // smirk
      return stroke(`M${x - 40} 366 Q${x + 8} 384 ${x + 46} 346`) + stroke(`M${x + 44} 342 l10 -6`, 8);
  }
}

// Hair and hats: [drawn behind the head, drawn over it].
function drawHair(kind, c) {
  const fill = d => `<path d="${d}" fill="${c}"/>`;
  const shade = (d, o = 0.16) => `<path d="${d}" fill="#000" opacity="${o}"/>`;
  switch (kind) {
    case "sprout":
      return [
        "",
        `<path d="M256 116 Q246 86 262 60" fill="none" stroke="${c}" stroke-width="10" stroke-linecap="round"/>` +
          fill("M262 62 C284 38 322 40 332 58 C308 74 278 76 262 62 Z") +
          fill("M258 70 C238 46 208 48 200 62 C220 76 244 78 258 70 Z"),
      ];
    case "bowl":
      return ["", fill(cap(206))];
    case "swoop": {
      const r = HEAD.r + 6;
      const dx = halfWidth(206, r);
      return ["", fill(`M${HEAD.x - dx} 206 A${r} ${r} 0 0 1 ${HEAD.x + dx} 206 Q336 160 262 198 Q206 222 ${HEAD.x - dx} 206 Z`)];
    }
    case "spiky":
      return ["", fill(cap(204)) + fill(spikes(-168, -12, 7, 52))];
    case "curly": {
      let s = fill(cap(210));
      for (let a = -170; a <= -10; a += 20) {
        const [cx, cy] = headPoint(a, HEAD.r + 2);
        s += `<circle cx="${cx}" cy="${cy}" r="36" fill="${c}"/>`;
      }
      for (let x = 136; x <= 380; x += 48) {
        s += `<circle cx="${x}" cy="206" r="22" fill="${c}"/>`;
      }
      return ["", s];
    }
    case "mohawk":
      return ["", fill(spikes(-122, -58, 4, 64))];
    case "bun":
      return ["", `<circle cx="256" cy="100" r="44" fill="${c}"/>` + fill(cap(204)) + shade("M234 140 h44 v10 h-44 Z", 0.2)];
    case "long":
      return [
        fill(`M60 300 A196 196 0 0 1 452 300 L446 450 Q256 492 66 450 Z`),
        fill(cap(206)) + `<path d="M256 112 Q250 152 236 198" fill="none" stroke="#000" stroke-opacity=".18" stroke-width="6" stroke-linecap="round"/>`,
      ];
    case "beanie": {
      let ribs = "";
      for (let x = 96; x <= 416; x += 20) {
        ribs += `<path d="M${x} 196 v40" stroke="#000" stroke-opacity=".1" stroke-width="5"/>`;
      }
      return [
        "",
        fill(cap(214, 184)) +
          `<rect x="${HEAD.x - 180}" y="192" width="360" height="46" rx="23" fill="${c}"/>` +
          `<rect x="${HEAD.x - 180}" y="192" width="360" height="46" rx="23" fill="#000" opacity=".14"/>` +
          ribs +
          `<circle cx="256" cy="96" r="30" fill="${c}"/><circle cx="256" cy="96" r="30" fill="#fff" opacity=".3"/>`,
      ];
    }
    case "cap":
      return [
        "",
        fill(cap(222, 182)) +
          `<path d="M256 104 V222" stroke="#000" stroke-opacity=".12" stroke-width="5"/>` +
          fill("M150 222 Q330 198 474 236 Q336 264 150 238 Z") +
          shade("M150 222 Q330 198 474 236 Q336 264 150 238 Z", 0.2) +
          `<circle cx="256" cy="104" r="11" fill="${c}"/>`,
      ];
    case "party":
      return [
        "",
        fill("M198 150 L256 24 L314 150 Q256 170 198 150 Z") +
          `<circle cx="246" cy="124" r="8" fill="#fff" opacity=".75"/><circle cx="272" cy="96" r="7" fill="#fff" opacity=".75"/><circle cx="262" cy="140" r="6" fill="#fff" opacity=".75"/>` +
          `<circle cx="256" cy="24" r="17" fill="#ffd84d"/><circle cx="250" cy="18" r="5" fill="#fff" opacity=".6"/>`,
      ];
    default: // none
      return ["", ""];
  }
}

// Extras: [drawn on the face, drawn over the hair].
function drawExtras(kind) {
  const [L, R] = EYES;
  switch (kind) {
    case "nerd":
      return [
        [L, R]
          .map(
            e =>
              `<rect x="${e.x - 56}" y="${e.y - 48}" width="112" height="96" rx="28" fill="#fff" fill-opacity=".14" stroke="${INK}" stroke-width="13"/>`
          )
          .join("") +
          `<path d="M${L.x + 56} ${L.y - 8} L${R.x - 56} ${R.y - 8}" stroke="${INK}" stroke-width="12"/>` +
          `<rect x="245" y="236" width="24" height="30" rx="5" fill="#fff" stroke="${INK}" stroke-width="4" transform="rotate(-8 257 251)"/>` +
          `<path d="M${L.x - 56} ${L.y - 14} L${HEAD.x - HEAD.r + 8} ${L.y - 24} M${R.x + 56} ${R.y - 14} L${HEAD.x + HEAD.r - 8} ${R.y - 24}" stroke="${INK}" stroke-width="10" stroke-linecap="round"/>`,
        "",
      ];
    case "round":
      return [
        [L, R]
          .map(
            e => `<circle cx="${e.x}" cy="${e.y}" r="56" fill="#fff" fill-opacity=".1" stroke="${INK}" stroke-width="7"/>`
          )
          .join("") + `<path d="M${L.x + 56} ${L.y - 4} Q257 ${L.y - 22} ${R.x - 56} ${R.y - 4}" fill="none" stroke="${INK}" stroke-width="7"/>`,
        "",
      ];
    case "shades":
      return [
        [L, R]
          .map(
            e =>
              `<rect x="${e.x - 56}" y="${e.y - 36}" width="112" height="80" rx="30" fill="#15161c"/>` +
              `<path d="M${e.x - 32} ${e.y - 14} l26 -12" stroke="#fff" stroke-opacity=".45" stroke-width="8" stroke-linecap="round"/>`
          )
          .join("") + `<path d="M${L.x + 56} ${L.y - 10} L${R.x - 56} ${R.y - 10}" stroke="#15161c" stroke-width="10"/>`,
        "",
      ];
    case "freckles":
      return [
        CHEEKS.map(({ x, y }) =>
          [
            [-16, -6],
            [2, 5],
            [18, -5],
            [-2, -16],
          ]
            .map(([dx, dy]) => `<circle cx="${x + dx}" cy="${y + dy}" r="6.5" fill="#9a4f2a" opacity=".62"/>`)
            .join("")
        ).join(""),
        "",
      ];
    case "blush":
      return [
        CHEEKS.map(
          ({ x, y }) =>
            `<ellipse cx="${x}" cy="${y}" rx="36" ry="20" fill="${TONGUE}" opacity=".7"/>` +
            `<path d="M${x - 16} ${y + 4} l10 -13 M${x + 2} ${y + 4} l10 -13" stroke="#fff" stroke-opacity=".75" stroke-width="5" stroke-linecap="round"/>`
        ).join(""),
        "",
      ];
    case "bandage":
      return [
        `<g transform="rotate(-24 368 318)"><rect x="332" y="304" width="72" height="28" rx="14" fill="#f2c48f" stroke="${INK}" stroke-opacity=".45" stroke-width="4"/>` +
          `<rect x="358" y="307" width="20" height="22" rx="4" fill="#dea06a"/></g>`,
        "",
      ];
    case "headphones":
      return [
        "",
        `<path d="M74 300 A182 182 0 0 1 438 300" fill="none" stroke="#2a2d3a" stroke-width="22" stroke-linecap="round"/>` +
          `<rect x="50" y="244" width="52" height="100" rx="24" fill="#2a2d3a"/><rect x="410" y="244" width="52" height="100" rx="24" fill="#2a2d3a"/>` +
          `<rect x="62" y="262" width="28" height="64" rx="14" fill="#2f6feb"/><rect x="422" y="262" width="28" height="64" rx="14" fill="#2f6feb"/>`,
      ];
    default: // none
      return ["", ""];
  }
}

function backdrop(kind) {
  if (kind === "none") {
    return "";
  }
  if (kind === "derp") {
    return (
      `<linearGradient id="derp" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#c6f57e"/>` +
      `<stop offset=".45" stop-color="#2fd6be"/><stop offset="1" stop-color="#2f6feb"/></linearGradient>` +
      `<circle cx="256" cy="256" r="256" fill="url(#derp)"/>`
    );
  }
  return `<circle cx="256" cy="256" r="256" fill="${PARTS.backdrop[kind]}"/>`;
}

function draw(dork, size) {
  const skin = PARTS.skin[dork.skin];
  const ink = isDark(skin) ? INK_ON_DARK : INK;
  const [hairBack, hairFront] = drawHair(dork.hair, PARTS.hairColor[dork.hairColor]);
  const [onFace, overHair] = drawExtras(dork.extras);
  const { x, y, r } = HEAD;
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 512 512">` +
    backdrop(dork.backdrop) +
    hairBack +
    `<circle cx="${x}" cy="${y}" r="${r}" fill="${skin}"/>` +
    `<path d="M${x - r} ${y} A${r} ${r} 0 0 0 ${x + r} ${y} A${r} ${r - 22} 0 0 1 ${x - r} ${y} Z" fill="#000" opacity=".06"/>` +
    `<ellipse cx="190" cy="180" rx="62" ry="34" transform="rotate(-28 190 180)" fill="#fff" opacity=".28"/>` +
    `<circle cx="${x}" cy="${y}" r="${r - 3}" fill="none" stroke="${INK}" stroke-opacity=".08" stroke-width="6"/>` +
    CHEEKS.map(c => `<ellipse cx="${c.x}" cy="${c.y}" rx="24" ry="13" fill="${TONGUE}" opacity=".22"/>`).join("") +
    drawEyes(dork.eyes, skin, ink) +
    drawMouth(dork.mouth, ink) +
    onFace +
    hairFront +
    overHair +
    `</svg>`
  );
}

// ── The dork ───────────────────────────────────────────────────────────────

export const DerpDork = {
  PARTS,
  PREF,

  /** A random dork: everyone starts with their own. */
  random(name = "") {
    return {
      name,
      skin: pick(choices("skin")),
      eyes: pick(["googly", "googly", "round", "happy", "wink", "startled"]),
      mouth: pick(PARTS.mouth),
      hair: pick(PARTS.hair),
      hairColor: pick(choices("hairColor")),
      extras: Math.random() < 0.5 ? "none" : pick(PARTS.extras.slice(1)),
      backdrop: pick(choices("backdrop").filter(b => b !== "none")),
    };
  },

  /** This profile's dork, with anything unknown replaced. */
  get() {
    let saved = {};
    try {
      saved = JSON.parse(Services.prefs.getStringPref(PREF, "{}")) || {};
    } catch {}
    const dork = { name: typeof saved.name === "string" ? saved.name.slice(0, NAME_MAX) : "" };
    for (const part of Object.keys(PARTS)) {
      dork[part] = choices(part).includes(saved[part]) ? saved[part] : choices(part)[0];
    }
    return dork;
  },

  set(changes) {
    const dork = { ...this.get(), ...changes };
    dork.name = String(dork.name ?? "").trim().slice(0, NAME_MAX);
    Services.prefs.setStringPref(PREF, JSON.stringify(dork));
  },

  svg(dork = this.get(), size = 512) {
    return draw(dork, size);
  },

  dataURL(dork = this.get(), size = 512) {
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(draw(dork, size))}`;
  },

  // ── In browser windows ───────────────────────────────────────────────────

  init({ cssURL }) {
    this.cssURL = cssURL;
    if (!Services.prefs.prefHasUserValue(PREF)) {
      this.set(this.random());
    }
    lazy.CustomizableUI.createWidget({
      id: WIDGET,
      type: "view",
      viewId: VIEW,
      defaultArea: lazy.CustomizableUI.AREA_TABSTRIP,
      l10nId: "derp-dork-button",
      onBeforeCreated: doc => {
        this.prepare(doc);
        return true;
      },
      onCreated: node => this.paintButton(node),
      onViewShowing: event => this.render(event.target, { pop: false }),
    });
    Services.prefs.addObserver(PREF, () => this.refresh());
  },

  /** Strings, styles and the editor for a browser window (once). The editor
   * waits in the window's panel view cache until it's opened. */
  prepare(doc) {
    let view = lazy.PanelMultiView.getViewNode(doc, VIEW);
    if (view) {
      return view;
    }
    const win = doc.defaultView;
    win.MozXULElement.insertFTLIfNeeded("derp/dork.ftl");
    win.windowUtils.loadSheetUsingURIString(this.cssURL, win.windowUtils.AUTHOR_SHEET);
    view = this.buildEditor(doc);
    doc.getElementById("appMenu-viewCache").content.append(view);
    return view;
  },

  paintButton(node, dork = this.get()) {
    node.setAttribute("image", this.dataURL(dork, 48));
    if (dork.name) {
      node.ownerDocument.l10n.setAttributes(node, "derp-dork-button-named", { name: dork.name });
    } else {
      node.ownerDocument.l10n.setAttributes(node, "derp-dork-button");
    }
  },

  refresh() {
    const dork = this.get();
    for (const win of Services.wm.getEnumerator("navigator:browser")) {
      const node = lazy.CustomizableUI.getWidget(WIDGET)?.forWindow(win)?.node;
      if (node) {
        this.paintButton(node, dork);
      }
      const view = lazy.PanelMultiView.getViewNode(win.document, VIEW);
      if (view?.closest("panel")?.state === "open") {
        this.render(view);
      }
    }
  },

  /** Open the editor in a browser window, from its avatar button if it has one. */
  openEditor(win) {
    this.prepare(win.document);
    const node = lazy.CustomizableUI.getWidget(WIDGET)?.forWindow(win)?.node;
    const anchor = node?.checkVisibility() ? node : win.document.getElementById("PanelUI-menu-button");
    win.PanelUI.showSubView(VIEW, anchor);
  },

  /** Your dork as a 1024px PNG, drawn in a browser window. */
  async picture(win, dork = this.get()) {
    const img = new win.Image();
    img.src = this.dataURL(dork, 1024);
    await img.decode();
    const canvas = win.document.createElementNS(XHTML, "canvas");
    canvas.width = canvas.height = 1024;
    canvas.getContext("2d").drawImage(img, 0, 0, 1024, 1024);
    const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"));
    return new Uint8Array(await blob.arrayBuffer());
  },

  async savePicture(win) {
    const dork = this.get();
    const [title, filterName] = await win.document.l10n.formatValues(["derp-dork-save-title", "derp-dork-save-filter"]);
    const picker = Cc["@mozilla.org/filepicker;1"].createInstance(Ci.nsIFilePicker);
    picker.init(win.browsingContext, title, Ci.nsIFilePicker.modeSave);
    picker.appendFilter(filterName, "*.png");
    picker.defaultString = `${(dork.name || "dork").replace(/[\\/:*?"<>|]/g, "")}.png`;
    picker.defaultExtension = "png";
    const result = await new Promise(resolve => picker.open(resolve));
    if (result !== Ci.nsIFilePicker.returnCancel) {
      await IOUtils.write(picker.file.path, await this.picture(win, dork));
    }
  },

  // ── The editor ───────────────────────────────────────────────────────────

  buildEditor(doc) {
    const h = (tag, attrs = {}, ...children) => {
      const el = doc.createElementNS(XHTML, tag);
      for (const [k, v] of Object.entries(attrs)) {
        el.setAttribute(k, v);
      }
      el.append(...children);
      return el;
    };
    const view = doc.createXULElement("panelview");
    view.id = VIEW;
    view.className = "PanelUI-subView";
    view.dataset.tab = "face";

    const name = h("input", { class: "derp-dork-name", type: "text", maxlength: NAME_MAX, "data-l10n-id": "derp-dork-name" });
    const tabs = h(
      "div",
      { class: "derp-dork-tabs", role: "tablist" },
      ...TABS.map(t => h("button", { role: "tab", "data-tab": t.id, "data-l10n-id": `derp-dork-tab-${t.id}` }))
    );
    const editor = h(
      "div",
      { class: "derp-dork" },
      h(
        "div",
        { class: "derp-dork-hero" },
        h("img", { class: "derp-dork-face", alt: "" }),
        name,
        h("p", { class: "derp-dork-note", "data-l10n-id": "derp-dork-local" })
      ),
      tabs,
      h("div", { class: "derp-dork-grid", role: "radiogroup" }),
      h("div", { class: "derp-dork-colors", role: "radiogroup" }),
      h(
        "div",
        { class: "derp-dork-actions" },
        h("button", { "data-action": "shuffle", "data-l10n-id": "derp-dork-shuffle" }),
        h("button", { "data-action": "save", "data-l10n-id": "derp-dork-save" }),
        h("button", { "data-action": "done", class: "primary", "data-l10n-id": "derp-dork-done" })
      )
    );
    const body = doc.createXULElement("vbox");
    body.className = "panel-subview-body";
    body.append(editor);
    view.append(body);

    let typing = null;
    name.addEventListener("input", () => {
      doc.defaultView.clearTimeout(typing);
      typing = doc.defaultView.setTimeout(() => this.set({ name: name.value }), 250);
    });
    name.addEventListener("keydown", e => {
      if (e.key === "Enter") {
        name.blur();
      }
    });
    name.addEventListener("change", () => this.set({ name: name.value }));
    editor.addEventListener("click", e => {
      const button = e.target.closest("button");
      if (!button) {
        return;
      }
      if (button.dataset.tab) {
        view.dataset.tab = button.dataset.tab;
        this.render(view, { pop: false });
      } else if (button.dataset.part) {
        this.set({ [button.dataset.part]: button.dataset.value });
      } else if (button.dataset.action === "shuffle") {
        this.set(this.random(this.get().name));
      } else if (button.dataset.action === "save") {
        this.savePicture(doc.defaultView).catch(console.error);
      } else if (button.dataset.action === "done") {
        view.closest("panel")?.hidePopup();
      }
    });
    return view;
  },

  render(view, { pop = true } = {}) {
    const doc = view.ownerDocument;
    const dork = this.get();
    const tab = TABS.find(t => t.id === view.dataset.tab) ?? TABS[0];

    const face = view.querySelector(".derp-dork-face");
    face.src = this.dataURL(dork, 256);
    if (pop) {
      face.classList.remove("derp-dork-pop");
      face.getBoundingClientRect(); // restart the animation
      face.classList.add("derp-dork-pop");
    }
    const name = view.querySelector(".derp-dork-name");
    if (doc.activeElement !== name) {
      name.value = dork.name;
    }
    for (const button of view.querySelectorAll(".derp-dork-tabs > button")) {
      button.setAttribute("aria-selected", button.dataset.tab === tab.id);
    }

    const focused = doc.activeElement?.dataset?.value;
    const choice = (part, value, content, attrs = {}) => {
      const button = doc.createElementNS(XHTML, "button");
      button.setAttribute("role", "radio");
      button.setAttribute("aria-checked", dork[part] === value);
      button.dataset.part = part;
      button.dataset.value = value;
      doc.l10n.setAttributes(button, `derp-dork-${part}-${value}`);
      for (const [k, v] of Object.entries(attrs)) {
        button.style.setProperty(k, v);
      }
      if (content) {
        button.append(content);
      }
      return button;
    };
    const grid = view.querySelector(".derp-dork-grid");
    grid.hidden = !tab.options;
    if (tab.options) {
      grid.replaceChildren(
        ...PARTS[tab.options].map(value => {
          const img = doc.createElementNS(XHTML, "img");
          img.alt = "";
          img.src = this.dataURL({ ...dork, [tab.options]: value }, 128);
          return choice(tab.options, value, img);
        })
      );
    }
    const colors = view.querySelector(".derp-dork-colors");
    colors.hidden = !tab.colors;
    if (tab.colors) {
      colors.replaceChildren(
        ...Object.entries(PARTS[tab.colors]).map(([value, color]) => choice(tab.colors, value, null, { "--swatch": color }))
      );
    }
    if (focused) {
      view.querySelector(`button[data-value="${focused}"][data-part]`)?.focus();
    }
  },
};
