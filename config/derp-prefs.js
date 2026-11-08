// Derp default preferences.
//
// Installed as <engine>/browser/defaults/preferences/derp.js, so these are
// *defaults*: anything you change in Settings or about:config sticks.

// ── Theme ────────────────────────────────────────────────────────────────
pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
pref("svg.context-properties.content.enabled", true);
pref("browser.tabs.inTitlebar", 1);
pref("browser.compactmode.show", true);
pref("browser.tabs.hoverPreview.enabled", true);
pref("browser.tabs.hoverPreview.showThumbnails", true);

// ── Fluid scrolling ──────────────────────────────────────────────────────
// Spring-physics wheel scrolling with momentum, plus elastic overscroll.
pref("general.smoothScroll", true);
pref("general.smoothScroll.msdPhysics.enabled", true);
pref("general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS", 12);
pref("general.smoothScroll.msdPhysics.motionBeginSpringConstant", 600);
pref("general.smoothScroll.msdPhysics.regularSpringConstant", 650);
pref("general.smoothScroll.msdPhysics.slowdownMinDeltaMS", 25);
pref("general.smoothScroll.msdPhysics.slowdownMinDeltaRatio", "2");
pref("general.smoothScroll.msdPhysics.slowdownSpringConstant", 250);
pref("general.smoothScroll.currentVelocityWeighting", "1");
pref("general.smoothScroll.stopDecelerationWeighting", "1");
pref("apz.overscroll.enabled", true);
pref("apz.gtk.kinetic_scroll.enabled", true);

// ── Rendering ────────────────────────────────────────────────────────────
pref("gfx.webrender.all", true);
pref("gfx.webrender.precache-shaders", true);
pref("gfx.canvas.accelerated", true);
pref("gfx.canvas.accelerated.cache-items", 4096);
pref("gfx.canvas.accelerated.cache-size", 512);
pref("gfx.content.skia-font-cache-size", 20);
pref("image.mem.decode_bytes_at_a_time", 32768);

// ── Network ──────────────────────────────────────────────────────────────
pref("network.http.max-connections", 1800);
pref("network.http.max-persistent-connections-per-server", 10);
pref("network.http.max-urgent-start-excessive-connections-per-host", 5);
pref("network.http.pacing.requests.enabled", false);
pref("network.dnsCacheEntries", 10000);
pref("network.dnsCacheExpiration", 3600);
pref("network.ssl_tokens_cache_capacity", 10240);
pref("network.dns.disablePrefetchFromHTTPS", false);

// ── Memory & disk ────────────────────────────────────────────────────────
pref("browser.tabs.unloadOnLowMemory", true);
pref("browser.sessionstore.interval", 60000);

// ── Quiet start ──────────────────────────────────────────────────────────
pref("browser.aboutwelcome.enabled", false);
pref("startup.homepage_welcome_url", "");
pref("startup.homepage_override_url", "");
pref("browser.shell.checkDefaultBrowser", false);
pref("browser.aboutConfig.showWarning", false);
pref("browser.startup.page", 3); // restore the previous session
pref("browser.aboutwelcome.experimentsGate.enabled", false); // no first-run splash

// ── Derp features (also in Settings → General → Derp) ────────────────────
pref("derp.memorySaver.enabled", true); // unload tabs unused for…
pref("derp.memorySaver.minutes", 30);
pref("derp.duck.enabled", false); // Duck mode (Settings → Derp → Just for fun)
pref("derp.fun.snail", false); // Snail mode: a snail on the loading bar of slow pages
pref("derp.fun.peekaboo", false); // Peekaboo: your dork peeks up now and then
pref("derp.fun.party", false); // Party mode: confetti when you bookmark a page
pref("derp.fun.sleepy", false); // Sleepy tabs: unloaded tabs snore
pref("browser.taskbarTabs.enabled", true); // web apps: install sites as apps
pref("image.jxl.enabled", true); // JPEG XL images

// AI enhancements start blocked (Settings → AI controls to unblock); on-device
// translation stays available.
pref("browser.ai.control.default", "blocked");
pref("browser.ai.control.translations", "available");
pref("extensions.ml.enabled", false);

// ── Derp stays Derp ──────────────────────────────────────────────────────
// No remote rollouts: they can swap in Mozilla's newer (Firefox-branded,
// signed) new tab page or onboarding that Derp can't rebrand.
pref("nimbus.rollouts.enabled", false);

// ── No Mozilla account or online services ────────────────────────────────
// policies.json turns off the account (sign-in, Sync, Send Tab), Mozilla's
// VPN, feedback/"report broken site", Firefox Labs and online suggestions.
pref("signon.firefoxRelay.feature", "disabled"); // Relay email masks
pref("signon.management.page.breach-alerts.enabled", false); // Monitor breach alerts
pref("browser.contentblocking.report.monitor.enabled", false);
pref("browser.contentblocking.report.vpn.enabled", false);
pref("browser.contentblocking.report.show_mobile_app", false);
pref("browser.promo.pin.enabled", false);
pref("browser.vpn_promo.enabled", false);
pref("browser.preferences.moreFromMozilla", false);
pref("browser.uitour.enabled", false); // mozilla.org pages can't drive the UI
pref("ui.new-webcompat-reporter.enabled", false);
// Crash reports aren't sent to Mozilla (Derp is a modified build).
pref("breakpad.reportURL", "");
pref("browser.tabs.crashReporting.sendReport", false);
pref("browser.crashReports.unsubmittedCheck.enabled", false);
pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);

// ── Clean new tab & address bar ──────────────────────────────────────────
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.default.sites", "");
pref("browser.newtabpage.activity-stream.showWeather", false); // a plain new tab, no weather card
pref("browser.toolbars.bookmarks.visibility", "never"); // minimal: no bookmarks bar (Ctrl+Shift+B shows it)
pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
pref("browser.urlbar.trending.featureGate", false);
pref("extensions.getAddons.showPane", false);
pref("extensions.htmlaboutaddons.recommendations.enabled", false);
pref("browser.discovery.enabled", false);
