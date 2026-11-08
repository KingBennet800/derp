package io.github.kingbennet800.derp

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.Executors
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject

/** Your devices: Derp on this phone paired with Derp on your computer, sharing
 * bookmarks, passwords and open tabs, end-to-end encrypted, with no account.
 * Desktop Derp shows a QR code; its link, opened here, pairs. The protocol is
 * desktop Derp's (src/features/DerpPair.sys.mjs; tests/pairing.py has it in
 * Python): keys come from the shared secret, each device keeps one encrypted
 * snapshot on a relay that can't read them, and the newest change to anything
 * wins. The ledger keeps a keyed hash of each password, never the password;
 * the secret itself is kept encrypted with a key in Android's keystore. */
class Pairing(private val app: DerpApp) {
    private val file = File(app.filesDir, "devices.json")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val tick = Runnable { syncSoon(0) }
    private var state: JSONObject? = null
    private var keys: Keys? = null
    private var loaded = false

    /** The phone's view of things for the Your devices page, as of the last sync. */
    @Volatile
    var summary: JSONObject = JSONObject().put("paired", false)
        private set

    val paired get() = summary.optBoolean("paired")

    fun start() = worker.execute {
        load()
        if (state != null) main.postDelayed(tick, 10_000)
    }

    // ── When to sync ───────────────────────────────────────────────────────

    /** Derp came to the screen: sync soon, then every ten minutes while it's there. */
    fun resumed() {
        if (paired && System.currentTimeMillis() - summary.optLong("syncedAt") > 60_000) syncSoon(2000)
    }

    /** Derp left the screen: send your open tabs, and stop syncing on a timer. */
    fun paused() {
        main.removeCallbacks(tick)
        if (paired) go(again = false)
    }

    /** Something you keep changed here (a bookmark, a password). */
    fun changed() {
        if (paired) syncSoon(5000)
    }

    fun syncSoon(delay: Long) {
        main.removeCallbacks(tick)
        if (delay == 0L) go() else main.postDelayed(tick, delay)
    }

    private fun go(again: Boolean = true, done: (() -> Unit)? = null) {
        val tabs = openTabs()
        worker.execute {
            sync(tabs)
            main.post { done?.invoke() }
        }
        if (again) main.postDelayed(tick, EVERY)
    }

    fun syncNow(done: () -> Unit) {
        main.removeCallbacks(tick)
        go(done = done)
    }

    /** Your open tabs (not private ones), most recently seen first; read on the main thread. */
    private fun openTabs(): JSONArray {
        val list = JSONArray()
        app.browser.tabs.filter { !it.private && isWeb(it.url) }
            .sortedByDescending { if (it === app.browser.current) Long.MAX_VALUE else it.seen }
            .take(TABS)
            .forEach { list.put(JSONObject().put("url", it.url).put("title", it.title.take(300))) }
        return list
    }

    // ── Pairing and leaving ────────────────────────────────────────────────

    /** Joins the pair in [link] (leaving any other first); [done] gets what to tell you. */
    fun join(link: String, done: (String) -> Unit) {
        val (secret, relay) = parse(link) ?: return done("That pairing code didn't work. Make a new one on your computer.")
        val tabs = openTabs()
        worker.execute {
            if (state != null) leaveNow()
            state = JSONObject()
                .put("secret", Locker.seal(secret))
                .put("relay", relay)
                .put("device", hex(ByteArray(16).also { SecureRandom().nextBytes(it) }))
                .put("ledger", JSONObject().put("bookmarks", JSONObject()).put("logins", JSONObject()))
                .put("devices", JSONObject())
            keys = Keys(secret)
            save()
            sync(tabs)
            val names = deviceNames()
            Log.i("Derp", "Your devices: paired" + if (names.isEmpty()) "" else " with $names")
            main.post {
                done(if (names.isEmpty()) "Paired. Your computer shows up here once it syncs." else "Paired with $names")
                main.removeCallbacks(tick)
                main.postDelayed(tick, EVERY)
            }
        }
    }

    /** Stop syncing: this phone leaves the pair. Its bookmarks and passwords stay. */
    fun leave(done: () -> Unit) {
        main.removeCallbacks(tick)
        worker.execute {
            leaveNow()
            Log.i("Derp", "Your devices: left the pair")
            main.post(done)
        }
    }

