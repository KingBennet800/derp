/* Derp's browser features, loaded at startup by derp.cfg (Firefox autoconfig).
 * Managed by Derp's installer.
 *
 * - Web apps: install a site as an app with its own window and dock icon.
 *   Firefox ships this as "Taskbar Tabs" (Windows-first, off on Linux); Derp
 *   turns it on and, on Linux, points the desktop entries it writes at Derp's
 *   launcher.
 * - Memory Saver: unloads tabs you haven't looked at for a while.
 * - A "Derp" page in Settings for these, JPEG XL and AI controls.
 * - Derp's minimal toolbar layout, applied once (you can rearrange after).
 * Mozilla's account and online services are off by policy (config/). */

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  CustomizableUI: "moz-src:///browser/components/customizableui/CustomizableUI.sys.mjs",
  PrivateBrowsingUtils: "resource://gre/modules/PrivateBrowsingUtils.sys.mjs",
  ShellService: "moz-src:///browser/components/shell/ShellService.sys.mjs",
  TaskbarTabsUtils: "moz-src:///browser/components/taskbartabs/TaskbarTabsUtils.sys.mjs",
  setInterval: "resource://gre/modules/Timer.sys.mjs",
  webrtcUI: "resource:///modules/webrtcUI.sys.mjs",
});

// derp.cfg imports this module as ...?v=<mtime>; reuse it to version what we load.
const VERSION = new URL(import.meta.url).searchParams.get("v") ?? "0";

const PREFS = {
  memorySaver: "derp.memorySaver.enabled",
  memorySaverMinutes: "derp.memorySaver.minutes",
};

export const DerpFeatures = {
  init() {
    const onStartup = () => {
      Services.obs.removeObserver(onStartup, "final-ui-startup");
      for (const feature of [WebApps, MemorySaver, SettingsSection, Layout]) {
        try {
          feature.init();
        } catch (e) {
          console.error("Derp feature failed to start:", e);
        }
      }
    };
    Services.obs.addObserver(onStartup, "final-ui-startup");
  },
};

const WebApps = {
  init() {
    // Windows has these natively; macOS doesn't support them yet.
    if (Services.appinfo.OS === "Darwin") {
      Services.prefs.getDefaultBranch("").setBoolPref("browser.taskbarTabs.enabled", false);
    }
    if (Services.appinfo.OS !== "Linux") {
      return;
    }
    // Linux desktop entries must start Derp through its launcher, which adds the
    // "derp" instance name; the bare engine would collide with a running Derp.
    const launcher = PathUtils.join(Services.dirsvc.get("Home", Ci.nsIFile).path, ".local", "bin", "derp");
    lazy.ShellService._findStartupCommand = async () => launcher;
    lazy.TaskbarTabsUtils._determineNewDesktopEntryName = id => `derp.webapp-${id}`;
  },
};

const Layout = {
  PREF: "derp.layout.version",
  // Each step runs once per profile, in order; you can rearrange freely after.
  STEPS: [
    // 1: uBlock Origin lives in the extensions menu, off the toolbar.
    CustomizableUI => CustomizableUI.addWidgetToArea("ublock0_raymondhill_net-browser-action", CustomizableUI.AREA_ADDONS),
    // 2: no Mozilla account button (Derp turns accounts off).
    CustomizableUI => CustomizableUI.removeWidgetFromArea("fxa-toolbar-menu-button"),
  ],

  init() {
    const done = Services.prefs.getIntPref(this.PREF, 0);
    if (done >= this.STEPS.length) {
      return;
    }
    const apply = () => {
      Services.obs.removeObserver(apply, "browser-delayed-startup-finished");
      for (const step of this.STEPS.slice(done)) {
        try {
          step(lazy.CustomizableUI);
        } catch (e) {
          console.error("Derp layout step failed:", e);
        }
      }
      Services.prefs.setIntPref(this.PREF, this.STEPS.length);
    };
    Services.obs.addObserver(apply, "browser-delayed-startup-finished");
  },
};

const MemorySaver = {
  init() {
    lazy.setInterval(() => this.sweep(), 60 * 1000);
  },

  sweep() {
    if (!Services.prefs.getBoolPref(PREFS.memorySaver, true)) {
      return;
    }
    const minutes = Math.max(5, Services.prefs.getIntPref(PREFS.memorySaverMinutes, 30));
    const cutoff = Date.now() - minutes * 60 * 1000;
    for (const win of Services.wm.getEnumerator("navigator:browser")) {
      if (win.closed || !win.gBrowser || lazy.PrivateBrowsingUtils.isWindowPrivate(win)) {
        continue;
      }
      for (const tab of win.gBrowser.tabs) {
        if (tab.lastAccessed < cutoff && !this.mustKeep(tab)) {
          // discardBrowser itself refuses selected tabs, open dialogs and
          // pages that would warn about unsaved changes.
          win.gBrowser.discardBrowser(tab);
        }
      }
    }
  },

  mustKeep(tab) {
    const browser = tab.linkedBrowser;
    return (
      !browser?.isConnected || // already unloaded
      tab.pinned ||
      tab.splitview ||
      tab.soundPlaying ||
      tab.pictureinpicture ||
      tab.undiscardable ||
      lazy.webrtcUI.browserHasStreams(browser) ||
      !!browser.browsingContext?.currentWindowGlobal?.hasActivePeerConnections()
    );
  },
};

const SettingsSection = {
  init() {
    // Derp's strings: resource://derp/locales/<locale>/derp/settings.ftl
    const source = new L10nFileSource("derp", "app", ["en-US"], "resource://derp/locales/{locale}/");
    L10nRegistry.getInstance().registerSources([source]);
    Services.obs.addObserver(this, "document-element-inserted");
  },

  observe(doc) {
    const url = doc.documentURI || "";
    if (url.startsWith("about:preferences") || url.startsWith("about:settings")) {
      // Runs before Settings' own DOMContentLoaded handler, so Derp's pane
      // is registered by the time Settings picks which pane to show.
      // (Capture on the window runs before Settings' listener on the document.)
      doc.defaultView?.addEventListener("DOMContentLoaded", () => this.addPane(doc.defaultView), {
        once: true,
        capture: true,
      });
    }
  },

  addPane(win) {
    win.derpFeaturesVersion = VERSION;
    Services.scriptloader.loadSubScriptWithOptions(`resource://derp/derp-settings.js?v=${VERSION}`, {
      target: win,
      ignoreCache: true,
    });
  },
};
