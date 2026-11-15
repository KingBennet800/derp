"use strict";
// Screenshot with stickers: a picture of a page, with stickers you put on it
// (your dork, googly eyes, the duck…), to save or copy. Plain script with no
// privileges, shared by desktop Derp (DerpStickers.sys.mjs shows it over the
// window) and Derp for Android (stickers.html, a page of its own): the host
// says where the picture comes from and what to do with the result.
//
// Stickers sit in the picture's coordinates (centre, size as a share of the
// picture's width, turn), so the saved picture matches what you see at any
// size. Drag a sticker to move it; drag its round handle to resize and turn
// it; its × (or Delete) takes it off.

/* exported DerpStickerEditor */
var DerpStickerEditor = (() => {
  const art = s => "data:image/svg+xml;charset=utf-8," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 64 64">${s}</svg>`);

  /** Stickers of its own; the host adds your dork and Derp's critters. */
  const BUILT_IN = [
    {
      id: "googly",
      url: art(
        `<circle cx="18" cy="32" r="15" fill="#fff" stroke="#1d2030" stroke-width="2.5"/><circle cx="46" cy="32" r="15" fill="#fff" stroke="#1d2030" stroke-width="2.5"/>` +
          `<circle cx="22" cy="37" r="7" fill="#1d2030"/><circle cx="41" cy="36" r="7" fill="#1d2030"/><circle cx="19.5" cy="34.5" r="2" fill="#fff"/><circle cx="38.5" cy="33.5" r="2" fill="#fff"/>`
      ),
    },
    { id: "heart", url: art(`<path d="M32 56S6 40 6 23a13 13 0 0 1 26-6 13 13 0 0 1 26 6c0 17-26 33-26 33z" fill="#ff5d8f"/><ellipse cx="19" cy="20" rx="5" ry="3.5" transform="rotate(-30 19 20)" fill="#fff" opacity=".45"/>`) },
    { id: "star", url: art(`<path d="M32 4l8.2 17.4 19 2.4-14 13.1 3.6 18.8L32 46.6 15.2 55.7l3.6-18.8-14-13.1 19-2.4z" fill="#ffd43b" stroke="#e0a800" stroke-width="2.5" stroke-linejoin="round"/>`) },
    { id: "sparkle", url: art(`<path d="M32 4c2 14 6 22 26 28-20 6-24 14-26 28-2-14-6-22-26-28 20-6 24-14 26-28z" fill="#b8a4ff"/><path d="M52 6c.8 4 2 6 6 7-4 1-5.2 3-6 7-.8-4-2-6-6-7 4-1 5.2-3 6-7z" fill="#2fd6be"/>`) },
    { id: "shades", url: art(`<rect x="4" y="22" width="24" height="18" rx="7" fill="#15161c"/><rect x="36" y="22" width="24" height="18" rx="7" fill="#15161c"/><path d="M28 28h8" stroke="#15161c" stroke-width="4"/><path d="M10 27l7-3M42 27l7-3" stroke="#fff" stroke-opacity=".5" stroke-width="3" stroke-linecap="round"/>`) },
    { id: "crown", url: art(`<path d="M8 50 5 18l14 12 13-20 13 20 14-12-3 32z" fill="#ffd43b" stroke="#d99a00" stroke-width="3" stroke-linejoin="round"/><circle cx="32" cy="38" r="4" fill="#ff5d7a"/><circle cx="18" cy="41" r="3" fill="#3b74f0"/><circle cx="46" cy="41" r="3" fill="#22bfa8"/>`) },
    {
      id: "derp",
      url: art(
        `<path d="M6 10h52a4 4 0 0 1 4 4v24a4 4 0 0 1-4 4H26l-12 12v-12H6a4 4 0 0 1-4-4V14a4 4 0 0 1 4-4z" fill="#fff" stroke="#1d2030" stroke-width="2.5" stroke-linejoin="round"/>` +
          `<text x="32" y="33" text-anchor="middle" font-family="system-ui, sans-serif" font-size="15" font-weight="800" fill="#2f6feb">derp!</text>`
      ),
    },
  ];

  const loadImage = url =>
    new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error(`couldn't load ${url.slice(0, 40)}`));
      img.src = url;
    });

  /**
   * Builds the editor into [root] (emptied first) for the picture at [image].
   * [stickers]: the host's stickers ({ id, url, label? }), before the built-in ones.
   * [labels]: { title, hint, save, copy?, cancel, remove } in your language.
   * [onSave]/[onCopy] get the finished picture as a PNG blob (no Copy button
   * without onCopy); [onClose] is called when it's cancelled.
   */
  async function open({ root, image, stickers = [], labels, onSave, onCopy, onClose }) {
    const doc = root.ownerDocument;
    const h = (tag, attrs = {}, ...children) => {
      const el = doc.createElement(tag);
      for (const [k, v] of Object.entries(attrs)) {
        el.setAttribute(k, v);
      }
      el.append(...children);
      return el;
    };
    const shot = await loadImage(image);
    const all = [...stickers, ...BUILT_IN];
    const placed = [];
    let selected = null;

    const picture = h("img", { class: "derp-st-shot", src: image, alt: "", draggable: "false" });
    const stage = h("div", { class: "derp-st-stage" }, picture);
    const tray = h(
      "div",
      { class: "derp-st-tray", role: "toolbar" },
      ...all.map(s => {
        const button = h("button", { type: "button", "data-sticker": s.id, title: s.label ?? "", "aria-label": s.label ?? s.id });
        button.append(h("img", { src: s.url, alt: "" }));
        return button;
      })
    );
    const save = h("button", { type: "button", class: "derp-st-primary" }, labels.save);
    const copy = onCopy ? h("button", { type: "button" }, labels.copy) : "";
    const cancel = h("button", { type: "button" }, labels.cancel);
    const editor = h(
      "div",
      { class: "derp-st", role: "dialog", "aria-label": labels.title },
      h("div", { class: "derp-st-top" }, h("strong", {}, labels.title), h("span", { class: "derp-st-hint" }, labels.hint)),
      h("div", { class: "derp-st-area" }, stage),
      tray,
      h("div", { class: "derp-st-actions" }, cancel, copy, save)
    );
    root.replaceChildren(editor);

    // ── Placing stickers ─────────────────────────────────────────────────
    const rect = () => stage.getBoundingClientRect();
    const draw = item => {
      const { node } = item;
      node.style.left = `${item.x * 100}%`;
      node.style.top = `${item.y * (shot.naturalWidth / shot.naturalHeight) * 100}%`;
      node.style.width = `${item.size * 100}%`;
      node.style.rotate = `${item.turn}rad`;
    };
    const select = item => {
      selected = item;
      for (const other of placed) {
        other.node.classList.toggle("derp-st-selected", other === item);
      }
    };
    const remove = item => {
      item.node.remove();
      placed.splice(placed.indexOf(item), 1);
      if (selected === item) {
        select(null);
      }
    };
    const add = sticker => {
      const node = h("div", { class: "derp-st-sticker", tabindex: "0" });
      const img = h("img", { src: sticker.url, alt: "", draggable: "false" });
      const close = h("button", { type: "button", class: "derp-st-x", "aria-label": labels.remove }, "×");
      const grip = h("span", { class: "derp-st-grip" });
      node.append(img, close, grip);
      // A little off the middle each time, so stickers don't pile up exactly.
      const nudge = (placed.length % 5) * 0.03;
      const item = { sticker, node, x: 0.5 + nudge, y: 0.5 * (shot.naturalHeight / shot.naturalWidth) + nudge, size: 0.16, turn: 0 };
      placed.push(item);
      stage.append(node);
      draw(item);
      select(item);

      close.addEventListener("click", e => {
        e.stopPropagation();
        remove(item);
      });
      // Drag to move.
      node.addEventListener("pointerdown", e => {
        if (e.target === close || e.target === grip) {
          return;
        }
        e.preventDefault();
        select(item);
        node.focus({ preventScroll: true });
        node.setPointerCapture(e.pointerId);
        const start = { x: e.clientX, y: e.clientY, ix: item.x, iy: item.y };
        const move = m => {
          const w = rect().width;
          item.x = start.ix + (m.clientX - start.x) / w;
          item.y = start.iy + (m.clientY - start.y) / w;
          draw(item);
        };
        const up = () => {
          node.removeEventListener("pointermove", move);
          node.removeEventListener("pointerup", up);
          node.removeEventListener("pointercancel", up);
        };
        node.addEventListener("pointermove", move);
        node.addEventListener("pointerup", up);
        node.addEventListener("pointercancel", up);
      });
      // Drag the grip to resize and turn: it follows your pointer around the centre.
      grip.addEventListener("pointerdown", e => {
        e.preventDefault();
        e.stopPropagation();
        select(item);
        grip.setPointerCapture(e.pointerId);
        const r = rect();
        const centre = () => ({ x: r.left + item.x * r.width, y: r.top + item.y * r.width });
        const c = centre();
        const startAngle = Math.atan2(e.clientY - c.y, e.clientX - c.x);
        const startDist = Math.hypot(e.clientX - c.x, e.clientY - c.y) || 1;
        const start = { size: item.size, turn: item.turn };
        const move = m => {
          const angle = Math.atan2(m.clientY - c.y, m.clientX - c.x);
          const dist = Math.hypot(m.clientX - c.x, m.clientY - c.y);
          item.size = Math.min(1.2, Math.max(0.03, start.size * (dist / startDist)));
          item.turn = start.turn + angle - startAngle;
          draw(item);
        };
        const up = () => {
          grip.removeEventListener("pointermove", move);
          grip.removeEventListener("pointerup", up);
          grip.removeEventListener("pointercancel", up);
        };
        grip.addEventListener("pointermove", move);
        grip.addEventListener("pointerup", up);
        grip.addEventListener("pointercancel", up);
      });
      // The mouse wheel resizes too (with Shift, turns).
      node.addEventListener(
        "wheel",
        e => {
          e.preventDefault();
          select(item);
          if (e.shiftKey) {
            item.turn += Math.sign(e.deltaY || e.deltaX) * 0.12;
          } else {
            item.size = Math.min(1.2, Math.max(0.03, item.size * (e.deltaY > 0 ? 0.92 : 1.08)));
          }
          draw(item);
        },
        { passive: false }
      );
    };

    tray.addEventListener("click", e => {
      const button = e.target.closest("[data-sticker]");
      if (button) {
        add(all.find(s => s.id === button.dataset.sticker));
      }
    });
    stage.addEventListener("pointerdown", e => {
      if (e.target === stage || e.target === picture) {
        select(null);
      }
    });
    editor.addEventListener("keydown", e => {
      if ((e.key === "Delete" || e.key === "Backspace") && selected) {
        e.preventDefault();
        remove(selected);
      } else if (e.key === "Escape") {
        e.preventDefault();
        onClose?.();
      }
    });

    // ── The finished picture ─────────────────────────────────────────────
    const render = async () => {
      const canvas = doc.createElement("canvas");
      canvas.width = shot.naturalWidth;
      canvas.height = shot.naturalHeight;
      const ctx = canvas.getContext("2d");
      ctx.drawImage(shot, 0, 0);
      const w = canvas.width;
      for (const item of placed) {
        const img = await loadImage(item.sticker.url);
        const size = item.size * w;
        const aspect = img.naturalHeight / img.naturalWidth || 1;
        ctx.save();
        ctx.translate(item.x * w, item.y * w);
        ctx.rotate(item.turn);
        ctx.drawImage(img, -size / 2, (-size * aspect) / 2, size, size * aspect);
        ctx.restore();
      }
      return new Promise(resolve => canvas.toBlob(resolve, "image/png"));
    };
    const busy = async action => {
      for (const b of editor.querySelectorAll(".derp-st-actions > button")) {
        b.disabled = true;
      }
      try {
        await action(await render());
      } finally {
        for (const b of editor.querySelectorAll(".derp-st-actions > button")) {
          b.disabled = false;
        }
      }
    };
    save.addEventListener("click", () => busy(onSave));
    if (onCopy) {
      copy.addEventListener("click", () => busy(onCopy));
    }
    cancel.addEventListener("click", () => onClose?.());
    editor.focus?.();
    return { add: id => add(all.find(s => s.id === id)), placed };
  }

  return { open, BUILT_IN };
})();
