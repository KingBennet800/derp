package io.github.kingbennet800.derp

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/** Your bookmarks and history (and the passwords table Logins keeps), in one
 * database on this device. Nothing here leaves it. */
class Library(context: Context) : SQLiteOpenHelper(context, "derp.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE bookmarks (url TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '', added INTEGER NOT NULL)")
        db.execSQL(
            "CREATE TABLE history (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL, " +
                "title TEXT NOT NULL DEFAULT '', visited INTEGER NOT NULL)",
        )
        db.execSQL("CREATE INDEX history_url ON history (url)")
        db.execSQL("CREATE INDEX history_visited ON history (visited)")
        db.execSQL(
            "CREATE TABLE logins (guid TEXT PRIMARY KEY, origin TEXT NOT NULL, form_action TEXT, realm TEXT, " +
                "username TEXT NOT NULL DEFAULT '', password TEXT NOT NULL, created INTEGER NOT NULL, used INTEGER NOT NULL)",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    // ── Bookmarks ──────────────────────────────────────────────────────────

    fun isBookmarked(url: String): Boolean =
        readableDatabase.rawQuery("SELECT 1 FROM bookmarks WHERE url = ?", arrayOf(url)).use { it.moveToFirst() }

    fun bookmark(url: String, title: String) {
        writableDatabase.insertWithOnConflict("bookmarks", null, ContentValues().apply {
            put("url", url)
            put("title", title)
            put("added", System.currentTimeMillis())
        }, SQLiteDatabase.CONFLICT_REPLACE)
        Log.i("Derp", "Bookmarks: ${count("bookmarks")}")
    }

    fun unbookmark(url: String) {
        writableDatabase.delete("bookmarks", "url = ?", arrayOf(url))
    }

    /** Every bookmark, address to title (for syncing with your other devices). */
    fun allBookmarks(): Map<String, String> {
        val all = LinkedHashMap<String, String>()
        readableDatabase.rawQuery("SELECT url, title FROM bookmarks ORDER BY added", null).use { c ->
            while (c.moveToNext()) all[c.getString(0)] = c.getString(1).orEmpty()
        }
        return all
    }

    fun retitle(url: String, title: String) {
        writableDatabase.update("bookmarks", ContentValues().apply { put("title", title) }, "url = ?", arrayOf(url))
    }

    /** Newest first, optionally only those matching [query]. */
    fun bookmarks(query: String = "", limit: Int = 500): JSONArray {
        val items = JSONArray()
        val (where, args) = matching(query)
        readableDatabase.rawQuery(
            "SELECT url, title, added FROM bookmarks $where ORDER BY added DESC LIMIT $limit", args,
        ).use { c ->
            while (c.moveToNext()) {
                items.put(JSONObject().put("url", c.getString(0)).put("title", c.getString(1)).put("added", c.getLong(2)))
            }
        }
        return items
    }

    /** Adds the ones you don't have yet; returns how many that was. */
    fun importBookmarks(marks: List<Imports.Bookmark>): Int {
        val db = writableDatabase
        var added = 0
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            // Oldest first, so the file's first bookmark ends up on top.
            marks.asReversed().forEachIndexed { i, mark ->
                val row = ContentValues().apply {
                    put("url", mark.url)
                    put("title", mark.title)
                    put("added", now + i)
                }
                if (db.insertWithOnConflict("bookmarks", null, row, SQLiteDatabase.CONFLICT_IGNORE) != -1L) added++
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        Log.i("Derp", "Bookmarks: ${count("bookmarks")} after importing $added")
        return added
    }

    // ── History ────────────────────────────────────────────────────────────

    /** A page you went to. Coming back to the same page within half an hour
     * (a reload, say) moves its visit instead of adding another. */
    fun visit(url: String) {
        val db = writableDatabase
        val now = System.currentTimeMillis()
        val recent = db.rawQuery(
            "SELECT id FROM history WHERE url = ? AND visited > ? ORDER BY visited DESC LIMIT 1",
            arrayOf(url, (now - 30 * MINUTE).toString()),
        ).use { if (it.moveToFirst()) it.getLong(0) else null }
        if (recent != null) {
            db.update("history", ContentValues().apply { put("visited", now) }, "id = ?", arrayOf(recent.toString()))
        } else {
            db.insert("history", null, ContentValues().apply {
                put("url", url)
                put("visited", now)
            })
            if (++visits % 100 == 0) prune(db, now)
        }
    }

    private var visits = 0

    /** Keeps the last 180 days, at most 20,000 visits. */
    private fun prune(db: SQLiteDatabase, now: Long) {
        db.delete("history", "visited < ?", arrayOf((now - 180 * DAY).toString()))
        db.execSQL("DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY visited DESC LIMIT 20000)")
    }

    /** The page's title, once it has one, for its latest visit. */
    fun title(url: String, title: String) {
        if (title.isBlank()) return
        writableDatabase.execSQL(
            "UPDATE history SET title = ? WHERE id = (SELECT id FROM history WHERE url = ? ORDER BY visited DESC LIMIT 1)",
            arrayOf(title, url),
        )
    }

    /** Newest first, older than [before] (for paging), optionally matching [query]. */
    fun history(query: String = "", before: Long = Long.MAX_VALUE, limit: Int = 200): JSONArray {
        val items = JSONArray()
        val (where, args) = matching(query)
        val clause = if (where.isEmpty()) "WHERE visited < ?" else "$where AND visited < ?"
        readableDatabase.rawQuery(
            "SELECT url, title, visited FROM history $clause ORDER BY visited DESC LIMIT $limit", args + before.toString(),
        ).use { c ->
            while (c.moveToNext()) {
                items.put(JSONObject().put("url", c.getString(0)).put("title", c.getString(1)).put("visited", c.getLong(2)))
            }
        }
        return items
    }

    fun forget(url: String) {
        writableDatabase.delete("history", "url = ?", arrayOf(url))
    }

    fun clearHistory() {
        writableDatabase.delete("history", null, null)
    }

    // ──────────────────────────────────────────────────────────────────────

    fun count(table: String): Long = readableDatabase.rawQuery("SELECT COUNT(*) FROM $table", null).use {
        it.moveToFirst()
        it.getLong(0)
    }

    /** A WHERE clause matching [query] in the title or address. */
    private fun matching(query: String): Pair<String, Array<String>> {
        val q = query.trim()
        if (q.isEmpty()) return "" to emptyArray()
        val like = "%" + q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        return "WHERE (title LIKE ? ESCAPE '\\' OR url LIKE ? ESCAPE '\\')" to arrayOf(like, like)
    }

    companion object {
        private const val MINUTE = 60 * 1000L
        private const val DAY = 24 * 60 * MINUTE
    }
}
