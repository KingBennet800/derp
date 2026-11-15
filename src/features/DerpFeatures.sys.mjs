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
 *   Google's results in Doodle's look (doodle-look/), dark while Derp is
 *   dark.
 * - Your devices: pair with Derp on your phone to share bookmarks, passwords
 *   and open tabs, end-to-end encrypted (DerpPair.sys.mjs).
 * - Just for fun (all off by default): Duck mode, where now and then a duck
 *   eats what you typed in the address bar (DerpDuck.sys.mjs), Dork pet
 *   (DerpPet.sys.mjs), and Snail mode, Peekaboo, Party mode, Sleepy tabs,
 *   Power typing, Hiccups, Tab ghosts and Rainbow mode (DerpFun.sys.mjs).
 * - Screenshot with stickers, in a page's context menu (DerpStickers.sys.mjs,
 *   with stickers.js).
 * - A "Derp" page in Settings for these, JPEG XL and AI controls, and
 *   checking for updates now (DerpUpdates.sys.mjs).
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
      for (const feature of [Strings, WebApps, MemorySaver, Dork, Duck, Fun, Pet, Stickers, Doodle, Pair, SettingsSection, Layout]) {
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

const Pet = {
  init() {
    const { DerpPet } = ChromeUtils.importESModule(derpURL("DerpPet.sys.mjs"));
    const { DerpDork } = ChromeUtils.importESModule(derpURL("DerpDork.sys.mjs"));
    DerpPet.init({ cssURL: derpURL("pet.css"), dork: DerpDork });
  },
};

const Stickers = {
  init() {
    const { DerpStickers } = ChromeUtils.importESModule(derpURL("DerpStickers.sys.mjs"));
    const { DerpDork } = ChromeUtils.importESModule(derpURL("DerpDork.sys.mjs"));
    const { DUCK_URL } = ChromeUtils.importESModule(derpURL("DerpDuck.sys.mjs"));
    const { SNAIL_URL, GHOST_URL } = ChromeUtils.importESModule(derpURL("DerpFun.sys.mjs"));
    DerpStickers.init({
      cssURL: derpURL("stickers.css"),
      scriptURL: derpURL("stickers.js"),
      dork: DerpDork,
      critters: { duck: DUCK_URL, snail: SNAIL_URL, ghost: GHOST_URL },
    });
  },
};

const Fun = {
  init() {
    const { DerpFun } = ChromeUtils.importESModule(derpURL("DerpFun.sys.mjs"));
    const { DerpDork } = ChromeUtils.importESModule(derpURL("DerpDork.sys.mjs"));
    const { DUCK_URL } = ChromeUtils.importESModule(derpURL("DerpDuck.sys.mjs"));
    DerpFun.init({ cssURL: derpURL("fun.css"), dork: DerpDork, duckURL: DUCK_URL });
  },
};

// Doodle searches Google, with doodle=1 in the address to mark the page as
// Doodle's, which gets Doodle's look. Derp tells Google whether it's light or
// dark, the way Chrome does (its Sec-CH-Prefers-Color-Scheme hint, which
// Google doesn't get from Firefox otherwise), so Google's pages, Doodle's
// results among them, come in Derp's theme.
const Doodle = {
  init() {
    Services.obs.addObserver(this, "http-on-modify-request");
    this.installLook().catch(e => console.error("Doodle's look didn't install:", e));
  },
  observe(subject) {
    const channel = subject.QueryInterface(Ci.nsIHttpChannel);
    if (
      channel.URI.host === "www.google.com" &&
      channel.loadInfo.externalContentPolicyType === Ci.nsIContentPolicy.TYPE_DOCUMENT
    ) {
      channel.setRequestHeader("Sec-CH-Prefers-Color-Scheme", this.dark() ? "dark" : "light", false);
    }
  },
  // Settings → Website appearance: dark, light, or (2) following the theme.
  dark() {
    const appearance = Services.prefs.getIntPref("layout.css.prefers-color-scheme.content-override", 2);
    return appearance === 2 ? Services.appinfo.contentThemeDerivedColorSchemeIsDark : appearance === 0;
  },
  // Doodle's look on its result pages is a tiny built-in extension
  // (doodle-look/): web pages' processes can't read Derp's files, but an
  // extension's content script reaches them. It's installed again whenever
  // its files change, and allowed in private windows too.
  LOOK: "doodle-look@kingbennet800.github.io",
  LOOK_PREF: "derp.doodle.lookInstalled",
  async installLook() {
    const { AddonManager } = ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs");
    const { ExtensionPermissions } = ChromeUtils.importESModule("resource://gre/modules/ExtensionPermissions.sys.mjs");
    const base = "resource://derp/doodle-look/";
    const stamp = ["manifest.json", "doodle-page.js", "doodle-page.css"].map(f => derpURL(`doodle-look/${f}`).split("?v=")[1]).join(".");
    const { version } = await (await fetch(base + "manifest.json")).json();
    if (Services.prefs.getStringPref(this.LOOK_PREF, "") !== stamp) {
      // Out with the old copy first: Firefox keeps an extension's manifest
      // (what pages it runs on) cached by version, which may not have changed.
      await (await AddonManager.getAddonByID(this.LOOK))?.uninstall();
      await AddonManager.installBuiltinAddon(base);
      Services.prefs.setStringPref(this.LOOK_PREF, stamp);
    } else {
      await AddonManager.maybeInstallBuiltinAddon(this.LOOK, version, base);
    }
    await ExtensionPermissions.add(this.LOOK, { permissions: ["internal:privateBrowsingAllowed"], origins: [] });
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
      updates: derpURL("DerpUpdates.sys.mjs"),
    };
    Services.scriptloader.loadSubScriptWithOptions(derpURL("derp-settings.js"), {
      target: win,
      ignoreCache: true,
    });
  },
};
