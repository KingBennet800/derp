package io.github.kingbennet800.derp

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** Derp updates itself from its GitHub releases, like desktop Derp: whenever
 * you open it (at most once an hour) it reads the latest release's SHA256SUMS
 * (which names the version), and if there's a newer Derp it offers it. "Later"
 * puts that version off for a day. The APK is checked
 * against SHA256SUMS before Android's installer gets it, and Android only
 * accepts it if it's signed with the same key as this Derp. */
object Updater {
    private const val RELEASES = "https://github.com/KingBennet800/derp/releases"
    private const val HOUR = 60 * 60 * 1000L
    private const val DAY = 24 * HOUR
    const val INSTALL_STATUS = "io.github.kingbennet800.derp.INSTALL_STATUS"

    /** This device's APK flavor, as named in the releases. */
    fun abi(): String = when (Build.SUPPORTED_ABIS.firstOrNull()) {
        "armeabi-v7a" -> "arm"
        "x86_64" -> "x86_64"
        else -> "arm64"
    }

    fun check(activity: MainActivity, manual: Boolean) {
        val prefs = activity.getSharedPreferences("browser", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (!manual && now - prefs.getLong("updateChecked", 0) < HOUR) return
        if (manual) Toast.makeText(activity, "Checking for updates…", Toast.LENGTH_SHORT).show()
        Thread {
            val found = runCatching {
                val sums = fetch("$RELEASES/latest/download/SHA256SUMS").toString(Charsets.UTF_8)
                val version = Regex("""derp-(\d+(?:\.\d+)*)\.tar\.gz""").find(sums)?.groupValues?.get(1)
                    ?: error("no version in SHA256SUMS")
                val apk = "derp-android-${abi()}.apk"
                val hash = sums.lines().firstOrNull { it.trimEnd().endsWith(" $apk") }?.substringBefore(' ')
                Triple(version, apk, hash)
            }
            activity.runOnUiThread {
                prefs.edit().putLong("updateChecked", now).apply()
                found.onSuccess { (version, apk, hash) ->
                    when {
                        newer(version, BuildConfig.VERSION_NAME) && hash != null -> {
                            // You said "Later" to this version less than a day ago: wait (unless you asked).
                            val putOff = prefs.getString("updateLater", null) == version &&
                                now - prefs.getLong("updateLaterAt", 0) < DAY
                            if (manual || !putOff) {
                                activity.offerUpdate(
                                    version,
                                    later = { prefs.edit().putString("updateLater", version).putLong("updateLaterAt", now).apply() },
                                ) { download(activity, version, "$RELEASES/download/v$version/$apk", hash) }
                            }
                        }
                        manual -> Toast.makeText(activity, "Derp is up to date (${BuildConfig.VERSION_NAME})", Toast.LENGTH_SHORT).show()
                    }
                }.onFailure {
                    if (manual) Toast.makeText(activity, "Couldn't reach GitHub to check for updates", Toast.LENGTH_SHORT).show()
                }
            }
        }.start()
    }

    private fun download(activity: MainActivity, version: String, url: String, hash: String) {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            Toast.makeText(activity, "Let Derp install updates, then try again", Toast.LENGTH_LONG).show()
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")),
            )
            return
        }
        Toast.makeText(activity, "Downloading Derp $version…", Toast.LENGTH_SHORT).show()
        Thread {
            val result = runCatching {
                val file = File(activity.cacheDir, "derp-update.apk")
                file.writeBytes(fetch(url))
                val actual = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
                check(actual.equals(hash, ignoreCase = true)) { "checksum mismatch" }
                install(activity, file)
            }
            activity.runOnUiThread {
                result.onFailure {
                    Toast.makeText(activity, "The update didn't download correctly (${it.message})", Toast.LENGTH_LONG).show()
                }
            }
        }.start()
    }

    /** Hands the APK to Android's installer, which asks you to confirm. */
    private fun install(context: Context, apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            session.openWrite("derp.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val status = Intent(context, MainActivity::class.java).setAction(INSTALL_STATUS)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            session.commit(PendingIntent.getActivity(context, 0, status, flags).intentSender)
        }
        apk.delete()
    }

    private fun fetch(url: String): ByteArray {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 60_000
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("User-Agent", "Derp/${BuildConfig.VERSION_NAME}")
        try {
            check(connection.responseCode == 200) { "HTTP ${connection.responseCode}" }
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    fun newer(a: String, b: String): Boolean {
        val x = a.split(".").map { it.toIntOrNull() ?: 0 }
        val y = b.split(".").map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(x.size, y.size)) {
            val p = x.getOrElse(i) { 0 }
            val q = y.getOrElse(i) { 0 }
            if (p != q) return p > q
        }
        return false
    }
}