    private fun leaveNow() {
        val state = state ?: return
        val keys = keys ?: return
        runCatching {
            request(state.getString("relay"), "POST", keys, mapOf("X-Derp-Token" to keys.token, "X-Derp-Device" to state.getString("device"), "X-Derp-Delete" to "1"), ByteArray(0))
        }.onFailure { Log.w("Derp", "Your devices: couldn't leave the relay", it) }
        this.state = null
        this.keys = null
        file.delete()
        summary = JSONObject().put("paired", false)
    }

    // ── Syncing (on the worker thread) ─────────────────────────────────────

    private class Local(val bookmarks: MutableMap<String, String>, val logins: MutableMap<String, Logins.Synced>)

    private fun sync(tabs: JSONArray) {
        load()
        val state = state ?: return
        val keys = keys ?: return
        val local = Local(
            app.library.allBookmarks().filterKeys { isWeb(it) }.toMutableMap(),
            app.logins.all().filter { isWeb(it.origin) }.associateBy { loginKey(it.origin, it.realm, it.username) }.toMutableMap(),
        )
        noteLocal(state, keys, local)
        var changes = 0
        try {
            pull(state, keys)?.let { slots ->
                val seen = JSONObject()
                for (device in slots.keys()) {
                    if (device == state.getString("device") || !HEX32.matches(device)) continue
                    val snapshot = runCatching {
                        JSONObject(unseal(keys, device, Base64.getDecoder().decode(slots.getJSONObject(device).getString("data"))))
                    }.onFailure { Log.w("Derp", "Your devices: a slot didn't decrypt", it) }.getOrNull() ?: continue
                    val theirTabs = JSONArray()
                    snapshot.optJSONArray("tabs")?.let { list ->
                        for (i in 0 until minOf(list.length(), TABS)) {
                            val tab = list.optJSONObject(i) ?: continue
                            if (isWeb(tab.optString("url"))) {
                                theirTabs.put(JSONObject().put("url", tab.optString("url")).put("title", tab.optString("title").take(300)))
                            }
                        }
                    }
                    seen.put(device, JSONObject()
                        .put("name", snapshot.optString("name", "Derp").take(80))
                        .put("kind", snapshot.optString("kind").takeIf { it in setOf("phone", "tablet", "desktop") } ?: "desktop")
                        .put("at", snapshot.optLong("at"))
                        .put("tabs", theirTabs))
                    changes += merge(state, keys, snapshot, local)
                }
                state.put("devices", seen)
            }
            forgetOld(state)
            push(state, keys, local, tabs)
            state.put("syncedAt", System.currentTimeMillis()).put("problem", "")
        } catch (e: Exception) {
            state.put("problem", e.message ?: e.toString())
            Log.w("Derp", "Your devices: sync failed", e)
        }
        save()
        Log.i("Derp", "Your devices: synced ($changes change(s), ${state.getJSONObject("devices").length()} other device(s))")
    }

    /** Your changes since the last sync go in the ledger, as of now. */
    private fun noteLocal(state: JSONObject, keys: Keys, local: Local) {
        val now = System.currentTimeMillis()
        val ledger = state.getJSONObject("ledger")
        val bookmarks = ledger.getJSONObject("bookmarks")
        for ((url, title) in local.bookmarks) {
            val known = bookmarks.optJSONObject(url)
            if (known == null || known.optBoolean("gone") || known.optString("title") != title) {
                bookmarks.put(url, JSONObject().put("title", title).put("at", now).put("gone", false))
            }
        }
        for (url in bookmarks.keys().asSequence().toList()) {
            val known = bookmarks.getJSONObject(url)
            if (!known.optBoolean("gone") && url !in local.bookmarks) {
                bookmarks.put(url, JSONObject().put("title", known.optString("title")).put("at", now).put("gone", true))
            }
        }
        val logins = ledger.getJSONObject("logins")
        for ((key, login) in local.logins) {
            val hash = hash(keys, login.password)
            val known = logins.optJSONObject(key)
            if (known == null || known.optBoolean("gone") || known.optString("hash") != hash) {
                logins.put(key, loginEntry(login.origin, login.realm, login.form, login.username).put("hash", hash).put("at", now).put("gone", false))
            }
        }
        for (key in logins.keys().asSequence().toList()) {
            val known = logins.getJSONObject(key)
            if (!known.optBoolean("gone") && key !in local.logins) {
                logins.put(key, JSONObject(known.toString()).put("hash", "").put("at", now).put("gone", true))
            }
        }
    }

