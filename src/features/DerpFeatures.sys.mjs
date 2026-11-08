/* Derp's browser features, loaded at startup by derp.cfg (Firefox autoconfig).
 * Managed by Derp's installer.
 *
 * - Web apps: install a site as an app with its own window and dock icon.
 *   Firefox ships this as "Taskbar Tabs" (Windows-first, off on Linux); Derp
 *   turns it on and, on Linux, points the desktop entries it writes at Derp's
 *   launcher.
 * - Memory Saver: unloads tabs you haven't looked at for a while.
 * - Your dork: Derp's own account, an avatar you design, kept on this device
 *   (DerpDork.sys.mjs).
 * - Doodle: Derp's search (the default, by policy in config/policies.json),
 *   DuckDuckGo's results in Derp's colors, dark while Derp is dark.
 * - Your devices: pair with Derp on your phone to share bookmarks, passwords
 *   and open tabs, end-to-end encrypted (DerpPair.sys.mjs).
 * - Just for fun (all off by default): Duck mode, where now and then a duck
 *   eats what you typed in the address bar (DerpDuck.sys.mjs), and Snail
 *   mode, Peekaboo, Party mode, Sleepy tabs, Power typing, Hiccups, Tab ghosts
 *   and Rainbow mode (DerpFun.sys.mjs).
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

// resource://derp/<name>, versioned by the file's modification time so the
// startup cache never serves an older copy after an update.
function derpURL(name) {
  const base = Services.io.getProtocolHandler("resource").QueryInterface(Ci.nsIResProtocolHandler).getSubstitution("derp");
  const file = base.QueryInterface(Ci.nsIFileURL).file.clone();
  for (const part of name.split("/")) {
    file.append(part);
  }
  return `resource://derp/${name}?v=${file.exists() ? file.lastModifiedTime : 0}`;
}

const PREFS = {
  memorySaver: "derp.memorySaver.enabled",
  memorySaverMinutes: "derp.memorySaver.minutes",
};

export const DerpFeatures = {
  init() {
    const onStartup = () => {
      Services.obs.removeObserver(onStartup, "final-ui-startup");
      for (const feature of [Strings, WebApps, MemorySaver, Dork, Duck, Fun, Doodle, Pair, SettingsSection, Layout]) {
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

// Derp's strings: resource://derp/locales/<locale>/derp/*.ftl
const Strings = {
  init() {
    const source = new L10nFileSource("derp", "app", ["en-US"], "resource://derp/locales/{locale}/");
    L10nRegistry.getInstance().registerSources([source]);
  },
};

const Dork = {
  init() {
    const { DerpDork } = ChromeUtils.importESModule(derpURL("DerpDork.sys.mjs"));
    DerpDork.init({ cssURL: derpURL("dork.css") });
  },
};

const Duck = {
  init() {
    const { DerpDuck } = ChromeUtils.importESModule(derpURL("DerpDuck.sys.mjs"));
    DerpDuck.init({ cssURL: derpURL("duck.css") });
  },
};

const Fun = {
  init() {
    const { DerpFun } = ChromeUtils.importESModule(derpURL("DerpFun.sys.mjs"));
    const { DerpDork } = ChromeUtils.importESModule(derpURL("DerpDork.sys.mjs"));
    DerpFun.init({ cssURL: derpURL("fun.css"), dork: DerpDork });
  },
};

// Doodle's search address carries DuckDuckGo's settings for Derp's light
// colors (DuckDuckGo stays light unless asked). While websites are shown dark,
// Doodle's searches swap them for its dark theme in Derp's dark colors.
const Doodle = {
  LIGHT: "k9=2f6feb&kaa=7a52c7&kx=0f8a74",
  DARK: "kae=d&k9=86b1ff&kaa=a98bf0&kx=34c6a0",
  init() {
    Services.obs.addObserver(this, "http-on-modify-request");
  },
  observe(subject) {
    const channel = subject.QueryInterface(Ci.nsIHttpChannel);
    const uri = channel.URI;
    if (
      uri.host !== "duckduckgo.com" ||
      !uri.query.includes(this.LIGHT) ||
      channel.loadInfo.externalContentPolicyType !== Ci.nsIContentPolicy.TYPE_DOCUMENT ||
      !this.dark()
    ) {
      return;
    }
    channel.redirectTo(Services.io.newURI(uri.spec.replace(this.LIGHT, this.DARK)));
  },
  // Settings → Website appearance: dark, light, or (2) following the theme.
  dark() {
    const appearance = Services.prefs.getIntPref("layout.css.prefers-color-scheme.content-override", 2);
    return appearance === 2 ? Services.appinfo.contentThemeDerivedColorSchemeIsDark : appearance === 0;
  },
};

const Pair = {
  init() {
    const { DerpPair } = ChromeUtils.importESModule(derpURL("DerpPair.sys.mjs"));
    const { DerpDork } = ChromeUtils.importESModule(derpURL("DerpDork.sys.mjs"));
    DerpPair.init({ cssURL: derpURL("pair.css"), dork: DerpDork });
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
    win.derpURLs = {
      settings: derpURL("DerpSettings.mjs"),
      dork: derpURL("DerpDork.sys.mjs"),
      duck: derpURL("DerpDuck.sys.mjs"),
      pair: derpURL("DerpPair.sys.mjs"),
    };
    Services.scriptloader.loadSubScriptWithOptions(derpURL("derp-settings.js"), {
      target: win,
      ignoreCache: true,
    });
  },
};
