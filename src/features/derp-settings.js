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

  SettingPaneManager.registerPane("derp", {
    l10nId: "derp-pane-header",
    iconSrc: "chrome://branding/content/about-logo.svg",
    groupIds: ["derpMemorySaver", "derpWebApps", "derpImages", "derpAi"],
    module: `resource://derp/DerpSettings.mjs?v=${window.derpFeaturesVersion}`,
    visible: () => true,
  });
}
