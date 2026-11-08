package io.github.kingbennet800.derp

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import org.mozilla.geckoview.Autocomplete
import org.mozilla.geckoview.GeckoResult
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Saved passwords. The engine asks here for a site's logins to fill in, and
 * hands over new ones once you say "Save". Each password is encrypted with a
 * key that never leaves Android's keystore; the rest (site, username) isn't
 * secret. Kept in the Library's database, on this device only. */
class Logins(private val app: DerpApp) : Autocomplete.StorageDelegate {
    private val db get() = app.library.writableDatabase
    private val prefs = app.getSharedPreferences("browser", Context.MODE_PRIVATE)

    /** Whether Derp offers to save a password when you sign in somewhere. */
    var offerToSave: Boolean
        get() = prefs.getBoolean("savePasswords", true)
        set(value) = prefs.edit().putBoolean("savePasswords", value).apply()

    // ── For the engine ─────────────────────────────────────────────────────

    override fun onLoginFetch(domain: String): GeckoResult<Array<Autocomplete.LoginEntry>>? {
        val found = rows().filter { matches(it.origin, domain) }.mapNotNull { it.entry() }
        Log.d("Derp", "Passwords for a site: ${found.size}")
        return GeckoResult.fromValue(found.toTypedArray())
    }

    override fun onLoginSave(login: Autocomplete.LoginEntry) {
        save(login.guid, login.origin, login.formActionOrigin, login.httpRealm, login.username, login.password)
        app.pairing.changed()
    }

    override fun onLoginUsed(login: Autocomplete.LoginEntry, usedFields: Int) {
        val guid = login.guid ?: return
        db.update("logins", ContentValues().apply { put("used", System.currentTimeMillis()) }, "guid = ?", arrayOf(guid))
    }

    // ── For the Passwords page ─────────────────────────────────────────────

    /** Sites and usernames (not passwords), optionally only those matching [query]. */
    fun list(query: String = ""): JSONArray {
        val q = query.trim().lowercase()
        val items = JSONArray()
        rows()
            .filter { q.isEmpty() || it.origin.lowercase().contains(q) || it.username.lowercase().contains(q) }
            .sortedWith(compareBy({ host(it.origin) }, { it.username }))
            .forEach { items.put(JSONObject().put("guid", it.guid).put("origin", it.origin).put("username", it.username)) }
        return items
    }

    fun password(guid: String): String? = rows("guid = ?", arrayOf(guid)).firstOrNull()?.let { Vault.open(it.sealed) }

    fun remove(guid: String) {
        db.delete("logins", "guid = ?", arrayOf(guid))
    }

    /** Adds the logins you don't have yet, and updates changed passwords. */
    fun import(logins: List<Imports.Login>): Pair<Int, Int> {
        var added = 0
        var updated = 0
        for (login in logins) {
            val existing = rows("origin = ? AND username = ?", arrayOf(login.origin, login.username)).firstOrNull()
            when {
                existing == null -> added++
                runCatching { Vault.open(existing.sealed) }.getOrNull() != login.password -> updated++
                else -> continue
            }
            save(existing?.guid, login.origin, null, null, login.username, login.password)
        }
        return added to updated
    }

    fun count(): Long = app.library.count("logins")

    // ── For syncing with your other devices ────────────────────────────────

    class Synced(val origin: String, val realm: String, val form: String, val username: String, val password: String)

    /** Every saved password, decrypted (those that can be). */
    fun all(): List<Synced> = rows().mapNotNull { row ->
        runCatching { Synced(row.origin, row.realm.orEmpty(), row.formAction.orEmpty(), row.username, Vault.open(row.sealed)) }.getOrNull()
    }

    /** Saves a password from another device (new, or a changed one). */
    fun put(login: Synced) {
        val existing = rows("origin = ? AND username = ?", arrayOf(login.origin, login.username))
            .firstOrNull { it.realm.orEmpty() == login.realm }
        save(existing?.guid, login.origin, login.form.ifEmpty { null }, login.realm.ifEmpty { null }, login.username, login.password)
    }

    /** Removes a password another device deleted. */
    fun delete(origin: String, realm: String, username: String) {
        rows("origin = ? AND username = ?", arrayOf(origin, username))
            .filter { it.realm.orEmpty() == realm }
            .forEach { remove(it.guid) }
    }

    // ──────────────────────────────────────────────────────────────────────

    private class Row(
        val guid: String,
        val origin: String,
        val formAction: String?,
        val realm: String?,
        val username: String,
        val sealed: String,
    ) {
        /** For the engine; null if the password can't be decrypted (a lost key). */
        fun entry(): Autocomplete.LoginEntry? = runCatching {
            Autocomplete.LoginEntry.Builder()
                .guid(guid)
                .origin(origin)
                .formActionOrigin(formAction)
                .httpRealm(realm)
                .username(username)
                .password(Vault.open(sealed))
                .build()
        }.getOrNull()
    }

    private fun rows(where: String? = null, args: Array<String>? = null): List<Row> {
        val rows = mutableListOf<Row>()
        app.library.readableDatabase.query(
            "logins", arrayOf("guid", "origin", "form_action", "realm", "username", "password"),
            where, args, null, null, null,
        ).use { c ->
            while (c.moveToNext()) {
                rows += Row(c.getString(0), c.getString(1), c.getString(2), c.getString(3), c.getString(4), c.getString(5))
            }
        }
        return rows
    }

    /** Updates the login with [guid] (or this site and username), or adds it. */
    private fun save(guid: String?, origin: String, formAction: String?, realm: String?, username: String, password: String) {
        val now = System.currentTimeMillis()
        val target = guid?.takeIf { rows("guid = ?", arrayOf(it)).isNotEmpty() }
            ?: rows("origin = ? AND username = ?", arrayOf(origin, username)).firstOrNull()?.guid
        val values = ContentValues().apply {
            put("origin", origin)
            put("form_action", formAction)
            put("realm", realm)
            put("username", username)
            put("password", Vault.seal(password))
            put("used", now)
        }
        if (target != null) {
            db.update("logins", values, "guid = ?", arrayOf(target))
        } else {
            values.put("guid", "{${UUID.randomUUID()}}")
            values.put("created", now)
            db.insert("logins", null, values)
        }
        Log.i("Derp", "Passwords: ${count()} saved")
    }

    companion object {
        fun host(origin: String): String = Uri.parse(origin).host ?: origin

        /** Whether a login saved for [origin] belongs on [domain] (or its subdomains). */
        fun matches(origin: String, domain: String): Boolean {
            val host = host(origin).lowercase()
            val d = domain.lowercase().removePrefix("www.")
            val h = host.removePrefix("www.")
            return h == d || h.endsWith(".$d") || d.endsWith(".$h")
        }
    }
}

/** Encrypts passwords with an AES key kept in Android's keystore. */
private object Vault {
    private const val ALIAS = "derp-passwords"
    private const val IV = 12

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

    fun seal(text: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return Base64.encodeToString(cipher.iv + cipher.doFinal(text.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }

    fun open(sealed: String): String {
        val bytes = Base64.decode(sealed, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, IV))
        return String(cipher.doFinal(bytes, IV, bytes.size - IV), Charsets.UTF_8)
    }
}
