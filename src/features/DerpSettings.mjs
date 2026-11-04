/* Settings for Derp's pane. Settings imports this into its own window when
 * the pane opens, like its built-in config modules. */

import { Preferences } from "chrome://global/content/preferences/Preferences.mjs";
import { SettingGroupManager } from "chrome://browser/content/preferences/config/SettingGroupManager.mjs";

const UNLOAD_AFTER_MINUTES = [15, 30, 60, 120, 240];

Preferences.addAll([
  { id: "derp.memorySaver.enabled", type: "bool" },
  { id: "derp.memorySaver.minutes", type: "int" },
  { id: "browser.taskbarTabs.enabled", type: "bool" },
  { id: "image.jxl.enabled", type: "bool" },
]);

Preferences.addSetting({ id: "derpMemorySaver", pref: "derp.memorySaver.enabled" });
Preferences.addSetting({
  id: "derpMemorySaverMinutes",
  pref: "derp.memorySaver.minutes",
  deps: ["derpMemorySaver"],
  disabled: ({ derpMemorySaver }) => !derpMemorySaver.value,
  get: minutes => String(minutes),
  set: value => Number(value),
});
Preferences.addSetting({ id: "derpWebApps", pref: "browser.taskbarTabs.enabled" });
Preferences.addSetting({ id: "derpJpegXL", pref: "image.jxl.enabled" });
Preferences.addSetting({ id: "derpAiControls" });

SettingGroupManager.registerGroups({
  derpMemorySaver: {
    l10nId: "derp-memory-saver-group",
    headingLevel: 2,
    iconSrc: "chrome://global/skin/icons/performance.svg",
    items: [
      {
        id: "derpMemorySaver",
        l10nId: "derp-memory-saver",
        items: [
          {
            id: "derpMemorySaverMinutes",
            l10nId: "derp-memory-saver-after",
            control: "moz-select",
            options: UNLOAD_AFTER_MINUTES.map(m => ({ value: String(m), l10nId: `derp-after-${m}` })),
          },
        ],
      },
    ],
  },
  derpWebApps: {
    l10nId: "derp-web-apps-group",
    headingLevel: 2,
    iconSrc: "chrome://browser/skin/window.svg",
    items: [{ id: "derpWebApps", l10nId: "derp-web-apps" }],
  },
  derpImages: {
    l10nId: "derp-images-group",
    headingLevel: 2,
    iconSrc: "chrome://global/skin/icons/defaultFavicon.svg",
    items: [{ id: "derpJpegXL", l10nId: "derp-jpeg-xl" }],
  },
  derpAi: {
    l10nId: "derp-ai-group",
    headingLevel: 2,
    iconSrc: "chrome://global/skin/icons/highlights.svg",
    items: [{ id: "derpAiControls", control: "moz-box-button", l10nId: "derp-ai-controls-button", loadPane: "ai" }],
  },
});
