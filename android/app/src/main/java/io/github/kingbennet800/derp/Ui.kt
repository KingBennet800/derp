package io.github.kingbennet800.derp

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.OvalShape
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.animation.PathInterpolator
import android.widget.LinearLayout

/** Derp's colors: desktop Derp's theme tokens (theme/derp-theme.css), for
 * light, dark and private tabs. */
data class Palette(
    /** Behind the tab strip. */
    val frame: Int,
    val toolbar: Int,
    /** The address bar while you type in it. */
    val fieldFocus: Int,
    /** Menus. */
    val box: Int,
    /** Behind pages, until they paint. */
    val content: Int,
    val text: Int,
    val dim: Int,
    val icon: Int,
    /** Hairlines in the toolbar and tab strip. */
    val line: Int,
    /** The hairline between the toolbar and the page. */
    val contentLine: Int,
    val accent: Int,
    val dark: Boolean,
) {
    /** Pressed buttons and rows: the text color, faintly. */
    val press get() = (text and 0xFFFFFF) or 0x24000000

    companion object {
        private fun c(hex: String) = Color.parseColor(hex)

        val LIGHT = Palette(
            frame = c("#ECECEE"), toolbar = c("#FAFAFA"), fieldFocus = c("#FFFFFF"), box = c("#FFFFFF"),
            content = c("#FFFFFF"), text = c("#1D1D1F"), dim = c("#6E6E73"), icon = c("#5A5A60"),
            line = c("#D8D8DC"), contentLine = c("#E0E0E4"), accent = c("#2F6FEB"), dark = false,
        )
        val DARK = Palette(
            frame = c("#1B1B1C"), toolbar = c("#272728"), fieldFocus = c("#303032"), box = c("#26272A"),
            content = c("#1E1E1F"), text = c("#ECECEC"), dim = c("#A3A3A6"), icon = c("#B4B4B8"),
            line = c("#3A3A3C"), contentLine = c("#333335"), accent = c("#86B1FF"), dark = true,
        )
        /** Private tabs are always dark, with a violet tint so they stand out. */
        val PRIVATE = Palette(
            frame = c("#1C1925"), toolbar = c("#2A2633"), fieldFocus = c("#343040"), box = c("#2A2633"),
            content = c("#1F1C27"), text = c("#ECEBF2"), dim = c("#BDB8CC"), icon = c("#CBC5DA"),
            line = c("#3D3848"), contentLine = c("#3A3546"), accent = c("#B8A4FF"), dark = true,
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

val MEDIUM: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)

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

/** The press ripple of a round icon button: a circle, [inset] in from the button's edges. */
fun roundRipple(color: Int, inset: Int) =
    RippleDrawable(ColorStateList.valueOf(color), null, InsetDrawable(ShapeDrawable(OvalShape()), inset))

/** The press ripple of a row: a rounded rectangle. */
fun rowRipple(color: Int, radius: Float) = RippleDrawable(ColorStateList.valueOf(color), null, rounded(Color.WHITE, radius))

/** The tab strip's color, with the hairline along its bottom that the selected tab opens out of. */
fun stripBackground(fill: Int, line: Int, lineWidth: Int): Drawable =
    LayerDrawable(arrayOf(ColorDrawable(fill), ColorDrawable(line))).apply {
        setLayerGravity(1, Gravity.BOTTOM or Gravity.FILL_HORIZONTAL)
        setLayerHeight(1, lineWidth)
    }

/** A tab in the tablet tab strip. The one in front is desktop Derp's folder
 * tab: the toolbar's color, outlined by a hairline whose feet curve out into
 * the strip's bottom line. The feet need [foot] of room on each side, so tabs
 * overlap their neighbors by that much. */
class FolderTab(context: Context, private val foot: Int) : LinearLayout(context) {
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val fillPath = Path()
    private val edgePath = Path()
    private val lip = context.dpf(6)
    private var front = false

    init {
        setWillNotDraw(false)
    }

    fun paint(front: Boolean, fillColor: Int, lineColor: Int, lineWidth: Int) {
        this.front = front
        fill.color = fillColor
        edge.color = lineColor
        edge.strokeWidth = lineWidth.toFloat()
        // Tabs behind get a soft rounded highlight when pressed.
        foreground = if (front) null else RippleDrawable(
            ColorStateList.valueOf((lineColor and 0xFFFFFF) or 0x66000000), null,
            InsetDrawable(rounded(Color.WHITE, context.dpf(8)), foot, lip.toInt(), foot, context.dp(5)),
        )
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        outline(fillPath, w.toFloat(), h.toFloat())
        fillPath.close()
        // The hairline lands on the middle of the strip's line.
        outline(edgePath, w.toFloat(), h - edge.strokeWidth / 2)
    }

    private fun outline(path: Path, w: Float, bottom: Float) {
        val r = foot.toFloat()
        path.reset()
        path.moveTo(0f, bottom)
        path.arcTo(RectF(-r, bottom - 2 * r, r, bottom), 90f, -90f)
        path.lineTo(r, lip + r)
        path.arcTo(RectF(r, lip, 3 * r, lip + 2 * r), 180f, 90f)
        path.lineTo(w - 2 * r, lip)
        path.arcTo(RectF(w - 3 * r, lip, w - r, lip + 2 * r), 270f, 90f)
        path.lineTo(w - r, bottom - r)
        path.arcTo(RectF(w - r, bottom - 2 * r, w + r, bottom), 180f, -90f)
    }

    override fun onDraw(canvas: Canvas) {
        if (front) {
            canvas.drawPath(fillPath, fill)
            canvas.drawPath(edgePath, edge)
        }
        super.onDraw(canvas)
    }
}

/** The hairline between the page and the toolbar, with desktop Derp's
 * loading shimmer: a short lime-teal-blue streak sweeping along it while a
 * page loads. The hairline is on the page's side ([lineAtTop] when the page
 * is above). */
class ProgressLine(context: Context, private val lineAtTop: Boolean) : View(context) {
    private val hairline = Paint()
    private val streak = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shift = Matrix()
    private var busy = false
    private var shown = 0f
    private var phase = 0f
    private var fade: ValueAnimator? = null
    private val sweep = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1150
        repeatCount = ValueAnimator.INFINITE
        interpolator = PathInterpolator(0.45f, 0f, 0.55f, 1f)
        addUpdateListener {
            phase = it.animatedValue as Float
            invalidate()
        }
    }

    fun setColors(line: Int, background: Int) {
        hairline.color = line
        setBackgroundColor(background)
    }

    fun setBusy(on: Boolean) {
        if (on == busy) return
        busy = on
        if (on && ValueAnimator.areAnimatorsEnabled() && !sweep.isStarted) sweep.start()
        fade?.cancel()
        fade = ValueAnimator.ofFloat(shown, if (on) 1f else 0f).apply {
            duration = 450
            addUpdateListener {
                shown = it.animatedValue as Float
                invalidate()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (!busy) sweep.cancel()
                }
            })
            start()
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // Faded in at both ends, like desktop's mask.
        val length = if (ValueAnimator.areAnimatorsEnabled()) w * 0.35f else w.toFloat()
        streak.shader = LinearGradient(
            0f, 0f, length, 0f,
            intArrayOf(0x00C6F57E, 0xFF72E4A2.toInt(), 0xFF2FD6BE.toInt(), 0xFF2F9ED7.toInt(), 0x002F6FEB),
            floatArrayOf(0f, 0.25f, 0.45f, 0.75f, 1f), Shader.TileMode.CLAMP,
        )
    }

    override fun onDetachedFromWindow() {
        sweep.cancel()
        fade?.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val line = context.dp(1).toFloat()
        if (lineAtTop) canvas.drawRect(0f, 0f, w, line, hairline) else canvas.drawRect(0f, h - line, w, h, hairline)
        if (shown <= 0f) return
        streak.alpha = (shown * 255).toInt()
        if (ValueAnimator.areAnimatorsEnabled()) {
            // From just off the left edge to just off the right one.
            val length = w * 0.35f
            val x = -length + phase * (w * 1.05f + length)
            shift.setTranslate(x, 0f)
            streak.shader?.setLocalMatrix(shift)
            canvas.drawRoundRect(x, 0f, x + length, h, h / 2, h / 2, streak)
        } else {
            canvas.drawRect(0f, 0f, w, h, streak)
        }
    }
}
