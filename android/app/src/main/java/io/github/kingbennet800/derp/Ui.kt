package io.github.kingbennet800.derp

import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.animation.ValueAnimator

/** Derp's colors (the desktop theme's tokens): light, dark, and private tabs. */
data class Palette(
    val frame: Int,
    val toolbar: Int,
    val field: Int,
    val card: Int,
    val text: Int,
    val dim: Int,
    val line: Int,
    val accent: Int,
    val onAccent: Int,
    val dark: Boolean,
) {
    companion object {
        private fun c(hex: String) = Color.parseColor(hex)

        val LIGHT = Palette(
            frame = c("#ECECEE"), toolbar = c("#FAFAFA"), field = c("#ECECEE"), card = c("#FFFFFF"),
            text = c("#18181B"), dim = c("#5F6068"), line = c("#DEDEE3"), accent = c("#2F6FEB"),
            onAccent = c("#FFFFFF"), dark = false,
        )
        val DARK = Palette(
            frame = c("#1B1B1C"), toolbar = c("#272728"), field = c("#38383B"), card = c("#2C2C2F"),
            text = c("#F2F2F3"), dim = c("#A1A1AA"), line = c("#3A3A3C"), accent = c("#86B1FF"),
            onAccent = c("#0F1115"), dark = true,
        )
        val PRIVATE = Palette(
            frame = c("#1C1729"), toolbar = c("#2A2140"), field = c("#3B3057"), card = c("#342A4D"),
            text = c("#F4F0FF"), dim = c("#B8AED6"), line = c("#43385F"), accent = c("#B69CFF"),
            onAccent = c("#140F22"), dark = true,
        )

        fun of(context: Context, private: Boolean): Palette {
            val night = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
            return when {
                private -> PRIVATE
                night -> DARK
                else -> LIGHT
            }
        }
    }
}

fun Context.dp(value: Int): Int =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

fun Context.dpf(value: Int): Float =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics)

fun rounded(color: Int, radius: Float, stroke: Int = 0, strokeColor: Int = Color.TRANSPARENT) =
    GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius
        if (stroke > 0) setStroke(stroke, strokeColor)
    }

/** The hairline between the page and the toolbar, with Derp's lime-teal-blue
 * loading bar running along it while a page loads. */
class ProgressLine(context: Context) : View(context) {
    private val bar = Paint(Paint.ANTI_ALIAS_FLAG)
    private val hairline = Paint()
    private var shown = 1f
    private var animator: ValueAnimator? = null

    fun setColors(line: Int) {
        hairline.color = line
        invalidate()
    }

    fun setProgress(progress: Int) {
        val target = progress.coerceIn(0, 100) / 100f
        animator?.cancel()
        if (target >= 1f && shown >= 1f) return
        animator = ValueAnimator.ofFloat(if (target < shown) 0f else shown, target).apply {
            duration = if (target >= 1f) 180 else 260
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                shown = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    override fun onDraw(canvas: Canvas) {
        val h = height.toFloat()
        canvas.drawRect(0f, h - 1f, width.toFloat(), h, hairline)
        if (shown in 0.001f..0.999f) {
            bar.shader = LinearGradient(
                0f, 0f, width.toFloat(), 0f,
                intArrayOf(Color.parseColor("#C6F57E"), Color.parseColor("#2FD6BE"), Color.parseColor("#2F6FEB")),
                null, Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, width * shown, h, bar)
        }
    }
}
