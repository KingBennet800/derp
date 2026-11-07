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
        )
    }
    val runtime: GeckoRuntime by engine

    /** Pages follow light and dark mode. Gecko is told each time the system
     * switches, since on its own it doesn't always notice. */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (engine.isInitialized()) runtime.settings.setPreferredColorScheme(colorScheme(newConfig))
    }

    private fun colorScheme(config: Configuration) =
        if ((config.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES) {
            GeckoRuntimeSettings.COLOR_SCHEME_DARK
        } else {
            GeckoRuntimeSettings.COLOR_SCHEME_LIGHT
        }

    val dork by lazy { Dork(this) }
    val browser by lazy { Browser(this) }

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
