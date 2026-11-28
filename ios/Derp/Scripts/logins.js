"use strict";
// Saved passwords: when you sign in somewhere, Derp offers to save the
// password; when you come back and tap the sign-in form, it offers to fill it
// in. Runs in Derp's own script world, apart from the page's scripts.
(() => {
  if (!/^https?:$/.test(location.protocol)) return;
  const post = message => window.webkit.messageHandlers.derpPage.postMessage({ ...message, origin: location.origin });
  const visible = input => input.getClientRects().length > 0;
  const passwordFields = () => [...document.querySelectorAll('input[type="password"]')].filter(visible);

  /** The username field that goes with [password]: the last text field before it. */
  function usernameFor(password) {
    const scope = password.form || document;
    const inputs = [...scope.querySelectorAll("input")].filter(i => visible(i) && /^(text|email|tel|)$/i.test(i.getAttribute("type") || ""));
    const before = inputs.filter(i => i.compareDocumentPosition(password) & Node.DOCUMENT_POSITION_FOLLOWING);
    return before[before.length - 1] || inputs.find(i => /user|email|login|account/i.test(`${i.name} ${i.id} ${i.autocomplete}`)) || null;
  }

  let reported = "";
  function report() {
    const password = passwordFields().find(p => p.value);
    if (!password) return;
    // Sign-up and change-password forms have more than one: the last is the new one.
    const fields = password.form ? [...password.form.querySelectorAll('input[type="password"]')].filter(visible) : [password];
    const newest = fields[fields.length - 1];
    const user = usernameFor(fields[0]);
    const key = `${user?.value || ""}\n${newest.value}`;
    if (key === reported) return;
    reported = key;
    let action = location.origin;
    try {
      if (password.form?.action) action = new URL(password.form.action, location.href).origin;
    } catch {}
    post({ type: "login.submit", username: user?.value || "", password: newest.value, action });
  }
  addEventListener("submit", report, true);
  addEventListener("click", e => {
    if (e.target instanceof Element && e.target.closest('button, input[type="submit"], [role="button"]')) setTimeout(report, 0);
  }, true);
  addEventListener("keydown", e => {
    if (e.key === "Enter" && e.target instanceof HTMLInputElement) setTimeout(report, 0);
  }, true);
  addEventListener("pagehide", report, true);

  // Tapping a sign-in field asks Derp to offer the logins it has (once per page).
  let offered = false;
  addEventListener("focusin", e => {
    const field = e.target;
    if (offered || !(field instanceof HTMLInputElement)) return;
    const password = field.type === "password" ? field : passwordFields()[0];
    if (!password || (field !== password && field !== usernameFor(password))) return;
    offered = true;
    post({ type: "login.focus" });
  }, true);

  window.derpFill = (username, password) => {
    const field = passwordFields()[0];
    if (!field) return false;
    const user = usernameFor(field);
    const set = (input, value) => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(input, value);
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
    };
    if (user && username) set(user, username);
    set(field, password);
    // What Derp filled in isn't news.
    reported = `${username}\n${password}`;
    return true;
  };
})();
