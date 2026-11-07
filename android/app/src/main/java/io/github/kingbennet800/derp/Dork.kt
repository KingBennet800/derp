package io.github.kingbennet800.derp

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import com.caverock.androidsvg.SVG
import org.json.JSONObject

/** Your dork, Derp's account: a cartoon you design, kept only on this device.
 * Derp's pages (dork.html, newtab.html) draw and edit it with the same code as
 * desktop Derp and send it here; the toolbar shows it. */
class Dork(context: Context) {
    private val prefs = context.getSharedPreferences("dork", Context.MODE_PRIVATE)
    private var cached: Bitmap? = null

    /** Called (on the UI thread) whenever your dork changes. */
    var listener: (() -> Unit)? = null

    val json: JSONObject?
        get() = prefs.getString("dork", null)?.let { runCatching { JSONObject(it) }.getOrNull() }

    /** Set once you've pressed "That's me!"; until then Derp opens with the editor. */
    var made: Boolean
        get() = prefs.getBoolean("made", false)
        set(value) {
            prefs.edit().putBoolean("made", value).apply()
            listener?.invoke()
        }

    fun save(dork: JSONObject, svg: String) {
        prefs.edit().putString("dork", dork.toString()).putString("svg", svg).apply()
        cached = null
        listener?.invoke()
    }

    /** Your dork as a bitmap, or null before you have one. */
    fun avatar(size: Int): Bitmap? {
        cached?.let { if (it.width == size) return it }
        val svg = prefs.getString("svg", null) ?: return null
        cached = runCatching {
            val doc = SVG.getFromString(svg)
            doc.documentWidth = size.toFloat()
            doc.documentHeight = size.toFloat()
            Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { doc.renderToCanvas(Canvas(it)) }
        }.getOrNull()
        return cached
    }
}
