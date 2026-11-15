"use strict";
// The dork editor: the same parts and art as desktop Derp's editor.

const welcome = new URLSearchParams(location.search).has("welcome");
const TAB_NAMES = { face: "Face", eyes: "Eyes", mouth: "Mouth", hair: "Hair", extras: "Extras", backdrop: "Backdrop" };
const LABELS = {
  eyes: { googly: "Googly", round: "Round", happy: "Happy", sleepy: "Sleepy", wink: "Wink", hearts: "Hearts", startled: "Startled" },
  mouth: { derp: "Derp", grin: "Grin", smile: "Smile", buck: "Buck teeth", blep: "Blep", o: "Oh", smirk: "Smirk" },
  hair: { none: "No hair", sprout: "Sprout", bowl: "Bowl cut", swoop: "Swoop", spiky: "Spiky", curly: "Curly", mohawk: "Mohawk", bun: "Bun", long: "Long", beanie: "Beanie", cap: "Cap", party: "Party hat", flower: "Flower", crown: "Crown", wizard: "Wizard hat" },
  extras: { none: "Nothing", nerd: "Taped glasses", round: "Round glasses", shades: "Shades", freckles: "Freckles", blush: "Blush", bandage: "Bandage", headphones: "Headphones", bowtie: "Bow tie", monocle: "Monocle" },
  backdrop: { stars: "Starry night" },
};
const label = (part, value) => LABELS[part]?.[value] ?? (value === "none" ? "None" : value[0].toUpperCase() + value.slice(1));
const $ = id => document.getElementById(id);

let dork = randomDork();
let tab = "face";
// Your days together if your dork is a pet (Just for fun), which unlock outfits.
let petDays = null;
// Whether you've picked Doodle's results (when starting Derp, after your dork).
let doodlePicked = true;

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
  $("days").hidden = petDays === null;
  $("days").textContent = petDays === 1 ? "🐾 Your first day together" : `🐾 ${petDays} days together`;
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
    // A pet's outfit it hasn't earned yet: shown locked.
    if (!unlocked(part, value, petDays) && dork[part] !== value) {
      b.disabled = true;
      b.classList.add("locked");
      b.setAttribute("aria-label", `Locked: unlocks after ${unlockOf(part, value).days} days together`);
    }
    if (swatch) b.style.setProperty("--swatch", swatch);
    if (content) b.append(content);
    return b;
  };
  const grid = $("grid");
  grid.hidden = !current.options;
  if (current.options) {
    grid.replaceChildren(
      ...PARTS[current.options].filter(value => offered(current.options, value)).map(value => {
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
    colors.replaceChildren(
      ...Object.entries(PARTS[current.colors])
        .filter(([value]) => offered(current.colors, value))
        .map(([value, color]) => choice(current.colors, value, null, color))
    );
  }
}

/** Pet outfits are offered once your dork is a pet (locked until earned), and
 * not at all otherwise, unless your dork already wears one. */
function offered(part, value) {
  return petDays !== null || unlocked(part, value, null) || dork[part] === value;
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
  } else if (b.dataset.doodle) {
    await derp({ type: "doodle.set", results: b.dataset.doodle });
    location.replace("newtab.html");
  } else if (b.id === "done") {
    await saveDork(dork);
    if (welcome) {
      await derp({ type: "made" });
      // Starting Derp: next, where Doodle's results come from.
      if (doodlePicked) {
        location.replace("newtab.html");
      } else {
        document.body.classList.add("asking");
        $("doodle-ask").hidden = false;
        scrollTo(0, 0);
      }
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
  ({ dork, petDays, doodlePicked } = await myDork());
  // From "Try it on" (a dork pet's new outfit): dork.html?wear=hair.crown
  const [part, value] = (new URLSearchParams(location.search).get("wear") || "").split(".");
  if (PARTS[part] && choices(part).includes(value) && unlocked(part, value, petDays)) {
    tab = TABS.find(t => t.id === part || t.colors === part || t.options === part)?.id ?? tab;
    update({ [part]: value });
  } else {
    render(false);
  }
})();
