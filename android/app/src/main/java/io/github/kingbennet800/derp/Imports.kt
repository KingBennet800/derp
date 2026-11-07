package io.github.kingbennet800.derp

import java.net.URI

/** Reading other browsers' exports, for Import data: a bookmarks .html file
 * (the format every browser exports bookmarks in) and a passwords .csv file
 * (Chrome, Edge, Firefox, Safari and Derp on computers all write one). Plain
 * Kotlin, so the unit tests run without a device. */
object Imports {
    data class Bookmark(val url: String, val title: String)
    data class Login(val origin: String, val username: String, val password: String)

    private val anchor = Regex(
        """<a\s[^>]*?href\s*=\s*"([^"]*)"[^>]*>(.*?)</a\s*>""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
    )
    private val tags = Regex("<[^>]*>")

    /** Every web link in a bookmarks file, folders flattened, each address once. */
    fun bookmarks(html: String): List<Bookmark> = anchor.findAll(html)
        .mapNotNull { match ->
            val url = unescape(match.groupValues[1]).trim()
            if (!isWeb(url)) return@mapNotNull null
            val title = unescape(match.groupValues[2].replace(tags, "")).trim()
            Bookmark(url, title.ifBlank { url })
        }
        .distinctBy { it.url }
        .toList()

    /** The saved logins in a passwords file, for websites (not apps). */
    fun logins(text: String): List<Login> {
        val rows = csv(text)
        if (rows.isEmpty()) return emptyList()
        val head = rows.first().map { it.trim().lowercase() }
        fun column(vararg names: String) = head.indexOfFirst { it in names }
        val site = column("url", "origin", "website", "login_uri")
        val user = column("username", "login", "login_username", "user")
        val pass = column("password", "login_password")
        if (site < 0 || pass < 0) return emptyList()
        return rows.drop(1).mapNotNull { row ->
            val origin = origin(row.getOrNull(site).orEmpty()) ?: return@mapNotNull null
            val password = row.getOrNull(pass).orEmpty()
            if (password.isEmpty()) return@mapNotNull null
            Login(origin, if (user >= 0) row.getOrNull(user).orEmpty() else "", password)
        }.distinct()
    }

    /** A web address's origin (https://example.com:8443), or null for anything else. */
    fun origin(url: String): String? {
        val uri = runCatching { URI(url.trim()) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()
        if ((scheme != "http" && scheme != "https") || host.isNullOrEmpty()) return null
        return "$scheme://$host" + if (uri.port == -1) "" else ":${uri.port}"
    }

    fun isWeb(url: String) = url.startsWith("https://", ignoreCase = true) || url.startsWith("http://", ignoreCase = true)

    /** RFC 4180 CSV: quoted fields may hold commas, quotes ("") and line breaks. */
    fun csv(text: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var quoted = false
        val s = text.removePrefix("﻿")
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (quoted) {
                if (c == '"') {
                    if (i + 1 < s.length && s[i + 1] == '"') {
                        field.append('"')
                        i++
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                when (c) {
                    '"' -> quoted = true
                    ',' -> {
                        row.add(field.toString())
                        field.setLength(0)
                    }
                    '\r' -> Unit
                    '\n' -> {
                        row.add(field.toString())
                        field.setLength(0)
                        rows.add(row)
                        row = mutableListOf()
                    }
                    else -> field.append(c)
                }
            }
            i++
        }
        if (field.isNotEmpty() || row.isNotEmpty()) {
            row.add(field.toString())
            rows.add(row)
        }
        return rows.filter { cells -> cells.any { it.isNotBlank() } }
    }

    private val entity = Regex("&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);")
    private val named = mapOf("amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ")

    private fun char(code: Int): String? = runCatching { String(Character.toChars(code)) }.getOrNull()

    /** HTML character references (&amp; &#39; &#x2014; …) back to text. */
    fun unescape(text: String): String = entity.replace(text) { match ->
        val name = match.groupValues[1]
        when {
            name.startsWith("#x") || name.startsWith("#X") ->
                name.substring(2).toIntOrNull(16)?.let(::char) ?: match.value
            name.startsWith("#") -> name.substring(1).toIntOrNull()?.let(::char) ?: match.value
            else -> named[name.lowercase()] ?: match.value
        }
    }
}