    /** Takes another device's newer changes; returns how many. The ledger only
     * takes a change once it's made here, so a failed one is tried again. */
    private fun merge(state: JSONObject, keys: Keys, snapshot: JSONObject, local: Local): Int {
        var changes = 0
        val ledger = state.getJSONObject("ledger")
        val bookmarks = ledger.getJSONObject("bookmarks")
        snapshot.optJSONObject("bookmarks")?.let { theirs ->
            for (url in theirs.keys()) {
                val entry = theirs.optJSONObject(url) ?: continue
                val at = entry.optLong("at", -1)
                if (!isWeb(url) || at < 0 || (bookmarks.optJSONObject(url)?.optLong("at") ?: -1) >= at) continue
                val title = entry.optString("title").take(1000)
                val gone = entry.optBoolean("gone")
                runCatching {
                    when {
                        gone -> if (local.bookmarks.remove(url) != null) {
                            app.library.unbookmark(url)
                            changes++
                        }
                        url !in local.bookmarks -> {
                            app.library.bookmark(url, title)
                            local.bookmarks[url] = title
                            changes++
                        }
                        local.bookmarks[url] != title -> {
                            app.library.retitle(url, title)
                            local.bookmarks[url] = title
                            changes++
                        }
                    }
                    bookmarks.put(url, JSONObject().put("title", title).put("at", at).put("gone", gone))
                }.onFailure { Log.w("Derp", "Your devices: couldn't apply a bookmark", it) }
            }
        }
        val logins = ledger.getJSONObject("logins")
        snapshot.optJSONObject("logins")?.let { theirs ->
            for (name in theirs.keys()) {
                val entry = theirs.optJSONObject(name) ?: continue
                val at = entry.optLong("at", -1)
                val origin = originOf(entry.optString("origin")) ?: continue
                val username = entry.optString("username")
                if (at < 0 || username.length > MAX_TEXT) continue
                val realm = entry.optString("realm").take(1000)
                val form = entry.optString("form").take(1000)
                val key = loginKey(origin, realm, username)
                if ((logins.optJSONObject(key)?.optLong("at") ?: -1) >= at) continue
                val gone = entry.optBoolean("gone")
                val password = entry.optString("password")
                if (!gone && (password.isEmpty() || password.length > MAX_TEXT)) continue
                runCatching {
                    val mine = local.logins[key]
                    if (gone) {
                        if (mine != null) {
                            app.logins.delete(origin, realm, username)
                            local.logins.remove(key)
                            changes++
                        }
                        logins.put(key, loginEntry(origin, realm, form, username).put("hash", "").put("at", at).put("gone", true))
                    } else {
                        if (mine == null || mine.password != password) {
                            val login = Logins.Synced(origin, realm, form, username, password)
                            app.logins.put(login)
                            local.logins[key] = login
                            changes++
                        }
                        logins.put(key, loginEntry(origin, realm, form, username).put("hash", hash(keys, password)).put("at", at).put("gone", false))
                    }
                }.onFailure { Log.w("Derp", "Your devices: couldn't apply a password", it) }
            }
        }
        return changes
    }

    /** Deletions are remembered for 90 days, so the other devices hear of them. */
    private fun forgetOld(state: JSONObject) {
        val old = System.currentTimeMillis() - FORGET_GONE
        val ledger = state.getJSONObject("ledger")
        for (list in listOf(ledger.getJSONObject("bookmarks"), ledger.getJSONObject("logins"))) {
            for (key in list.keys().asSequence().toList()) {
                val entry = list.getJSONObject(key)
                if (entry.optBoolean("gone") && entry.optLong("at") < old) list.remove(key)
            }
        }
    }

    private fun pull(state: JSONObject, keys: Keys): JSONObject? {
        val etag = state.optString("etag")
        val (status, body, tag) = request(state.getString("relay"), "GET", keys, if (etag.isEmpty()) emptyMap() else mapOf("If-None-Match" to etag), null)
        if (status == 304) return null
        state.put("etag", tag.orEmpty())
        return JSONObject(String(body, Charsets.UTF_8)).optJSONObject("slots") ?: JSONObject()
    }

