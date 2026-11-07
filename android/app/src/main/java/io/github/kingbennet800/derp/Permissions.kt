package io.github.kingbennet800.derp

import android.app.AlertDialog
import android.net.Uri
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSession.PermissionDelegate
import org.mozilla.geckoview.GeckoSession.PermissionDelegate.ContentPermission

/** Sites ask before using your location, camera or microphone; Android asks
 * for its own permission only then. Sound doesn't autoplay; silent video can. */
class Permissions(private val browser: Browser) : PermissionDelegate {

    override fun onAndroidPermissionsRequest(
        session: GeckoSession,
        permissions: Array<out String>?,
        callback: PermissionDelegate.Callback,
    ) {
        val activity = browser.ui ?: return callback.reject()
        activity.requestAndroidPermissions(permissions?.toList().orEmpty(), callback)
    }

    override fun onContentPermissionRequest(session: GeckoSession, perm: ContentPermission): GeckoResult<Int> {
        val allow = GeckoResult.fromValue(ContentPermission.VALUE_ALLOW)
        val deny = GeckoResult.fromValue(ContentPermission.VALUE_DENY)
        val what = when (perm.permission) {
            PermissionDelegate.PERMISSION_AUTOPLAY_INAUDIBLE -> return allow
            PermissionDelegate.PERMISSION_AUTOPLAY_AUDIBLE -> return deny
            PermissionDelegate.PERMISSION_MEDIA_KEY_SYSTEM_ACCESS -> "play protected video and music"
            PermissionDelegate.PERMISSION_GEOLOCATION -> "know your location"
            PermissionDelegate.PERMISSION_PERSISTENT_STORAGE -> "keep its data on this device"
            PermissionDelegate.PERMISSION_STORAGE_ACCESS -> "use its cookies here"
            else -> return deny
        }
        return ask(siteName(perm.uri), what)?.let { result ->
            result.map { yes -> if (yes == true) ContentPermission.VALUE_ALLOW else ContentPermission.VALUE_DENY }
        } ?: deny
    }

    override fun onMediaPermissionRequest(
        session: GeckoSession,
        uri: String,
        video: Array<out PermissionDelegate.MediaSource>?,
        audio: Array<out PermissionDelegate.MediaSource>?,
        callback: PermissionDelegate.MediaCallback,
    ) {
        val what = when {
            video != null && audio != null -> "use your camera and microphone"
            video != null -> "use your camera"
            audio != null -> "use your microphone"
            else -> return callback.reject()
        }
        val result = ask(siteName(uri), what) ?: return callback.reject()
        result.accept({ yes ->
            if (yes == true) callback.grant(video?.firstOrNull(), audio?.firstOrNull()) else callback.reject()
        }, { callback.reject() })
    }

    private fun ask(site: String, what: String): GeckoResult<Boolean>? {
        val activity = browser.ui ?: return null
        val result = GeckoResult<Boolean>()
        var answered = false
        fun answer(yes: Boolean) {
            if (!answered) {
                answered = true
                result.complete(yes)
            }
        }
        AlertDialog.Builder(activity)
            .setTitle("Allow $site to $what?")
            .setPositiveButton("Allow") { _, _ -> answer(true) }
            .setNegativeButton("Don't allow") { _, _ -> answer(false) }
            .setOnDismissListener { answer(false) }
            .show()
        return result
    }

    private fun siteName(uri: String?) =
        runCatching { Uri.parse(uri).host?.removePrefix("www.") }.getOrNull() ?: "this site"
}
