package io.github.kingbennet800.derp

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import com.caverock.androidsvg.SVG
import java.time.LocalDate
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/** Just for fun: joke settings, all off until you turn them on (⋮ → Just for
 * fun). Desktop Derp has the same ones (src/features/DerpDuck.sys.mjs,
 * DerpPet.sys.mjs and DerpFun.sys.mjs). */
enum class Gag(val key: String, val title: String, val about: String) {
    DUCK("duck", "Duck mode", "1 in 10 times you press Enter in the address bar, a duck eats what you typed."),
    PET("pet", "Dork pet", "Your dork becomes a pet: it naps while you’re away and earns new outfits the more days you spend together."),
    SNAIL("snail", "Snail mode", "When a page takes its time, a snail crawls along the loading bar."),
    PEEKABOO("peekaboo", "Peekaboo", "Now and then, your dork peeks up when you open a new tab."),
    PARTY("party", "Party mode", "Confetti when you bookmark a page."),
    SLEEPY("sleepy", "Sleepy tabs", "Tabs Memory Saver has put to sleep snore. 💤"),
    POWER("power", "Power typing", "Sparks fly from the address bar as you type."),
    HICCUPS("hiccups", "Hiccups", "Now and then, a page gets the hiccups. Hic!"),
    GHOSTS("ghosts", "Tab ghosts", "A tab you close floats away as a little ghost."),
    RAINBOW("rainbow", "Rainbow mode", "The loading bar is a rainbow."),
    SEASONS("seasons", "Seasons", "Now and then the season drifts down: snow, blossoms, sunshine or leaves, with hearts for Valentine’s Day and pumpkins for Halloween."),
    DOWNLOAD_DUCK("downloadDuck", "Download duck", "A duck carries each download across the toolbar.");

    fun on(context: Context) = prefs(context).getBoolean(key, false)

    fun set(context: Context, on: Boolean) = prefs(context).edit().putBoolean(key, on).apply()

    private fun prefs(context: Context) = context.getSharedPreferences("browser", Context.MODE_PRIVATE)
}

/** A burst of little bits in Derp's colors from ([x], [y]), up and out, that
 * gravity pulls away; it removes itself. Party mode's confetti and Power
 * typing's sparks. */
class Burst(context: Context, x: Float, y: Float, private val style: Style) : View(context) {
    /** How many bits, how fast (dp/s), for how long (s), how heavy, and how big (dp). */
    class Style(val count: Int, val speed: ClosedFloatingPointRange<Float>, val life: Float, val gravity: Float, val w: Float, val h: Float)

    private class Bit(var x: Float, var y: Float, var vx: Float, var vy: Float, var angle: Float, val spin: Float, val color: Int)

    private val density = context.resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val colors = listOf("#C6F57E", "#2FD6BE", "#2F6FEB", "#FFD43B", "#FF6B9A", "#B8A4FF").map(Color::parseColor)
    private val bits = List(style.count) { i ->
        // Up and out, then gravity takes over.
        val angle = Random.nextDouble(PI * 1.05, PI * 1.95)
        val speed = (style.speed.start + Random.nextFloat() * (style.speed.endInclusive - style.speed.start)) * density
        Bit(x, y, (cos(angle) * speed).toFloat(), (sin(angle) * speed).toFloat(), Random.nextFloat() * 360, Random.nextFloat() * 900 - 450, colors[i % colors.size])
    }
    private var last = 0L
    private var age = 0f

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        val dt = if (last == 0L) 0f else ((now - last) / 1000f).coerceAtMost(0.05f)
        last = now
        age += dt
        // Fades out over the last 40%.
        val life = style.life
        val fade = (255 * (1 - (age - life * 0.6f) / (life * 0.4f))).toInt().coerceIn(0, 255)
        val w = style.w * density
        val h = style.h * density
        for (bit in bits) {
            bit.vy += style.gravity * density * dt
            bit.vx *= 1 - 0.8f * dt
            bit.x += bit.vx * dt
            bit.y += bit.vy * dt
            bit.angle += bit.spin * dt
            paint.color = bit.color
            paint.alpha = fade
            canvas.save()
            canvas.rotate(bit.angle, bit.x, bit.y)
            canvas.drawRect(bit.x - w / 2, bit.y - h / 2, bit.x + w / 2, bit.y + h / 2, paint)
            canvas.restore()
        }
        if (age < life) postInvalidateOnAnimation() else post { (parent as? ViewGroup)?.removeView(this) }
    }

    companion object {
        val CONFETTI = Style(70, 350f..1000f, 1.8f, 1500f, 8f, 5f)
        val SPARKS = Style(8, 80f..240f, 0.45f, 400f, 4f, 4f)
    }
}

/** Seasons: what drifts down on a given day, the same as desktop Derp
 * (seasonOf in DerpFun.sys.mjs, whose art prepare_assets.py copies into
 * assets/derp/seasons/). */
object Seasons {
    fun of(date: LocalDate): List<String> {
        val month = date.monthValue
        val day = date.dayOfMonth
        return when {
            month == 2 && day in 7..14 -> listOf("heart")
            month == 10 && day >= 24 -> listOf("pumpkin", "leaf", "redLeaf")
            month == 12 || month <= 2 -> listOf("snow")
            month <= 5 -> listOf("blossom")
            month <= 8 -> listOf("sun")
            else -> listOf("leaf", "redLeaf")
        }
    }

    /** Today's art as bitmaps, [size] px across. */
    fun art(context: Context, size: Int, date: LocalDate = LocalDate.now()): List<Bitmap> = of(date).mapNotNull { name ->
        runCatching {
            val svg = SVG.getFromAsset(context.assets, "derp/seasons/$name.svg")
            svg.documentWidth = size.toFloat()
            svg.documentHeight = size.toFloat()
            Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { svg.renderToCanvas(Canvas(it)) }
        }.getOrNull()
    }
}

/** A flurry of the season's things drifting down from the top of the page,
 * swaying and turning, and fading as they go; it removes itself. */
class Flurry(context: Context, private val art: List<Bitmap>, private val depth: Float) : View(context) {
    private class Bit(val art: Bitmap, val x: Float, val scale: Float, val delay: Float, val life: Float, val drift: Float, val spin: Float)

    private val density = context.resources.displayMetrics.density
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val bits = List(18) { i ->
        Bit(
            art[i % art.size], Random.nextFloat(), 0.45f + Random.nextFloat() * 0.45f, Random.nextFloat() * 1.4f,
            2.8f + Random.nextFloat() * 2f, (Random.nextFloat() * 120 - 60) * density, Random.nextFloat() * 540 - 270,
        )
    }
    private var start = 0L

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        if (start == 0L) start = now
        val age = (now - start) / 1000f
        var alive = false
        for (bit in bits) {
            val t = ((age - bit.delay) / bit.life).coerceIn(0f, 1f)
            if (t < 1f) alive = true
            if (t <= 0f || t >= 1f) continue
            // In over the first 12%, out over the last 30%.
            paint.alpha = (255 * minOf(1f, t / 0.12f, (1 - t) / 0.3f)).toInt().coerceIn(0, 255)
            val size = bit.art.width * bit.scale
            val x = bit.x * width + bit.drift * t
            val y = -size + (depth + size) * t
            canvas.save()
            canvas.rotate(bit.spin * t, x, y)
            canvas.translate(x - size / 2, y - size / 2)
            canvas.scale(bit.scale, bit.scale)
            canvas.drawBitmap(bit.art, 0f, 0f, paint)
            canvas.restore()
        }
        if (alive) postInvalidateOnAnimation() else post { (parent as? ViewGroup)?.removeView(this) }
    }
}