    /** Uploads this phone's snapshot when it changed (or once a week, so the relay keeps it). */
    private fun push(state: JSONObject, keys: Keys, local: Local, tabs: JSONArray) {
        val ledger = state.getJSONObject("ledger")
        val logins = JSONObject()
        val known = ledger.getJSONObject("logins")
        for (key in known.keys()) {
            val entry = known.getJSONObject(key)
            val out = loginEntry(entry.optString("origin"), entry.optString("realm"), entry.optString("form"), entry.optString("username"))
                .put("at", entry.optLong("at"))
            if (entry.optBoolean("gone")) {
                logins.put(key, out.put("gone", true))
            } else {
                val mine = local.logins[key] ?: continue
                logins.put(key, out.put("password", mine.password).put("gone", false))
            }
        }
        val snapshot = JSONObject()
            .put("v", 1)
            .put("device", state.getString("device"))
            .put("name", "Derp on ${Build.MODEL}")
            .put("kind", if (app.resources.configuration.smallestScreenWidthDp >= 600) "tablet" else "phone")
            .put("tabs", tabs)
            .put("bookmarks", ledger.getJSONObject("bookmarks"))
            .put("logins", logins)
        val body = snapshot.toString()
        val fingerprint = hex(MessageDigest.getInstance("SHA-256").digest(body.toByteArray(Charsets.UTF_8)))
        val now = System.currentTimeMillis()
        if (fingerprint == state.optString("pushed") && now - state.optLong("pushedAt") < 7 * DAY) return
        val sealed = seal(keys, state.getString("device"), snapshot.put("at", now).toString())
        request(state.getString("relay"), "POST", keys, mapOf(
            "X-Derp-Token" to keys.token,
            "X-Derp-Device" to state.getString("device"),
            "Content-Type" to "application/octet-stream",
        ), sealed)
        state.put("pushed", fingerprint).put("pushedAt", now).put("etag", "")
    }

