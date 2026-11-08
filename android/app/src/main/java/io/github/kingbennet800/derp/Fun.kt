package io.github.kingbennet800.derp

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/** Just for fun: joke settings, all off until you turn them on (⋮ → Just for
 * fun). Desktop Derp has the same ones (src/features/DerpDuck.sys.mjs and
 * DerpFun.sys.mjs). */
enum class Gag(val key: String, val title: String, val about: String) {
    DUCK("duck", "Duck mode", "1 in 10 times you press Enter in the address bar, a duck eats what you typed."),
    SNAIL("snail", "Snail mode", "When a page takes its time, a snail crawls along the loading bar."),
    PEEKABOO("peekaboo", "Peekaboo", "Now and then, your dork peeks up when you open a new tab."),
    PARTY("party", "Party mode", "Confetti when you bookmark a page.");

    fun on(context: Context) = prefs(context).getBoolean(key, false)

    fun set(context: Context, on: Boolean) = prefs(context).edit().putBoolean(key, on).apply()

    private fun prefs(context: Context) = context.getSharedPreferences("browser", Context.MODE_PRIVATE)
}

/** Party mode's confetti: a burst in Derp's colors from ([x], [y]) that
 * falls away and then removes itself. */
class Confetti(context: Context, x: Float, y: Float) : View(context) {
    private class Bit(var x: Float, var y: Float, var vx: Float, var vy: Float, var angle: Float, val spin: Float, val color: Int)

    private val density = context.resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val colors = listOf("#C6F57E", "#2FD6BE", "#2F6FEB", "#FFD43B", "#FF6B9A", "#B8A4FF").map(Color::parseColor)
    private val bits = List(70) { i ->
        // Up and out, then gravity takes over.
        val angle = Random.nextDouble(PI * 1.05, PI * 1.95)
        val speed = (350 + Random.nextFloat() * 650) * density
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
        val fade = (255 * (1 - (age - LIFE * 0.6f) / (LIFE * 0.4f))).toInt().coerceIn(0, 255)
        val w = 8 * density
        val h = 5 * density
        for (bit in bits) {
            bit.vy += 1500 * density * dt
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
        if (age < LIFE) postInvalidateOnAnimation() else post { (parent as? ViewGroup)?.removeView(this) }
    }

    companion object {
        private const val LIFE = 1.8f
    }
}
