"use strict";
// The dork editor: the same parts and art as desktop Derp's editor.

const welcome = new URLSearchParams(location.search).has("welcome");
const TAB_NAMES = { face: "Face", eyes: "Eyes", mouth: "Mouth", hair: "Hair", extras: "Extras", backdrop: "Backdrop" };
const LABELS = {
  eyes: { googly: "Googly", round: "Round", happy: "Happy", sleepy: "Sleepy", wink: "Wink", hearts: "Hearts", startled: "Startled" },
  mouth: { derp: "Derp", grin: "Grin", smile: "Smile", buck: "Buck teeth", blep: "Blep", o: "Oh", smirk: "Smirk" },
  hair: { none: "No hair", sprout: "Sprout", bowl: "Bowl cut", swoop: "Swoop", spiky: "Spiky", curly: "Curly", mohawk: "Mohawk", bun: "Bun", long: "Long", beanie: "Beanie", cap: "Cap", party: "Party hat" },
  extras: { none: "Nothing", nerd: "Taped glasses", round: "Round glasses", shades: "Shades", freckles: "Freckles", blush: "Blush", bandage: "Bandage", headphones: "Headphones" },
};
const label = (part, value) => LABELS[part]?.[value] ?? (value === "none" ? "None" : value[0].toUpperCase() + value.slice(1));
const $ = id => document.getElementById(id);

let dork = randomDork();
let tab = "face";

document.getElementById("welcome").hidden = !welcome;
document.getElementById("plain").hidden = welcome;
$("done").textContent = welcome ? "That’s me!" : "Done";

$("tabs").append(
  ...TABS.map(t => {
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("role", "tab");
    b.dataset.tab = t.id;
    b.textContent = TAB_NAMES[t.id];
    return b;
  })
);

function render(pop = true) {
  const face = $("face");
  face.src = dorkURL(dork, 300);
  if (pop) {
    face.classList.remove("pop");
    void face.offsetWidth;
    face.classList.add("pop");
  }
  if (document.activeElement !== $("name")) $("name").value = dork.name;
  const current = TABS.find(t => t.id === tab);
  for (const b of $("tabs").children) b.setAttribute("aria-selected", b.dataset.tab === tab);

  const choice = (part, value, content, swatch) => {
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("role", "radio");
    b.setAttribute("aria-checked", dork[part] === value);
    b.setAttribute("aria-label", label(part, value));
    b.dataset.part = part;
    b.dataset.value = value;
    if (swatch) b.style.setProperty("--swatch", swatch);
    if (content) b.append(content);
    return b;
  };
  const grid = $("grid");
  grid.hidden = !current.options;
  if (current.options) {
    grid.replaceChildren(
      ...PARTS[current.options].map(value => {
        const img = new Image();
        img.alt = "";
        img.src = dorkURL({ ...dork, [current.options]: value }, 160);
        return choice(current.options, value, img);
      })
    );
  }
  const colors = $("colors");
  colors.hidden = !current.colors;
  if (current.colors) {
    colors.replaceChildren(...Object.entries(PARTS[current.colors]).map(([value, color]) => choice(current.colors, value, null, color)));
  }
}

function update(changes) {
  dork = normalizeDork({ ...dork, ...changes });
  saveDork(dork);
  render();
}

document.body.addEventListener("click", async e => {
  const b = e.target.closest("button");
  if (!b) return;
  if (b.dataset.tab) {
    tab = b.dataset.tab;
    render(false);
  } else if (b.dataset.part) {
    update({ [b.dataset.part]: b.dataset.value });
  } else if (b.id === "shuffle") {
    update(randomDork(dork.name));
  } else if (b.id === "save") {
    savePicture();
  } else if (b.id === "done") {
    await saveDork(dork);
    if (welcome) {
      await derp({ type: "made" });
      location.replace("newtab.html");
    } else if (history.length > 1) {
      history.back();
    } else {
      location.replace("newtab.html");
    }
  }
});

let typing;
$("name").addEventListener("input", e => {
  clearTimeout(typing);
  typing = setTimeout(() => {
    dork = normalizeDork({ ...dork, name: e.target.value });
    saveDork(dork);
  }, 250);
});
$("name").addEventListener("keydown", e => {
  if (e.key === "Enter") e.target.blur();
});

/** A 1024px PNG of your dork, into Downloads. */
async function savePicture() {
  const img = new Image();
  img.src = dorkURL(dork, 1024);
  await img.decode();
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1024;
  canvas.getContext("2d").drawImage(img, 0, 0, 1024, 1024);
  const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"));
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${(dork.name || "dork").replace(/[\\/:*?"<>|]/g, "") || "dork"}.png`;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 10000);
}

(async () => {
  dork = (await myDork()).dork;
  render(false);
})();