    private fun request(relay: String, method: String, keys: Keys, headers: Map<String, String>, body: ByteArray?): Triple<Int, ByteArray, String?> {
        val connection = URL(relay).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.useCaches = false
            connection.setRequestProperty("X-Derp-Box", keys.box)
            headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            if (body != null) {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
            }
            val status = connection.responseCode
            if (status != 304 && status !in 200..299) {
                val why = runCatching { JSONObject(connection.errorStream.bufferedReader().readText()).optString("error") }.getOrNull()
                throw IllegalStateException("relay $status" + if (why.isNullOrEmpty()) "" else ": $why")
            }
            val bytes = if (status == 200) connection.inputStream.use { it.readBytes() } else ByteArray(0)
            return Triple(status, bytes, connection.getHeaderField("ETag"))
        } finally {
            connection.disconnect()
        }
    }

    // ── Kept on the phone ──────────────────────────────────────────────────

    private fun load() {
        if (loaded) return
        loaded = true
        state = runCatching { JSONObject(file.readText()) }.getOrNull()
        keys = state?.let { runCatching { Keys(Locker.open(it.getString("secret"))) }.getOrNull() }
        if (keys == null) state = null
        publish()
    }

    private fun save() {
        state?.let { file.writeText(it.toString()) }
        publish()
    }

    private fun deviceNames(): String {
        val devices = state?.optJSONObject("devices") ?: return ""
        return devices.keys().asSequence().map { devices.getJSONObject(it).optString("name") }.joinToString(" and ")
    }

    /** What the Your devices page shows. */
    private fun publish() {
        val state = state
        summary = if (state == null) {
            JSONObject().put("paired", false)
        } else {
            val devices = JSONArray()
            val all = state.optJSONObject("devices") ?: JSONObject()
            for (id in all.keys()) devices.put(all.getJSONObject(id))
            JSONObject()
                .put("paired", true)
                .put("devices", devices)
                .put("syncedAt", state.optLong("syncedAt"))
                .put("problem", state.optString("problem"))
        }
    }

    companion object {
        const val RELAY = "https://bennettholland.com/derp-relay.php"
        const val LINK = "https://kingbennet800.github.io/derp/pair/#"
        private const val TABS = 50
        private const val MAX_TEXT = 4096
        private const val DAY = 24 * 60 * 60 * 1000L
        private const val FORGET_GONE = 90 * DAY
        private const val EVERY = 10 * 60 * 1000L
        private val HEX32 = Regex("^[0-9a-f]{32}$")
        private val LOCAL_RELAY = Regex("^http://(localhost|127\\.0\\.0\\.1)(:\\d+)?/")

        fun isWeb(url: String) = url.length <= MAX_TEXT && Regex("^https?://\\S+$", RegexOption.IGNORE_CASE).matches(url)

        private fun originOf(url: String): String? = runCatching {
            val uri = URI(url)
            if (uri.scheme !in setOf("http", "https") || uri.host.isNullOrEmpty()) null else "${uri.scheme}://${uri.rawAuthority}"
        }.getOrNull()

        fun loginKey(origin: String, realm: String, username: String) = "$origin\n$realm\n$username"

        private fun loginEntry(origin: String, realm: String, form: String, username: String) =
            JSONObject().put("origin", origin).put("realm", realm).put("form", form).put("username", username)

        /** The secret and relay in a pairing link, or null if it isn't one. */
        fun parse(link: String): Pair<ByteArray, String>? {
            if (!link.startsWith(LINK)) return null
            val rest = link.removePrefix(LINK)
            val secret = runCatching { Base64.getUrlDecoder().decode(rest.substringBefore('~')) }.getOrNull() ?: return null
            val relay = if ('~' in rest) runCatching { URLDecoder.decode(rest.substringAfter('~'), "UTF-8") }.getOrNull() else RELAY
            if (secret.size != 32 || relay == null) return null
            if (!relay.startsWith("https://") && !LOCAL_RELAY.containsMatchIn(relay)) return null
            return secret to relay
        }

        fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

        /** HKDF-SHA256 with no salt, 32 bytes (one block). */
        fun hkdf(secret: ByteArray, info: String): ByteArray {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(ByteArray(32), "HmacSHA256"))
            val prk = mac.doFinal(secret)
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.update(info.toByteArray(Charsets.UTF_8))
            mac.update(1)
            return mac.doFinal()
        }

        fun seal(keys: Keys, device: String, json: String): ByteArray {
            val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
            val zipped = ByteArrayOutputStream().also { out -> GZIPOutputStream(out).use { it.write(json.toByteArray(Charsets.UTF_8)) } }.toByteArray()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(keys.key, "AES"), GCMParameterSpec(128, nonce))
            cipher.updateAAD("derp pair v1 $device".toByteArray(Charsets.UTF_8))
            return byteArrayOf(1) + nonce + cipher.doFinal(zipped)
        }

        fun unseal(keys: Keys, device: String, blob: ByteArray): String {
            require(blob.size > 13 && blob[0] == 1.toByte()) { "unknown slot version" }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(keys.key, "AES"), GCMParameterSpec(128, blob, 1, 12))
            cipher.updateAAD("derp pair v1 $device".toByteArray(Charsets.UTF_8))
            val zipped = cipher.doFinal(blob, 13, blob.size - 13)
            return GZIPInputStream(ByteArrayInputStream(zipped)).use { String(it.readBytes(), Charsets.UTF_8) }
        }

        /** A keyed hash of a password, to notice changes without keeping it. */
        fun hash(keys: Keys, password: String): String {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(keys.hash, "HmacSHA256"))
            return hex(mac.doFinal(password.toByteArray(Charsets.UTF_8))).take(32)
        }
    }

    /** The keys a pair's secret gives. */
    class Keys(secret: ByteArray) {
        val box = hex(hkdf(secret, "derp pair box"))
        val token = hex(hkdf(secret, "derp pair write"))
        val key = hkdf(secret, "derp pair key")
        val hash = hkdf(secret, "derp pair hash")
    }
}

/** Keeps the pair's secret encrypted with an AES key in Android's keystore. */
private object Locker {
    private const val ALIAS = "derp-devices"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    fun seal(secret: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(secret))
    }

    fun open(sealed: String): ByteArray {
        val bytes = Base64.getDecoder().decode(sealed)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, 12))
        return cipher.doFinal(bytes, 12, bytes.size - 12)
    }
}
