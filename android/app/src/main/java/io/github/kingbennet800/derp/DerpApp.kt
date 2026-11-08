package io.github.kingbennet800.derp

import android.app.Application
import android.content.res.Configuration
import android.util.Log
import org.mozilla.geckoview.ContentBlocking
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.WebExtension

class DerpApp : Application() {

    /** The engine: Mozilla's GeckoView, with strict tracking protection,
     * tracking parameters stripped from links, and tracker cookies purged.
     * No telemetry: Derp never sets it up. */
    private val engine = lazy {
        val blocking = ContentBlocking.Settings.Builder()
            .antiTracking(ContentBlocking.AntiTracking.STRICT)
            .enhancedTrackingProtectionLevel(ContentBlocking.EtpLevel.STRICT)
            .strictSocialTrackingProtection(true)
            .cookieBehavior(ContentBlocking.CookieBehavior.ACCEPT_FIRST_PARTY_AND_ISOLATE_OTHERS)
            .cookiePurging(true)
            .queryParameterStrippingEnabled(true)
            .queryParameterStrippingPrivateBrowsingEnabled(true)
            .safeBrowsing(ContentBlocking.SafeBrowsing.DEFAULT)
            .build()
        GeckoRuntime.create(
            this,
            GeckoRuntimeSettings.Builder()
                .contentBlocking(blocking)
                .consoleOutput(false)
                .aboutConfigEnabled(true)
                .preferredColorScheme(colorScheme(resources.configuration))
                .build(),
        ).also {
            // Saved passwords: the engine asks Logins for them, and hands new ones over.
            it.setAutocompleteStorageDelegate(logins)
        }
    }
    val runtime: GeckoRuntime by engine

    /** Pages follow light and dark mode. Gecko is told each time the system
     * switches, since on its own it doesn't always notice. */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (engine.isInitialized()) runtime.settings.setPreferredColorScheme(colorScheme(newConfig))
    }

    /** Whether Derp is in dark mode. */
    val dark get() = night(resources.configuration)

    private fun night(config: Configuration) =
        (config.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    private fun colorScheme(config: Configuration) =
        if (night(config)) {
            GeckoRuntimeSettings.COLOR_SCHEME_DARK
        } else {
            GeckoRuntimeSettings.COLOR_SCHEME_LIGHT
        }

    val dork by lazy { Dork(this) }
    val library by lazy { Library(this) }
    val logins by lazy { Logins(this) }
    val browser by lazy { Browser(this) }
    val blocker by lazy { Blocker(this) }
    val pairing by lazy { Pairing(this) }

    /** Android is short of memory: Memory Saver puts every tab but the one
     * you're on to sleep (a Derp in the background is the first to go). */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        @Suppress("DEPRECATION")
        val short = level in TRIM_MEMORY_RUNNING_LOW until TRIM_MEMORY_UI_HIDDEN || level >= TRIM_MEMORY_BACKGROUND
        if (short) browser.sleepIdleTabs(all = true)
    }

    private var pages: WebExtension? = null
    private val waiting = mutableListOf<(WebExtension) -> Unit>()

    /** Derp's own pages (new tab, your dork) are a built-in WebExtension. */
    fun withPages(block: (WebExtension) -> Unit) {
        pages?.let {
            block(it)
            return
        }
        waiting += block
        if (waiting.size > 1) return
        runtime.webExtensionController
            .ensureBuiltIn("resource://android/assets/derp/", "derp@kingbennet800.github.io")
            .accept({ extension ->
                if (extension == null) return@accept
                pages = extension
                val queued = waiting.toList()
                waiting.clear()
                queued.forEach { it(extension) }
            }, { error ->
                Log.e("Derp", "Derp's pages didn't load", error)
            })
    }
}
