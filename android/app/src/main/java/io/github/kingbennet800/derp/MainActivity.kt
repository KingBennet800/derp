package io.github.kingbennet800.derp

import android.app.Activity
import android.app.AlertDialog
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
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
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
import org.mozilla.geckoview.WebResponse

class MainActivity : Activity() {
    private val app get() = application as DerpApp
    private val browser get() = app.browser

    private lateinit var root: FrameLayout
    private lateinit var column: LinearLayout
    private lateinit var geckoView: GeckoView
    private lateinit var progress: ProgressLine
    private lateinit var bar: LinearLayout
    private lateinit var url: EditText
    private lateinit var tabCount: TextView
    private lateinit var avatar: ImageView
    private lateinit var menuButton: ImageButton
    private var tabsPanel: LinearLayout? = null
    private var palette = Palette.LIGHT
    private var fullScreen = false
    private var bottomInset = 0
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
        column.addView(geckoView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        progress = ProgressLine(this)
        column.addView(progress, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(3)))

        bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(6), dp(4), dp(6))
        }
        url = EditText(this).apply {
            id = View.generateViewId()
            contentDescription = "Address bar"
            setSingleLine()
            textSize = 15f
            setPadding(dp(18), 0, dp(14), 0)
            gravity = Gravity.CENTER_VERTICAL
            imeOptions = EditorInfo.IME_ACTION_GO or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            setSelectAllOnFocus(true)
            ellipsize = TextUtils.TruncateAt.END
            compoundDrawablePadding = dp(8)
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
            }
        }
        bar.addView(url, LinearLayout.LayoutParams(0, dp(44), 1f))

        tabCount = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
        }
        val tabsButton = FrameLayout(this).apply {
            contentDescription = "Tabs"
            isClickable = true
            setOnClickListener { if (tabsPanel == null) openTabs() else closeTabs() }
            addView(tabCount, FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER))
        }
        bar.addView(tabsButton, LinearLayout.LayoutParams(dp(46), dp(46)).apply { marginStart = dp(6) })

        avatar = ImageView(this).apply {
            contentDescription = "Your dork"
            scaleType = ImageView.ScaleType.CENTER_CROP
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) = outline.setOval(0, 0, view.width, view.height)
            }
            clipToOutline = true
        }
        val avatarButton = FrameLayout(this).apply {
            contentDescription = "Your dork"
            isClickable = true
            setOnClickListener {
                closeTabs()
                browser.openDork()
            }
            addView(avatar, FrameLayout.LayoutParams(dp(32), dp(32), Gravity.CENTER))
        }
        bar.addView(avatarButton, LinearLayout.LayoutParams(dp(44), dp(46)))

        menuButton = iconButton(R.drawable.ic_menu, "Menu") { showMenu() }
        bar.addView(menuButton, LinearLayout.LayoutParams(dp(44), dp(46)))

        column.addView(bar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
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
            bottomInset = sides[3]
            if (fullScreen) column.setPadding(0, 0, 0, 0) else column.setPadding(sides[0], sides[1], sides[2], sides[3])
            tabsPanel?.setPadding(sides[0], sides[1], sides[2], sides[3])
            if (Build.VERSION.SDK_INT >= 30) WindowInsets.CONSUMED else insets
        }
    }

    private fun iconButton(icon: Int, description: String, onClick: () -> Unit) = ImageButton(this).apply {
        setImageResource(icon)
        contentDescription = description
        background = null
        scaleType = ImageView.ScaleType.CENTER
        setOnClickListener { onClick() }
    }

    // ── Showing tabs ───────────────────────────────────────────────────────

    fun showTab(tab: Tab) {
        if (geckoView.session !== tab.session) {
            geckoView.releaseSession()
            geckoView.coverUntilFirstPaint(Palette.of(this, tab.private).toolbar)
            geckoView.setSession(tab.session)
        }
        render()
    }

    fun detachTab() {
        geckoView.releaseSession()
    }

    fun onTabsChanged() = render()

    fun onTabChanged(tab: Tab) {
        if (tab === browser.current) render()
        tabsPanel?.let { fillTabs(it) }
    }

    /** Everything in the toolbar, from the current tab. */
    private fun render() {
        val tab = browser.current
        palette = Palette.of(this, tab?.private == true)
        root.setBackgroundColor(palette.toolbar)
        bar.setBackgroundColor(palette.toolbar)
        progress.setColors(palette.line)
        progress.setProgress(tab?.progress ?: 100)

        url.background = rounded(palette.field, dpf(22))
        url.setTextColor(palette.text)
        url.setHintTextColor(palette.dim)
        url.hint = if (tab?.private == true) "Search privately" else "Search or enter address"
        if (!url.hasFocus()) url.setText(tab?.let { browser.display(it) } ?: "")
        val mask = if (tab?.private == true) getDrawable(R.drawable.ic_mask)?.mutate()?.apply {
            setTint(palette.accent)
            setBounds(0, 0, dp(18), dp(18))
        } else null
        url.setCompoundDrawablesRelative(mask, null, null, null)

        val count = browser.tabs.size
        tabCount.text = if (count > 99) ":D" else count.toString()
        tabCount.setTextColor(palette.text)
        tabCount.background = rounded(Color.TRANSPARENT, dpf(6), dp(2), palette.text)
        menuButton.imageTintList = ColorStateList.valueOf(palette.text)
        paintAvatar()
        systemBarIcons(palette.dark)
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
        if (text.isBlank()) return
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

    // ── Menu ───────────────────────────────────────────────────────────────

    private fun showMenu() {
        val tab = browser.current ?: return
        hideKeyboard()
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(6), 0, dp(8))
        }
        val popup = PopupWindow(panel, dp(268), ViewGroup.LayoutParams.WRAP_CONTENT, true).apply {
            setBackgroundDrawable(rounded(palette.card, dpf(20), 1, palette.line))
            elevation = dpf(14)
        }
        fun run(action: () -> Unit) {
            popup.dismiss()
            action()
        }

        // Forward, reload, share, new tab.
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(6), 0, dp(6), dp(4))
        }
        val loading = tab.progress < 100
        listOf<Pair<Triple<Int, String, Boolean>, () -> Unit>>(
            Triple(R.drawable.ic_forward, "Forward", tab.canGoForward) to { tab.session.goForward() },
            Triple(if (loading) R.drawable.ic_stop else R.drawable.ic_reload, if (loading) "Stop" else "Reload", true) to {
                if (loading) tab.session.stop() else tab.session.reload()
            },
            Triple(R.drawable.ic_share, "Share", !browser.isDerpPage(tab)) to { share(tab.url, tab.title) },
            Triple(R.drawable.ic_plus, "New tab", true) to { browser.newTab(null) },
        ).forEach { (spec, action) ->
            val (icon, label, enabled) = spec
            row.addView(iconButton(icon, label) { run(action) }.apply {
                isEnabled = enabled
                imageTintList = ColorStateList.valueOf(if (enabled) palette.text else palette.line)
            }, LinearLayout.LayoutParams(0, dp(48), 1f))
        }
        panel.addView(row)
        panel.addView(View(this).apply { setBackgroundColor(palette.line) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1))

        fun item(label: String, detail: String? = null, action: () -> Unit) {
            val line = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(20), 0, dp(20), 0)
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
            panel.addView(line, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(46)))
        }
        item("New private tab") { browser.newTab(null, private = true) }
        item("Desktop site", if (tab.desktop) "On" else "Off") { browser.toggleDesktop(tab) }
        item("Your dork") { browser.openDork() }
        item("Search engine", browser.engine.label) { pickEngine() }
        item("Clear browsing data") { confirmClear() }
        item("Check for updates") { Updater.check(this, manual = true) }
        item("About Derp") { about() }

        popup.showAtLocation(root, Gravity.BOTTOM or Gravity.END, dp(8), bar.height + bottomInset + dp(6))
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
            .setMessage("This deletes cookies, site data and the cache, so you'll be signed out of websites. Your tabs and your dork stay.")
            .setPositiveButton("Clear") { _, _ ->
                app.runtime.storageController.clearData(StorageController.ClearFlags.ALL)
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
                    "Tracking protection: strict. Cookie banners: rejected for you. No telemetry.\n\n" +
                    "Derp is open source and isn't affiliated with Mozilla.",
            )
            .setPositiveButton("Website") { _, _ -> browser.newTab("https://kingbennet800.github.io/derp/") }
            .setNegativeButton("Close", null)
            .show()
    }

    fun offerUpdate(version: String, install: () -> Unit) {
        AlertDialog.Builder(this)
            .setTitle("Derp $version is out")
            .setMessage("Update now? Your tabs and your dork stay.")
            .setPositiveButton("Update") { _, _ -> install() }
            .setNegativeButton("Later", null)
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
            setPadding(dp(20), dp(14), dp(12), dp(10))
        }
        header.addView(TextView(this).apply {
            text = "Tabs"
            textSize = 24f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(base.text)
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        fun pill(label: String, background: Int, foreground: Int, action: () -> Unit) = TextView(this).apply {
            text = label
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(foreground)
            this.background = rounded(background, dpf(20))
            setPadding(dp(16), 0, dp(16), 0)
            setOnClickListener {
                closeTabs()
                action()
            }
        }
        header.addView(pill("Private", Palette.PRIVATE.field, Palette.PRIVATE.text) { browser.newTab(null, private = true) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(40)).apply { marginEnd = dp(8) })
        header.addView(pill("+ New tab", base.accent, base.onAccent) { browser.newTab(null) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(40)))
        panel.addView(header)

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, dp(14), dp(20))
        }
        for (tab in browser.tabs) {
            val colors = if (tab.private) Palette.PRIVATE else base
            val selected = tab === browser.current
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = rounded(colors.card, dpf(16), if (selected) dp(2) else 1, if (selected) colors.accent else colors.line)
                setPadding(dp(16), dp(12), dp(4), dp(12))
                setOnClickListener {
                    browser.select(tab)
                    closeTabs()
                }
            }
            val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            words.addView(TextView(this).apply {
                text = tab.title.ifBlank { if (browser.display(tab).isBlank()) "New tab" else browser.display(tab) }
                textSize = 15f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.text)
                setSingleLine()
                ellipsize = TextUtils.TruncateAt.END
            })
            words.addView(TextView(this).apply {
                text = listOfNotNull(if (tab.private) "Private" else null, browser.display(tab).ifBlank { null }).joinToString(" · ").ifBlank { "Derp" }
                textSize = 13f
                setTextColor(colors.dim)
                setSingleLine()
                ellipsize = TextUtils.TruncateAt.END
            })
            card.addView(words, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            card.addView(iconButton(R.drawable.ic_close, "Close tab") { browser.close(tab) }.apply {
                imageTintList = ColorStateList.valueOf(colors.dim)
            }, LinearLayout.LayoutParams(dp(44), dp(44)))
            list.addView(card, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                bottomMargin = dp(10)
            })
        }
        panel.addView(ScrollView(this).apply { addView(list) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
    }

    // ── Pages asking for things ────────────────────────────────────────────

    fun onFullScreen(on: Boolean) {
        fullScreen = on
        bar.visibility = if (on) View.GONE else View.VISIBLE
        progress.visibility = if (on) View.GONE else View.VISIBLE
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
        if (requestCode == REQUEST_FILES) {
            filesCallback?.invoke(resultCode, data)
            filesCallback = null
        }
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
    }
}
