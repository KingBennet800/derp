/* Adds Derp's pane to Settings. DerpFeatures runs this in the Settings window
 * just before Settings initializes, so the pane exists when Settings picks
 * which one to show. */
{
  document.l10n.addResourceIds(["derp/settings.ftl"]);

  const button = document.createElementNS("http://www.w3.org/1999/xhtml", "moz-page-nav-button");
  button.id = "category-derp";
  button.setAttribute("view", "paneDerp");
  button.setAttribute("iconsrc", "chrome://branding/content/about-logo.svg");
  button.setAttribute("data-l10n-id", "pane-derp-title");
  const tabsBrowsing = document.getElementById("category-tabs-browsing");
  if (tabsBrowsing) {
    tabsBrowsing.after(button);
  } else {
    document.getElementById("categories").append(button);
  }

  // Mozilla accounts are off, so "Account and sync" becomes Derp's own
  // account page: your dork first, then import and backup. Mozilla's account
  // cards and referral promo go. The page's module is Derp's settings, which
  // load the original account-sync module too.
  const { DerpDork } = ChromeUtils.importESModule(window.derpURLs.dork);
  const accountsOff = !Services.prefs.getBoolPref("identity.fxaccounts.enabled", true);
  if (accountsOff && typeof CONFIG_PANES == "object" && CONFIG_PANES.sync) {
    const mozilla = ["accountDisabled", "account", "sync", "referrals"];
    CONFIG_PANES.sync.groupIds = ["derpDork", ...CONFIG_PANES.sync.groupIds.filter(id => !mozilla.includes(id))];
    CONFIG_PANES.sync.l10nId = "derp-you-section";
    CONFIG_PANES.sync.iconSrc = DerpDork.dataURL(undefined, 64);
    CONFIG_PANES.sync.module = window.derpURLs.settings;
  }
  // Settings labels the nav button as it initializes, which happens in the
  // document's DOMContentLoaded listener; this one runs right after it.
  document.addEventListener(
    "DOMContentLoaded",
    () => {
      const nav = document.getElementById("category-sync");
      if (!nav || !accountsOff) {
        return;
      }
      nav.setAttribute("data-l10n-id", "derp-pane-you-title");
      const paint = () => {
        nav.iconSrc = DerpDork.dataURL(undefined, 64);
      };
      paint();
      Services.prefs.addObserver(DerpDork.PREF, paint);
      window.addEventListener("unload", () => Services.prefs.removeObserver(DerpDork.PREF, paint), { once: true });
    },
    { once: true }
  );

  SettingPaneManager.registerPane("derp", {
    l10nId: "derp-pane-header",
    iconSrc: "chrome://branding/content/about-logo.svg",
    groupIds: ["derpMemorySaver", "derpWebApps", "derpImages", "derpAi", "derpFun"],
    module: window.derpURLs.settings,
    visible: () => true,
  });
}
