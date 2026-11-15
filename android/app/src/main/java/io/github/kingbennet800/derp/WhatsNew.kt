package io.github.kingbennet800.derp

import android.content.Context
import org.json.JSONArray

/** What's new: after an update brings something new, Derp shows what came
 * with it (src/features/whatsnew.json, which desktop Derp shows too), each
 * with where to find it. ⋮ → About Derp → What's new shows it again. A new
 * Derp (still making its dork) needs no telling, and updates with nothing
 * listed (the weekly engine updates) pass quietly. */
object WhatsNew {
    class Item(val icon: String, val title: String, val text: String, val where: String?)
    class Release(val version: String, val title: String, val items: List<Item>)

    /** Whether version [a] (like "2.1.0") is newer than [b]. */
    fun newer(a: String, b: String): Boolean {
        val pa = a.split(".").map { it.toIntOrNull() ?: 0 }
        val pb = b.split(".").map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(pa.size, pb.size)) {
            val diff = pa.getOrElse(i) { 0 } - pb.getOrElse(i) { 0 }
            if (diff != 0) return diff > 0
        }
        return false
    }

    fun releases(context: Context): List<Release> = runCatching {
        val json = JSONArray(context.assets.open("derp/whatsnew.json").bufferedReader().use { it.readText() })
        (0 until json.length()).map { i ->
            val release = json.getJSONObject(i)
            val items = release.getJSONArray("items")
            Release(release.getString("version"), release.getString("title"), (0 until items.length()).map { j ->
                val item = items.getJSONObject(j)
                Item(item.getString("icon"), item.getString("title"), item.getString("text"), item.optString("android").ifBlank { null })
            })
        }
    }.getOrDefault(emptyList())

    /** This version's news (for About Derp → What's new). */
    fun current(context: Context) = releases(context).filter { !newer(it.version, BuildConfig.VERSION_NAME) }.take(1)

    /** What's new since you last looked, if anything; remembers you've looked.
     * [made]: whether you've made your dork (if not, Derp is new to you). */
    fun since(context: Context, made: Boolean): List<Release> {
        val prefs = context.getSharedPreferences("browser", Context.MODE_PRIVATE)
        val version = BuildConfig.VERSION_NAME
        val seen = prefs.getString("whatsNewSeen", null)
        prefs.edit().putString("whatsNewSeen", version).apply()
        if (!made || (seen != null && !newer(version, seen))) return emptyList()
        // Updating from before Derp kept track (2.0.x): this version's news.
        return releases(context).filter { if (seen != null) newer(it.version, seen) && !newer(it.version, version) else it.version == version }
    }
}
