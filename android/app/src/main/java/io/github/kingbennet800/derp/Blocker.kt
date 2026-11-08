package io.github.kingbennet800.derp

import android.content.Context
import android.util.Log
import org.mozilla.geckoview.AllowOrDeny
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.WebExtension
import org.mozilla.geckoview.WebExtensionController

/** The ad blocker: uBlock Origin, built in like on desktop Derp. The first
 * time Derp starts it installs uBlock Origin from addons.mozilla.org (Mozilla
 * signs it, and the engine checks), checks for a newer one once a day, and
 * the menu turns it on and off. It blocks in private tabs too. Derp only says
 * yes to uBlock Origin's permissions; no other extension gets installed. */
class Blocker(private val app: DerpApp) : WebExtensionController.PromptDelegate {
    private val prefs = app.getSharedPreferences("browser", Context.MODE_PRIVATE)
    private val controller get() = app.runtime.webExtensionController
    private var installing = false

    /** uBlock Origin, once it's installed. */
    var extension: WebExtension? = null
        private set

    val on get() = extension?.metaData?.enabled == true

    /** Called when Derp starts: finds uBlock Origin, or installs it. */
    fun start() {
        controller.promptDelegate = this
        controller.list().accept({ list ->
            val found = list?.firstOrNull { it.id == ID }
            if (found != null) {
                extension = found
                Log.i("Derp", "Ad blocker ready: uBlock Origin ${found.metaData.version}")
                update(found)
            } else {
                install()
            }
        }, { error -> Log.w("Derp", "Ad blocker: couldn't list extensions", error) })
    }

    private fun install() {
        if (installing) return
        installing = true
        controller.install(XPI, WebExtensionController.INSTALLATION_METHOD_ONBOARDING).accept({ installed ->
            installing = false
            extension = installed
            prefs.edit().putLong("blockerChecked", System.currentTimeMillis()).apply()
            Log.i("Derp", "Ad blocker ready: uBlock Origin ${installed?.metaData?.version}")
        }, { error ->
            // No connection, say: try again next time Derp starts.
            installing = false
            Log.w("Derp", "Ad blocker: uBlock Origin didn't install", error)
        })
    }

    /** A newer uBlock Origin, at most once a day. */
    private fun update(current: WebExtension) {
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("blockerChecked", 0) < DAY) return
        prefs.edit().putLong("blockerChecked", now).apply()
        controller.update(current).accept({ updated ->
            if (updated != null) {
                extension = updated
                Log.i("Derp", "Ad blocker updated: uBlock Origin ${updated.metaData.version}")
            }
        }, { error -> Log.w("Derp", "Ad blocker: update check failed", error) })
    }

    fun set(enabled: Boolean, done: () -> Unit) {
        val current = extension ?: return
        val result = if (enabled) {
            controller.enable(current, WebExtensionController.EnableSource.USER)
        } else {
            controller.disable(current, WebExtensionController.EnableSource.USER)
        }
        result.accept({ changed ->
            if (changed != null) extension = changed
            done()
        }, { error -> Log.w("Derp", "Ad blocker: couldn't switch", error) })
    }

    /** uBlock Origin's own settings page (its dashboard). */
    val settingsUrl get() = extension?.metaData?.optionsPageUrl

    override fun onInstallPromptRequest(
        extension: WebExtension,
        permissions: Array<String>,
        origins: Array<String>,
        dataCollectionPermissions: Array<String>,
    ): GeckoResult<WebExtension.PermissionPromptResponse> {
        val ours = extension.id == ID
        return GeckoResult.fromValue(WebExtension.PermissionPromptResponse(ours, ours, false))
    }

    override fun onUpdatePrompt(
        extension: WebExtension,
        newPermissions: Array<String>,
        newOrigins: Array<String>,
        newDataCollectionPermissions: Array<String>,
    ): GeckoResult<AllowOrDeny> = GeckoResult.fromValue(if (extension.id == ID) AllowOrDeny.ALLOW else AllowOrDeny.DENY)

    override fun onOptionalPrompt(
        extension: WebExtension,
        permissions: Array<String>,
        origins: Array<String>,
        dataCollectionPermissions: Array<String>,
    ): GeckoResult<AllowOrDeny> = GeckoResult.fromValue(if (extension.id == ID) AllowOrDeny.ALLOW else AllowOrDeny.DENY)

    companion object {
        const val ID = "uBlock0@raymondhill.net"
        private const val XPI = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
        private const val DAY = 24 * 60 * 60 * 1000L
    }
}
