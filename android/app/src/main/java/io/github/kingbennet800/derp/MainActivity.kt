package io.github.kingbennet800.derp

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.text.TextUtils
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.animation.LinearInterpolator
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import android.window.OnBackInvokedDispatcher
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoView
import org.mozilla.geckoview.StorageController
import org.json.JSONObject
import org.mozilla.geckoview.WebResponse
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random

class MainActivity : Activity() {
    private val app get() = application as DerpApp
    private val browser get() = app.browser

    private lateinit var root: FrameLayout
    private lateinit var column: LinearLayout
    private lateinit var geckoView: GeckoView
    private lateinit var progress: ProgressLine
    private lateinit var bar: LinearLayout
    private lateinit var url: EditText
    private lateinit var avatar: ImageView
    private lateinit var avatarButton: FrameLayout
    private lateinit var menuButton: ImageButton
    private var tabsPanel: LinearLayout? = null
    private var palette = Palette.LIGHT
    private var fullScreen = false
    private var topInset = 0
    private var bottomInset = 0

    /** Tablets look like desktop Derp: a tab strip with folder tabs, and the
     * toolbar (with back, forward and reload) under it. Phones keep the
     * toolbar at the bottom, with a tabs button. */
    private val tablet get() = resources.configuration.smallestScreenWidthDp >= 600
    private var tabCount: TextView? = null
    private var strip: LinearLayout? = null
    private var stripTabs: LinearLayout? = null
    private var stripScroll: HorizontalScrollView? = null
    private var stripShown = ""
    private var back: ImageButton? = null
    private var forward: ImageButton? = null
    private var reload: ImageButton? = null
    /** The toolbar's icon buttons, recolored with the palette. */
    private val toolbarButtons = mutableListOf<ImageButton>()
    private val hairline get() = dp(1)
    private var permissionCallback: GeckoSession.PermissionDelegate.Callback? = null
    private var filesCallback: ((Int, Intent?) -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        edgeToEdge()
        buildViews()
        browser.ui = this
        app.dork.listener = { runOnUiThread { paintAvatar() } }
        if (Build.VERSION.SDK_INT >= 33) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) {
                if (!handleBack()) moveTaskToBack(true)
            }
        }
        browser.start(intent)
        render()
    }

    /** Every time Derp comes to the screen, it looks for a newer Derp (at most once an hour). */
    override fun onResume() {
        super.onResume()
        Updater.check(this, manual = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == Updater.INSTALL_STATUS) return installStatus(intent)
        closeTabs()
        browser.handle(intent)
    }

    override fun onPause() {
        browser.save()
        super.onPause()
    }

    override fun onDestroy() {
        if (browser.ui === this) browser.ui = null
        geckoView.releaseSession()
        super.onDestroy()
    }

    @Deprecated("Android 13+ uses the back callback registered in onCreate")
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (!handleBack()) super.onBackPressed()
    }

    private fun handleBack(): Boolean {
        val tab = browser.current
        return when {
            fullScreen -> {
                tab?.session?.exitFullScreen()
                true
            }
            tabsPanel != null -> {
                closeTabs()
                true
            }
            url.hasFocus() -> {
                url.clearFocus()
                hideKeyboard()
                true
            }
            tab?.canGoBack == true -> {
                tab.session.goBack()
                true
            }
            else -> false
        }
    }

    // ── Layout ─────────────────────────────────────────────────────────────

    private fun edgeToEdge() {
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
    }

    private fun buildViews() {
        root = FrameLayout(this)
        column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        geckoView = GeckoView(this)
        progress = ProgressLine(this, lineAtTop = !tablet)

        bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            if (tablet) setPadding(dp(6), dp(4), dp(6), dp(4)) else setPadding(dp(6), dp(6), dp(2), dp(6))
        }
        if (tablet) {
            val buttons = listOf(
                toolbarButton(R.drawable.ic_back, "Back") { browser.current?.session?.goBack() },
                toolbarButton(R.drawable.ic_forward, "Forward") { browser.current?.session?.goForward() },
                toolbarButton(R.drawable.ic_reload, "Reload") {
                    val tab = browser.current ?: return@toolbarButton
                    if (tab.progress < 100) tab.session.stop() else tab.session.reload()
                },
            )
            buttons.forEach { bar.addView(it, LinearLayout.LayoutParams(dp(40), dp(40))) }
            back = buttons[0]
            forward = buttons[1]
            reload = buttons[2]
        }
        url = EditText(this).apply {
            id = View.generateViewId()
            contentDescription = "Address bar"
            setSingleLine()
            textSize = 15f
            setPadding(dp(14), 0, dp(14), 0)
            gravity = Gravity.CENTER_VERTICAL
            imeOptions = EditorInfo.IME_ACTION_GO or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            setSelectAllOnFocus(true)
            ellipsize = TextUtils.TruncateAt.END
            compoundDrawablePadding = dp(10)
            hint = "Search or enter address"
            setOnEditorActionListener { _, action, event ->
                val enter = event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN
                if (action == EditorInfo.IME_ACTION_GO || enter) {
                    go(text.toString())
                    true
                } else false
            }
            setOnFocusChangeListener { _, focused ->
                val tab = browser.current
                setText(if (tab == null) "" else if (focused) browser.address(tab) else browser.display(tab))
                if (focused) selectAll()
                paintUrl()
            }
        }
        bar.addView(url, LinearLayout.LayoutParams(0, dp(if (tablet) 40 else 44), 1f).apply {
            if (tablet) marginStart = dp(6)
        })

        avatar = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) = outline.setOval(0, 0, view.width, view.height)
            }
            clipToOutline = true
        }
        avatarButton = FrameLayout(this).apply {
            contentDescription = "Your dork"
            isClickable = true
            setOnClickListener {
                closeTabs()
                browser.openDork()
            }
            addView(avatar, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER))
        }

        if (!tablet) {
            val count = TextView(this).apply {
                gravity = Gravity.CENTER
                textSize = 11f
                typeface = MEDIUM
            }
            tabCount = count
            val tabsButton = FrameLayout(this).apply {
                id = View.generateViewId()
                contentDescription = "Tabs"
                isClickable = true
                setOnClickListener { if (tabsPanel == null) openTabs() else closeTabs() }
                addView(count, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            }
            bar.addView(tabsButton, LinearLayout.LayoutParams(dp(44), dp(44)).apply { marginStart = dp(4) })
            bar.addView(avatarButton, LinearLayout.LayoutParams(dp(44), dp(44)))
        }
        menuButton = toolbarButton(R.drawable.ic_menu, "Menu") { showMenu() }
        bar.addView(menuButton, LinearLayout.LayoutParams(dp(if (tablet) 40 else 44), dp(if (tablet) 40 else 44)))

        // Phones: page, then the toolbar at the bottom. Tablets: tab strip and toolbar on top.
        val page = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f)
        val line = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2))
        val toolbar = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        if (tablet) {
            column.addView(buildStrip(), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(44)))
            column.addView(bar, toolbar)
            column.addView(progress, line)
            column.addView(geckoView, page)
        } else {
            column.addView(geckoView, page)
            column.addView(progress, line)
            column.addView(bar, toolbar)
        }
        root.addView(column, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        setContentView(root)

        root.setOnApplyWindowInsetsListener { _, insets ->
            val sides = if (Build.VERSION.SDK_INT >= 30) {
                val i = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                intArrayOf(i.left, i.top, i.right, i.bottom)
            } else {
                @Suppress("DEPRECATION")
                intArrayOf(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            }
            topInset = sides[1]
            bottomInset = sides[3]
            if (fullScreen) column.setPadding(0, 0, 0, 0) else column.setPadding(sides[0], sides[1], sides[2], sides[3])
            tabsPanel?.setPadding(sides[0], sides[1], sides[2], sides[3])
            if (Build.VERSION.SDK_INT >= 30) WindowInsets.CONSUMED else insets
        }
    }

    /** The tablet tab strip: your tabs and a new tab button, and your dork in the corner. */
    private fun buildStrip(): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(6), 0, 0, 0)
        }
        val scroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            addView(row, ViewGroup.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
        val strip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(scroll, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
            addView(avatarButton, LinearLayout.LayoutParams(dp(44), dp(44)).apply { marginEnd = dp(4) })
        }
        this.strip = strip
        stripTabs = row
        stripScroll = scroll
        return strip
    }

    /** A round icon button in desktop Derp's style, colored for [colors]. */
    private fun iconButton(icon: Int, description: String, colors: Palette = palette, onClick: () -> Unit) = ImageButton(this).apply {
        setImageResource(icon)
        contentDescription = description
        scaleType = ImageView.ScaleType.CENTER
        setOnClickListener { onClick() }
        paintButton(this, colors)
    }

    /** A toolbar button: recolored whenever the palette changes. */
    private fun toolbarButton(icon: Int, description: String, onClick: () -> Unit) =
        iconButton(icon, description, palette, onClick).also { toolbarButtons += it }

    private fun paintButton(button: ImageButton, colors: Palette) {
        button.imageTintList = ColorStateList.valueOf(colors.icon)
        button.background = roundRipple(colors.press, dp(2))
    }

    private fun enable(button: ImageButton?, on: Boolean) {
        button ?: return
        button.isEnabled = on
        button.alpha = if (on) 1f else 0.4f
    }

    // ── Showing tabs ───────────────────────────────────────────────────────

    fun showTab(tab: Tab) {
        if (geckoView.session !== tab.session) {
            geckoView.releaseSession()
            geckoView.coverUntilFirstPaint(Palette.of(this, tab.private).content)
            geckoView.setSession(tab.session)
        }
        render()
    }

    fun detachTab() {
        geckoView.releaseSession()
    }

    fun onTabsChanged() = render()

    fun onTabChanged(tab: Tab) {
        if (tab === browser.current) render() else fillStrip()
        tabsPanel?.let { fillTabs(it) }
    }

    /** Everything in the toolbar, from the current tab. */
    private fun render() {
        val tab = browser.current
        palette = Palette.of(this, tab?.private == true)
        root.setBackgroundColor(if (tablet) palette.frame else palette.toolbar)
        strip?.background = stripBackground(palette.frame, palette.line, hairline)
        bar.setBackgroundColor(palette.toolbar)
        progress.setColors(palette.contentLine, palette.toolbar)
        progress.setBusy((tab?.progress ?: 100) < 100)
        toolbarButtons.forEach { paintButton(it, palette) }
        avatarButton.background = roundRipple(palette.press, dp(4))

        enable(back, tab?.canGoBack == true)
        enable(forward, tab?.canGoForward == true)
        val loading = (tab?.progress ?: 100) < 100
        reload?.setImageResource(if (loading) R.drawable.ic_stop else R.drawable.ic_reload)
        reload?.contentDescription = if (loading) "Stop" else "Reload"

        paintUrl()
        url.setTextColor(palette.text)
        url.setHintTextColor(palette.dim)
        url.highlightColor = (palette.accent and 0xFFFFFF) or 0x55000000
        if (!url.hasFocus()) url.setText(tab?.let { browser.display(it) } ?: "")
        // Private tabs wear the mask; otherwise a quiet search glyph marks the address bar.
        val glyph = getDrawable(if (tab?.private == true) R.drawable.ic_mask else R.drawable.ic_search)?.mutate()?.apply {
            setTint(if (tab?.private == true) palette.accent else palette.dim)
            setBounds(0, 0, dp(18), dp(18))
        }
        url.setCompoundDrawablesRelative(glyph, null, null, null)

        tabCount?.let {
            val count = browser.tabs.size
            it.text = if (count > 99) ":D" else count.toString()
            it.setTextColor(palette.icon)
            it.background = rounded(Color.TRANSPARENT, dpf(5), (resources.displayMetrics.density * 1.5f).toInt(), palette.icon)
            (it.parent as View).background = roundRipple(palette.press, dp(2))
        }
        paintAvatar()
        fillStrip()
        systemBarIcons(palette.dark)
    }

    /** No pill at rest, like desktop Derp; it fills in with an accent ring while you type. */
    private fun paintUrl() {
        val radius = dpf(if (tablet) 20 else 22)
        url.background = if (url.hasFocus()) {
            rounded(palette.fieldFocus, radius, (resources.displayMetrics.density * 1.5f).toInt(), palette.accent)
        } else {
            rounded(Color.TRANSPARENT, radius)
        }
    }

    /** The tablet tab strip, rebuilt when a tab's title, address or place changes. */
    private fun fillStrip() {
        val row = stripTabs ?: return
        val shown = browser.tabs.joinToString("\n") {
            "${System.identityHashCode(it)} ${it.private} ${it === browser.current} ${browser.display(it)} ${it.title}"
        } + palette.hashCode()
        if (shown == stripShown) return
        stripShown = shown
        row.removeAllViews()

        // Tabs share the room up to desktop's tab width; past that the strip scrolls.
        val foot = dp(10)
        val room = resources.displayMetrics.widthPixels - dp(6 + 48 + 44)
        val body = (room / maxOf(1, browser.tabs.size) - foot).coerceIn(dp(112), dp(232))
        var front: View? = null
        browser.tabs.forEachIndexed { i, tab ->
            val selected = tab === browser.current
            val title = tab.title.ifBlank { browser.display(tab).ifBlank { "New tab" } }
            val view = FolderTab(this, foot).apply {
                paint(selected, palette.toolbar, palette.line, hairline)
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(foot + dp(10), dp(6), foot + dp(2), 0)
                contentDescription = title
                setOnClickListener { browser.select(tab) }
            }
            view.addView(ImageView(this).apply { tabIcon(this, tab, palette) }, LinearLayout.LayoutParams(dp(16), dp(16)))
            view.addView(TextView(this).apply {
                text = title
                textSize = 14f
                setTextColor(if (selected) palette.text else palette.dim)
                typeface = if (selected) MEDIUM else Typeface.DEFAULT
                setSingleLine()
                ellipsize = TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(8) })
            if (selected) {
                view.addView(iconButton(R.drawable.ic_close, "Close tab") { browser.close(tab) }.apply {
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    setPadding(dp(7), dp(7), dp(7), dp(7))
                    background = roundRipple(palette.press, 0)
                }, LinearLayout.LayoutParams(dp(30), dp(30)))
                front = view
            }
            row.addView(view, LinearLayout.LayoutParams(body + 2 * foot, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                if (i > 0) marginStart = -foot
            })
        }
        row.addView(iconButton(R.drawable.ic_plus, "Open a new tab") { browser.newTab(null) },
            LinearLayout.LayoutParams(dp(36), dp(36)).apply {
                gravity = Gravity.CENTER_VERTICAL
                topMargin = dp(3)
            })
        // Keep the tab in front in view.
        front?.let { tab ->
            val scroll = stripScroll ?: return@let
            scroll.post {
                when {
                    tab.left < scroll.scrollX -> scroll.smoothScrollTo(tab.left, 0)
                    tab.right > scroll.scrollX + scroll.width -> scroll.smoothScrollTo(tab.right - scroll.width, 0)
                }
            }
        }
    }

    /** A tab's icon: Derp's logo on Derp's pages, the mask for private tabs, a globe for websites. */
    private fun tabIcon(view: ImageView, tab: Tab, colors: Palette) {
        when {
            tab.private -> {
                view.setImageResource(R.drawable.ic_mask)
                view.imageTintList = ColorStateList.valueOf(if (colors.dark) Palette.PRIVATE.accent else VIOLET)
            }
            browser.display(tab).isBlank() -> view.setImageResource(R.drawable.derp_logo)
            else -> {
                view.setImageResource(R.drawable.ic_globe)
                view.imageTintList = ColorStateList.valueOf(colors.dim)
            }
        }
    }

    private fun paintAvatar() {
        val dork = app.dork.avatar(dp(64))
        if (dork != null) avatar.setImageBitmap(dork) else avatar.setImageResource(R.drawable.derp_logo)
    }

    private fun systemBarIcons(dark: Boolean) {
        if (Build.VERSION.SDK_INT >= 30) {
            val light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            window.insetsController?.setSystemBarsAppearance(if (dark) 0 else light, light)
        } else {
            @Suppress("DEPRECATION")
            val flags = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                if (dark) window.decorView.systemUiVisibility and flags.inv() else window.decorView.systemUiVisibility or flags
        }
    }

    // ── Address bar ────────────────────────────────────────────────────────

    private fun go(text: String) {
        val tab = browser.current ?: return
        if (text.isBlank() || duckBusy) return
        if (duckMode && Random.nextInt(10) == 0) return duck(text)
        url.clearFocus()
        hideKeyboard()
        browser.load(tab, browser.toUrl(text))
    }

    fun focusUrl() {
        url.requestFocus()
        getSystemService(InputMethodManager::class.java)?.showSoftInput(url, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun hideKeyboard() {
        getSystemService(InputMethodManager::class.java)?.hideSoftInputFromWindow(url.windowToken, 0)
    }

    // ── Duck mode ──────────────────────────────────────────────────────────

    /** Duck mode, a joke setting (off by default, in the menu): 1 in 10 times
     * you press Enter in the address bar, a duck waddles along it and eats what
     * you typed instead. Desktop Derp has the same duck. */
    private var duckMode: Boolean
        get() = getSharedPreferences("browser", MODE_PRIVATE).getBoolean("duck", false)
        set(value) = getSharedPreferences("browser", MODE_PRIVATE).edit().putBoolean("duck", value).apply()
    private var duckBusy = false

    private fun duck(text: String) {
        duckBusy = true
        val size = dp(26)
        val duck = ImageView(this).apply { setImageResource(R.drawable.ic_duck) }
        val quack = TextView(this).apply {
            this.text = "Quack!"
            textSize = 13f
            typeface = MEDIUM
            setTextColor(Color.parseColor("#3A2A00"))
            background = rounded(Color.parseColor("#FFD43B"), dpf(8))
            setPadding(dp(8), dp(2), dp(8), dp(2))
            alpha = 0f
        }
        root.addView(duck, FrameLayout.LayoutParams(size, size))
        root.addView(quack, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // The duck stands at the end of what's left of the text.
        val rootAt = IntArray(2).also { root.getLocationInWindow(it) }
        val fieldAt = IntArray(2).also { url.getLocationInWindow(it) }
        val left = (fieldAt[0] - rootAt[0]).toFloat()
        val end = left + url.width - url.compoundPaddingRight - size
        fun at(kept: Int) = minOf(end, left + url.compoundPaddingLeft - url.scrollX + url.paint.measureText(text, 0, kept))
        duck.translationY = (fieldAt[1] - rootAt[1] + (url.height - size) / 2 - dp(2)).toFloat()
        quack.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED)
        quack.translationY = duck.translationY + (size - quack.measuredHeight) / 2
        // The hint would show through the duck once the field is empty.
        val hint = url.hint
        url.hint = null

        val walk = minOf(2400L, 900L + text.length * 45L)
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = walk
            interpolator = LinearInterpolator()
            addUpdateListener {
                val t = it.animatedFraction
                val kept = (text.length * (1 - t)).roundToInt()
                url.setText(text.substring(0, kept))
                url.setSelection(kept)
                duck.translationX = at(kept)
                duck.rotation = 9f * sin(t * walk / 220f * PI.toFloat())
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    url.setText("")
                    duck.rotation = 0f
                    quack.translationX = duck.translationX + size + dp(4)
                    quack.animate().alpha(1f).setDuration(160).start()
                    duck.animate().translationYBy(-dpf(5)).setDuration(150)
                        .withEndAction { duck.animate().translationYBy(dpf(5)).setDuration(150).start() }.start()
                    root.postDelayed({
                        root.removeView(duck)
                        root.removeView(quack)
                        url.hint = hint
                        duckBusy = false
                    }, 1100)
                }
            })
            start()
        }
    }

    // ── Menu ───────────────────────────────────────────────────────────────

    private fun showMenu() {
        val tab = browser.current ?: return
        hideKeyboard()
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
        }
        // Scrolls when it's taller than the room on screen (a small phone, landscape).
        val scroller = ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            addView(panel)
        }
        val popup = PopupWindow(scroller, dp(264), ViewGroup.LayoutParams.WRAP_CONTENT, true).apply {
            setBackgroundDrawable(rounded(palette.box, dpf(14), hairline, palette.line))
            elevation = dpf(8)
        }
        fun run(action: () -> Unit) {
            popup.dismiss()
            action()
        }

        // Quick actions as round buttons (on tablets, forward and reload are in the toolbar).
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val loading = tab.progress < 100
        fun quick(icon: Int, label: String, enabled: Boolean = true, action: () -> Unit) =
            row.addView(iconButton(icon, label) { run(action) }.apply { enable(this, enabled) }, LinearLayout.LayoutParams(0, dp(44), 1f))
        if (!tablet) {
            quick(R.drawable.ic_forward, "Forward", tab.canGoForward) { tab.session.goForward() }
            quick(if (loading) R.drawable.ic_stop else R.drawable.ic_reload, if (loading) "Stop" else "Reload") {
                if (loading) tab.session.stop() else tab.session.reload()
            }
        }
        val marked = browser.isWebPage(tab) && app.library.isBookmarked(tab.url)
        quick(if (marked) R.drawable.ic_star_filled else R.drawable.ic_star, if (marked) "Remove bookmark" else "Bookmark this page", browser.isWebPage(tab)) {
            val now = browser.toggleBookmark(tab)
            Toast.makeText(this, if (now) "Bookmarked" else "Bookmark removed", Toast.LENGTH_SHORT).show()
        }
        if (marked) (row.getChildAt(row.childCount - 1) as ImageButton).imageTintList = ColorStateList.valueOf(palette.accent)
        quick(R.drawable.ic_share, "Share", !browser.isDerpPage(tab)) { share(tab.url, tab.title) }
        quick(R.drawable.ic_plus, "New tab") { browser.newTab(null) }
        panel.addView(row)

        fun divider() = panel.addView(View(this).apply { setBackgroundColor(palette.line) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, hairline).apply {
                setMargins(dp(8), dp(5), dp(8), dp(5))
            })
        fun item(label: String, detail: String? = null, action: () -> Unit) {
            val line = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                contentDescription = label
                setPadding(dp(14), 0, dp(14), 0)
                background = rowRipple(palette.press, dpf(8))
                isClickable = true
                setOnClickListener { run(action) }
            }
            line.addView(TextView(this).apply {
                text = label
                textSize = 15f
                setTextColor(palette.text)
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            if (detail != null) {
                line.addView(TextView(this).apply {
                    text = detail
                    textSize = 14f
                    setTextColor(palette.dim)
                })
            }
            panel.addView(line, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(44)))
        }
        divider()
        item("New private tab") { browser.newTab(null, private = true) }
        item("Desktop site", if (tab.desktop) "On" else "Off") { browser.toggleDesktop(tab) }
        item("Your dork") { browser.openDork() }
        divider()
        item("Bookmarks") { browser.openPage("bookmarks.html") }
        item("History") { browser.openPage("history.html") }
        item("Passwords") { browser.openPage("passwords.html") }
        item("Import data") { browser.openPage("import.html") }
        divider()
        item("Search engine", browser.engine.label) { pickEngine() }
        item("Duck mode", if (duckMode) "On" else "Off") {
            duckMode = !duckMode
            Toast.makeText(this, if (duckMode) "Duck mode is on. Keep an eye on the address bar…" else "Duck mode is off", Toast.LENGTH_SHORT).show()
        }
        item("Clear browsing data") { confirmClear() }
        divider()
        item("Check for updates") { Updater.check(this, manual = true) }
        item("About Derp") { about() }

        panel.measure(
            View.MeasureSpec.makeMeasureSpec(dp(264), View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val room = if (tablet) {
            val at = IntArray(2).also { menuButton.getLocationInWindow(it) }
            root.height - at[1] - menuButton.height - bottomInset - dp(12)
        } else {
            root.height - bar.height - bottomInset - topInset - dp(20)
        }
        if (panel.measuredHeight > room) popup.height = room
        if (tablet) {
            popup.showAsDropDown(menuButton, 0, dp(4), Gravity.END)
        } else {
            popup.showAtLocation(root, Gravity.BOTTOM or Gravity.END, dp(8), bar.height + bottomInset + dp(6))
        }
    }

    private fun pickEngine() {
        val engines = Engine.values()
        AlertDialog.Builder(this)
            .setTitle("Search engine")
            .setSingleChoiceItems(engines.map { it.label }.toTypedArray(), engines.indexOf(browser.engine)) { d, which ->
                browser.engine = engines[which]
                d.dismiss()
            }
            .show()
    }

    private fun confirmClear() {
        AlertDialog.Builder(this)
            .setTitle("Clear browsing data?")
            .setMessage("This deletes your history, cookies, site data and the cache, so you'll be signed out of websites. Your tabs, bookmarks, passwords and your dork stay.")
            .setPositiveButton("Clear") { _, _ ->
                app.runtime.storageController.clearData(StorageController.ClearFlags.ALL)
                app.library.clearHistory()
                Toast.makeText(this, "Browsing data cleared", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun about() {
        val engine = listOf("MOZILLA_VERSION", "MOZ_APP_VERSION").firstNotNullOfOrNull { field ->
            runCatching { Class.forName("org.mozilla.geckoview.BuildConfig").getField(field).get(null) as String }.getOrNull()
        }
        AlertDialog.Builder(this)
            .setTitle("Derp ${BuildConfig.VERSION_NAME}")
            .setMessage(
                "A fast, fluid browser with a goofy streak.\n\n" +
                    "Engine: GeckoView ${engine ?: ""}, Mozilla's Firefox engine for apps.\n" +
                    "Tracking protection: strict, with tracking parameters stripped from links. No telemetry.\n\n" +
                    "Derp is open source and isn't affiliated with Mozilla.",
            )
            .setPositiveButton("Website") { _, _ -> browser.newTab("https://kingbennet800.github.io/derp/") }
            .setNegativeButton("Close", null)
            .show()
    }

    private var updateOffer: AlertDialog? = null

    fun offerUpdate(version: String, later: () -> Unit, install: () -> Unit) {
        if (updateOffer?.isShowing == true) return
        updateOffer = AlertDialog.Builder(this)
            .setTitle("Derp $version is out")
            .setMessage("Update now? Your tabs, bookmarks, passwords and your dork stay.")
            .setPositiveButton("Update") { _, _ -> install() }
            .setNegativeButton("Later") { _, _ -> later() }
            .show()
    }

    private fun installStatus(intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                confirm?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            }
            PackageInstaller.STATUS_SUCCESS -> Unit
            else -> Toast.makeText(this, "The update wasn't installed", Toast.LENGTH_SHORT).show()
        }
    }

    // ── Tabs view ──────────────────────────────────────────────────────────

    private fun openTabs() {
        hideKeyboard()
        url.clearFocus()
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Palette.of(this@MainActivity, false).frame)
            isClickable = true
            alpha = 0f
            translationY = dpf(24)
        }
        tabsPanel = panel
        root.addView(panel, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        fillTabs(panel)
        root.requestApplyInsets()
        panel.animate().alpha(1f).translationY(0f).setDuration(180).start()
    }

    private fun closeTabs() {
        val panel = tabsPanel ?: return
        tabsPanel = null
        panel.animate().alpha(0f).translationY(dpf(24)).setDuration(140).withEndAction { root.removeView(panel) }.start()
    }

    private fun fillTabs(panel: LinearLayout) {
        val base = Palette.of(this, false)
        panel.removeAllViews()
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(22), dp(14), dp(10), dp(8))
        }
        header.addView(TextView(this).apply {
            text = "Tabs"
            textSize = 22f
            typeface = MEDIUM
            setTextColor(base.text)
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(iconButton(R.drawable.ic_mask, "New private tab", base) {
            closeTabs()
            browser.newTab(null, private = true)
        }, LinearLayout.LayoutParams(dp(44), dp(44)))
        header.addView(iconButton(R.drawable.ic_plus, "Open a new tab", base) {
            closeTabs()
            browser.newTab(null)
        }, LinearLayout.LayoutParams(dp(44), dp(44)))
        panel.addView(header)

        // Like desktop's tabs: the one in front is a card the toolbar's color, the rest sit flat.
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(2), dp(10), dp(20))
        }
        for (tab in browser.tabs) {
            val selected = tab === browser.current
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = if (selected) rounded(base.toolbar, dpf(12), hairline, base.line) else null
                foreground = rowRipple(base.press, dpf(12))
                setPadding(dp(14), dp(10), dp(4), dp(10))
                setOnClickListener {
                    browser.select(tab)
                    closeTabs()
                }
            }
            card.addView(ImageView(this).apply { tabIcon(this, tab, base) }, LinearLayout.LayoutParams(dp(18), dp(18)))
            val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            words.addView(TextView(this).apply {
                text = tab.title.ifBlank { browser.display(tab).ifBlank { "New tab" } }
                textSize = 15f
                if (selected) typeface = MEDIUM
                setTextColor(base.text)
                setSingleLine()
                ellipsize = TextUtils.TruncateAt.END
            })
            words.addView(TextView(this).apply {
                text = listOfNotNull(if (tab.private) "Private" else null, browser.display(tab).ifBlank { null }).joinToString(" · ").ifBlank { "Derp" }
                textSize = 13f
                setTextColor(base.dim)
                setSingleLine()
                ellipsize = TextUtils.TruncateAt.END
            })
            card.addView(words, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(14) })
            card.addView(iconButton(R.drawable.ic_close, "Close tab", base) { browser.close(tab) }, LinearLayout.LayoutParams(dp(44), dp(44)))
            list.addView(card, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                bottomMargin = dp(4)
            })
        }
        panel.addView(ScrollView(this).apply { addView(list) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
    }

    // ── Pages asking for things ────────────────────────────────────────────

    fun onFullScreen(on: Boolean) {
        fullScreen = on
        bar.visibility = if (on) View.GONE else View.VISIBLE
        progress.visibility = if (on) View.GONE else View.VISIBLE
        strip?.visibility = if (on) View.GONE else View.VISIBLE
        if (Build.VERSION.SDK_INT >= 30) {
            window.insetsController?.let {
                if (on) {
                    it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    it.hide(WindowInsets.Type.systemBars())
                } else {
                    it.show(WindowInsets.Type.systemBars())
                }
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (on) {
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            } else {
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            }
            systemBarIcons(palette.dark)
        }
        root.requestApplyInsets()
    }

    /** Long-press on a link or image. */
    fun contextMenu(tab: Tab, element: GeckoSession.ContentDelegate.ContextElement) {
        val link = element.linkUri
        val image = element.srcUri?.takeIf { element.type == GeckoSession.ContentDelegate.ContextElement.TYPE_IMAGE }
        val actions = mutableListOf<Pair<String, () -> Unit>>()
        fun add(label: String, action: () -> Unit) {
            actions += label to action
        }
        if (link != null) {
            add("Open in new tab") {
                browser.newTab(link, private = tab.private, select = false, parent = tab)
                Toast.makeText(this, "Opened in a new tab", Toast.LENGTH_SHORT).show()
            }
            if (!tab.private) add("Open in private tab") { browser.newTab(link, private = true, parent = tab) }
            add("Copy link") { copy(link) }
            add("Share link") { share(link, element.title) }
        }
        if (image != null) {
            add("Open image in new tab") { browser.newTab(image, private = tab.private, parent = tab) }
            add("Copy image address") { copy(image) }
        }
        if (actions.isEmpty()) return
        AlertDialog.Builder(this)
            .setTitle(link ?: image)
            .setItems(actions.map { it.first }.toTypedArray()) { _, which -> actions[which].second() }
            .show()
    }

    fun download(response: WebResponse) {
        Downloads.save(this, response) { name ->
            Toast.makeText(this, if (name != null) "Saved $name to Downloads" else "The download didn't finish", Toast.LENGTH_SHORT).show()
        }
    }

    /** mailto:, tel:, intent: and other apps' links. */
    fun openExternal(uri: String, tab: Tab) {
        val intent = if (uri.startsWith("intent:")) {
            runCatching { Intent.parseUri(uri, Intent.URI_INTENT_SCHEME) }.getOrNull()
        } else {
            Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        } ?: return
        intent.addCategory(Intent.CATEGORY_BROWSABLE)
        intent.component = null
        intent.selector = null
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            val fallback = intent.getStringExtra("browser_fallback_url")
            if (fallback != null && (fallback.startsWith("https://") || fallback.startsWith("http://"))) {
                browser.load(tab, fallback)
            } else {
                Toast.makeText(this, "No app here can open that link", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun requestAndroidPermissions(permissions: List<String>, callback: GeckoSession.PermissionDelegate.Callback) {
        if (permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) return callback.grant()
        permissionCallback = callback
        requestPermissions(permissions.toTypedArray(), REQUEST_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_PERMISSIONS) return
        val callback = permissionCallback ?: return
        permissionCallback = null
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) callback.grant() else callback.reject()
    }

    fun pickFiles(intent: Intent, done: (Int, Intent?) -> Unit) {
        filesCallback = done
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(Intent.createChooser(intent, null), REQUEST_FILES)
        } catch (e: ActivityNotFoundException) {
            filesCallback = null
            done(RESULT_CANCELED, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_FILES -> {
                filesCallback?.invoke(resultCode, data)
                filesCallback = null
            }
            REQUEST_IMPORT -> {
                importDone?.invoke(resultCode, data)
                importDone = null
            }
            REQUEST_UNLOCK -> {
                val ok = resultCode == RESULT_OK
                if (ok) unlockedUntil = System.currentTimeMillis() + 2 * 60 * 1000
                unlockDone?.invoke(ok)
                unlockDone = null
            }
        }
    }

    // ── Import data and passwords ──────────────────────────────────────────

    private var importDone: ((Int, Intent?) -> Unit)? = null
    private var unlockDone: ((Boolean) -> Unit)? = null
    private var unlockedUntil = 0L

    /** Import data: pick a bookmarks (.html) or passwords (.csv) file another
     * browser exported, and add what's in it. */
    fun importFile(kind: String, done: (JSONObject) -> Unit) {
        val passwords = kind == "passwords"
        importDone = { code, data ->
            val uri = data?.data
            if (code != RESULT_OK || uri == null) {
                done(JSONObject().put("ok", true).put("cancelled", true))
            } else {
                Thread {
                    val reply = runCatching {
                        val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                        check(bytes.size < 50 * 1024 * 1024) { "That file is too big" }
                        val text = bytes.toString(Charsets.UTF_8)
                        if (passwords) {
                            val logins = Imports.logins(text)
                            val (added, updated) = app.logins.import(logins)
                            JSONObject().put("ok", true).put("found", logins.size).put("added", added).put("updated", updated)
                        } else {
                            val marks = Imports.bookmarks(text)
                            JSONObject().put("ok", true).put("found", marks.size).put("added", app.library.importBookmarks(marks))
                        }
                    }.getOrElse { JSONObject().put("ok", false).put("error", it.message ?: it.toString()) }
                    runOnUiThread { done(reply) }
                }.start()
            }
        }
        val types = if (passwords) {
            arrayOf("text/csv", "text/comma-separated-values", "text/plain", "application/csv", "application/vnd.ms-excel", "application/octet-stream")
        } else {
            arrayOf("text/html", "application/xhtml+xml", "text/plain", "application/octet-stream")
        }
        val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
            .putExtra(Intent.EXTRA_MIME_TYPES, types)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(pick, REQUEST_IMPORT)
        } catch (e: ActivityNotFoundException) {
            importDone = null
            done(JSONObject().put("ok", false).put("error", "No app here can pick files"))
        }
    }

    /** Your screen lock, before showing or copying a saved password (good for
     * two minutes). Phones without a screen lock skip this. */
    fun unlock(done: (Boolean) -> Unit) {
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (keyguard == null || !keyguard.isDeviceSecure || System.currentTimeMillis() < unlockedUntil) return done(true)
        @Suppress("DEPRECATION")
        val confirm = keyguard.createConfirmDeviceCredentialIntent("Your passwords", "Confirm it’s you to see your saved passwords")
            ?: return done(true)
        unlockDone = done
        @Suppress("DEPRECATION")
        startActivityForResult(confirm, REQUEST_UNLOCK)
    }

    /** Copies a password, marked sensitive so Android doesn't show it in previews. */
    fun copySecret(text: String) {
        val clip = ClipData.newPlainText("Password", text)
        clip.description.extras = PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
        getSystemService(ClipboardManager::class.java)?.setPrimaryClip(clip)
        if (Build.VERSION.SDK_INT < 33) Toast.makeText(this, "Password copied", Toast.LENGTH_SHORT).show()
    }

    fun share(text: String, title: String? = null) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        if (!title.isNullOrBlank()) send.putExtra(Intent.EXTRA_SUBJECT, title)
        startActivity(Intent.createChooser(send, null))
    }

    private fun copy(text: String) {
        getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Link", text))
        if (Build.VERSION.SDK_INT < 33) Toast.makeText(this, "Copied", Toast.LENGTH_SHORT).show()
    }

    companion object {
        private const val REQUEST_PERMISSIONS = 1
        private const val REQUEST_FILES = 2
        private const val REQUEST_IMPORT = 3
        private const val REQUEST_UNLOCK = 4
        /** Private tabs' mask on light backgrounds (their own accent is for dark ones). */
        private val VIOLET = Color.parseColor("#7C5CF5")
    }
}
