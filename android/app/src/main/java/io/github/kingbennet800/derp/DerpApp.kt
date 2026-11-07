package io.github.kingbennet800.derp

import android.app.Application
import android.util.Log
import org.mozilla.geckoview.ContentBlocking
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.WebExtension

class DerpApp : Application() {

    /** The engine: Mozilla's GeckoView, with strict tracking protection and
     * cookie banners rejected for you. No telemetry: Derp never sets it up. */
    val runtime: GeckoRuntime by lazy {
        val blocking = ContentBlocking.Settings.Builder()
            .antiTracking(ContentBlocking.AntiTracking.STRICT)
            .enhancedTrackingProtectionLevel(ContentBlocking.EtpLevel.STRICT)
            .cookieBehavior(ContentBlocking.CookieBehavior.ACCEPT_FIRST_PARTY_AND_ISOLATE_OTHERS)
            .cookieBannerHandlingMode(ContentBlocking.CookieBannerMode.COOKIE_BANNER_MODE_REJECT)
            .safeBrowsing(ContentBlocking.SafeBrowsing.DEFAULT)
            .build()
        GeckoRuntime.create(
            this,
            GeckoRuntimeSettings.Builder()
                .contentBlocking(blocking)
                .consoleOutput(false)
                .aboutConfigEnabled(true)
                .build(),
        )
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
