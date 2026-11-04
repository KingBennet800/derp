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

  // Mozilla accounts are off, so "Account and sync" keeps only import,
  // profiles and backup: drop the "account unavailable" card and Mozilla's
  // referral promo, and name the page for what's left.
  const accountsOff = !Services.prefs.getBoolPref("identity.fxaccounts.enabled", true);
  if (accountsOff && typeof CONFIG_PANES == "object" && CONFIG_PANES.sync) {
    const hide = ["accountDisabled", "account", "sync", "referrals"];
    CONFIG_PANES.sync.groupIds = CONFIG_PANES.sync.groupIds.filter(id => !hide.includes(id));
    CONFIG_PANES.sync.l10nId = "derp-import-backup-section";
    CONFIG_PANES.sync.iconSrc = "chrome://browser/skin/import.svg";
  }
  // Settings labels the nav button as it initializes, which happens in the
  // document's DOMContentLoaded listener; this one runs right after it.
  document.addEventListener(
    "DOMContentLoaded",
    () => {
      const nav = document.getElementById("category-sync");
      if (nav && accountsOff) {
        nav.setAttribute("data-l10n-id", "derp-pane-import-backup-title");
        nav.iconSrc = "chrome://browser/skin/import.svg";
      }
    },
    { once: true }
  );

  SettingPaneManager.registerPane("derp", {
    l10nId: "derp-pane-header",
    iconSrc: "chrome://branding/content/about-logo.svg",
    groupIds: ["derpMemorySaver", "derpWebApps", "derpImages", "derpAi"],
    module: `resource://derp/DerpSettings.mjs?v=${window.derpFeaturesVersion}`,
    visible: () => true,
  });
}
