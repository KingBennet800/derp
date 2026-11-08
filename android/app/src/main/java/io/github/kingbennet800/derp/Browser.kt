package io.github.kingbennet800.derp

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import org.mozilla.geckoview.AllowOrDeny
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.MediaSession
import org.mozilla.geckoview.WebExtension
import org.mozilla.geckoview.WebResponse

class Tab(val private: Boolean) {
    val session = GeckoSession(GeckoSessionSettings.Builder().usePrivateMode(private).build())
    var url = ""
    var title = ""
    var progress = 100
    var canGoBack = false
    var canGoForward = false
    var desktop = false

    /** Restored tabs load the first time you look at them. */
    var pending: String? = null

    /** The page's side of Derp's built-in extension (page.js), while the page
     * is open: whether it reads well in Reader view, and its icon. */
    var page: WebExtension.Port? = null
    var pageUrl = ""
    var readable = false
    var icon: String? = null

    /** What Reader view shows (the page's address and HTML), once you open it. */
    var reading: JSONObject? = null

    /** Memory Saver: when you last looked at this tab, whether it's playing
     * something, and while it's asleep, its pages and history. */
    var seen = System.currentTimeMillis()
    var playing = false
    var sleeping: GeckoSession.SessionState? = null
    val asleep get() = sleeping != null
}

// Doodle's DuckDuckGo settings: links and addresses in Derp's colors, light
// and dark (DuckDuckGo stays light unless asked). Desktop Derp's are in
// config/policies.json.
internal const val DOODLE_LIGHT = "k9=2f6feb&kaa=7a52c7&kx=0f8a74"
internal const val DOODLE_DARK = "kae=d&k9=86b1ff&kaa=a98bf0&kx=34c6a0"

enum class Engine(val label: String, val template: String) {
    DOODLE("Doodle", "https://duckduckgo.com/?q=%s&$DOODLE_LIGHT&kt=system-ui&ka=system-ui"),
    GOOGLE("Google", "https://www.google.com/search?q=%s"),
    DUCKDUCKGO("DuckDuckGo", "https://duckduckgo.com/?q=%s"),
    BING("Bing", "https://www.bing.com/search?q=%s"),
    STARTPAGE("Startpage", "https://www.startpage.com/do/search?q=%s"),
    ECOSIA("Ecosia", "https://www.ecosia.org/search?q=%s"),
    ;

    /** A search for [encoded] (already URL-encoded); Doodle's results are dark while Derp is. */
    fun search(encoded: String, dark: Boolean): String {
        val url = template.replace("%s", encoded)
        return if (this == DOODLE && dark) url.replace(DOODLE_LIGHT, DOODLE_DARK) else url
    }

    /** The words searched for, if [url] is a search on this engine. */
    fun terms(url: String): String? {
        val start = template.substringBefore("%s")
        if (!url.startsWith(start)) return null
        return runCatching { Uri.parse(url).getQueryParameter("q") }.getOrNull()?.trim()?.ifBlank { null }
    }
}

/** Derp's tabs and pages. Lives as long as the app, so tabs survive the
 * window being rebuilt; the current MainActivity draws them. */
class Browser(val app: DerpApp) {
    val tabs = mutableListOf<Tab>()
    var current: Tab? = null
        private set
    var ui: MainActivity? = null
    private var pagesBase: String? = null
    private var pages: WebExtension? = null
    private var started = false
    private val prefs = app.getSharedPreferences("browser", Context.MODE_PRIVATE)
    private val messages = Messages()

    var engine: Engine
        get() = runCatching { Engine.valueOf(prefs.getString("engine", "DOODLE")!!) }.getOrDefault(Engine.DOODLE)
        set(value) = prefs.edit().putString("engine", value.name).apply()

    // ── Starting ───────────────────────────────────────────────────────────

    /** First start: restore your tabs (or open a new tab), open what another
     * app asked for, and, until you've made your dork, open the dork editor. */
    fun start(intent: Intent?) {
        if (started) {
            // The window was rebuilt (say, for dark mode): just show the tab again.
            (current ?: tabs.lastOrNull())?.let { select(it) }
            return
        }
        started = true
        app.blocker.start()
        restore()
        app.withPages { extension ->
            pages = extension
            pagesBase = extension.metaData.baseUrl
            tabs.forEach { it.session.webExtensionController.setMessageDelegate(extension, messages, "derp") }
            extension.setMessageDelegate(messages, "derp")
            val welcome = !app.dork.made && intent?.data == null
            val tab = current
            // (A fresh tab still waiting for its new tab page; it may show about:blank.)
            if (welcome && tab != null && tab.pending == "derp:newtab.html") {
                tab.pending = null
                load(tab, extension.metaData.baseUrl + "dork.html?welcome=1")
            } else {
                // Tabs restored or opened before Derp's pages were ready.
                tab?.pending?.let { saved -> tab.pending = null; load(tab, resolve(saved)) }
                if (welcome) openWelcome()
            }
        }
        if (!handle(intent) && tabs.isEmpty()) newTab(null)
        (current ?: tabs.lastOrNull())?.let { select(it) }
    }

    /** A link or search from another app. */
    fun handle(intent: Intent?): Boolean {
        intent ?: return false
        val url = when (intent.action) {
            Intent.ACTION_VIEW -> intent.dataString
            Intent.ACTION_WEB_SEARCH -> intent.getStringExtra("query")?.let { toUrl(it) }
            else -> null
        } ?: return false
        newTab(url)
        return true
    }

    private fun openWelcome() {
        val base = pagesBase ?: return
        val welcome = tabs.firstOrNull { it.url.startsWith(base + "dork.html") }
        if (welcome != null) {
            select(welcome)
            load(welcome, base + "dork.html?welcome=1")
        } else {
            newTab(base + "dork.html?welcome=1")
        }
    }

    // ── Tabs ───────────────────────────────────────────────────────────────

    fun newTab(url: String?, private: Boolean = false, select: Boolean = true, parent: Tab? = null, open: Boolean = true): Tab {
        val tab = Tab(private)
        attach(tab)
        if (open) tab.session.open(app.runtime)
        val index = parent?.let { tabs.indexOf(it) + 1 }?.takeIf { it > 0 } ?: tabs.size
        tabs.add(index, tab)
        if (open) {
            if (url != null) load(tab, url) else home(tab)
        }
        if (select) select(tab)
        ui?.onTabsChanged()
        save()
        // A fresh new tab (not a link's): Peekaboo might happen.
        if (open && url == null && select) ui?.onBlankTab()
        return tab
    }

    fun select(tab: Tab) {
        val old = current
        val now = System.currentTimeMillis()
        if (old !== tab) {
            old?.session?.setActive(false)
            old?.seen = now
        }
        current = tab
        tab.seen = now
        if (!tab.session.isOpen) tab.session.open(app.runtime)
        wake(tab)
        tab.pending?.let { saved ->
            if (!saved.startsWith("derp:") || pagesBase != null) {
                tab.pending = null
                load(tab, resolve(saved))
            }
        }
        tab.session.setActive(true)
        ui?.showTab(tab)
        save()
    }

    fun close(tab: Tab) {
        val index = tabs.indexOf(tab)
        if (index < 0) return
        tabs.removeAt(index)
        if (current === tab) {
            current = null
            ui?.detachTab()
            val next = tabs.getOrNull(index) ?: tabs.getOrNull(index - 1)
            if (next != null) select(next) else newTab(null)
        }
        tab.session.close()
        ui?.onTabsChanged()
        save()
    }

    fun load(tab: Tab, url: String) {
        tab.url = url
        tab.session.loadUri(url)
        changed(tab)
    }

    fun home(tab: Tab) {
        val base = pagesBase
        if (base != null) load(tab, base + "newtab.html") else tab.pending = "derp:newtab.html"
    }

    fun openDork() = openPage("dork.html")

    /** One of Derp's own pages (bookmarks.html, history.html…) in the current tab. */
    fun openPage(name: String) {
        val tab = current ?: return
        app.withPages { load(tab, it.metaData.baseUrl + name) }
    }

    /** Bookmarks the current page, or removes its bookmark; true if it's bookmarked now. */
    fun toggleBookmark(tab: Tab): Boolean {
        val url = tab.url
        return if (app.library.isBookmarked(url)) {
            app.library.unbookmark(url)
            false
        } else {
            app.library.bookmark(url, tab.title.ifBlank { display(tab) })
            true
        }
    }

    /** Pages worth remembering in history and bookmarks: websites, not Derp's own. */
    fun isWebPage(tab: Tab) = Imports.isWeb(tab.url) && !isDerpPage(tab)

    fun toggleDesktop(tab: Tab) {
        tab.desktop = !tab.desktop
        tab.session.settings.userAgentMode =
            if (tab.desktop) GeckoSessionSettings.USER_AGENT_MODE_DESKTOP else GeckoSessionSettings.USER_AGENT_MODE_MOBILE
        tab.session.settings.viewportMode =
            if (tab.desktop) GeckoSessionSettings.VIEWPORT_MODE_DESKTOP else GeckoSessionSettings.VIEWPORT_MODE_MOBILE
        tab.session.reload()
    }

    /** Text from the address bar: a web address, or a search. */
    fun toUrl(input: String): String {
        val text = input.trim()
        val scheme = Regex("^(https?|about|file|data|view-source|moz-extension):", RegexOption.IGNORE_CASE)
        return when {
            scheme.containsMatchIn(text) -> text
            !text.contains(' ') && Regex("^localhost(:\\d+)?(/.*)?$").matches(text) -> "http://$text"
            !text.contains(' ') && Regex("^[^/\\s]+\\.[a-zA-Z]{2,}(:\\d+)?(/.*)?$").matches(text) -> "https://$text"
            else -> engine.search(Uri.encode(text), app.dark)
        }
    }

    /** What the address bar shows: the site's name, what you searched for, or
     * nothing on Derp's own pages. */
    fun display(tab: Tab): String {
        val url = tab.pending ?: tab.url
        if (url.isBlank() || url.startsWith("derp:")) return ""
        if (isReader(tab)) return tab.reading?.optString("url")?.let { host(it) }.orEmpty()
        pagesBase?.let { if (url.startsWith(it)) return "" }
        engine.terms(url)?.let { return it }
        return host(url) ?: url
    }

    private fun host(url: String) = runCatching { Uri.parse(url).host?.removePrefix("www.") }.getOrNull()

    /** The full address, or what you searched for, for editing. */
    fun address(tab: Tab): String {
        val url = tab.pending ?: tab.url
        pagesBase?.let { if (url.startsWith(it)) return "" }
        return if (url.startsWith("derp:")) "" else engine.terms(url) ?: url
    }

    fun isDerpPage(tab: Tab) = pagesBase?.let { tab.url.startsWith(it) } ?: false

    private fun changed(tab: Tab) = ui?.onTabChanged(tab)

    // ── Restoring tabs ─────────────────────────────────────────────────────

    /** Your (non-private) tabs, saved so they come back next time. Derp's own
     * pages are saved as derp:<page>, since their address can change. */
    fun save() {
        val kept = tabs.filter { !it.private }
        val list = JSONArray()
        kept.forEach { list.put(saved(if (isReader(it)) it.reading?.optString("url").orEmpty() else it.pending ?: it.url)) }
        prefs.edit()
            .putString("tabs", list.toString())
            .putInt("current", kept.indexOf(current).coerceAtLeast(0))
            .apply()
    }

    private fun restore() {
        val list = runCatching { JSONArray(prefs.getString("tabs", "[]")) }.getOrNull() ?: return
        for (i in 0 until list.length()) {
            val tab = Tab(false)
            attach(tab)
            tab.pending = list.optString(i).ifBlank { "derp:newtab.html" }
            tabs += tab
        }
        tabs.getOrNull(prefs.getInt("current", 0))?.let { select(it) }
    }

    private fun saved(url: String): String {
        val base = pagesBase
        return when {
            url.isBlank() -> "derp:newtab.html"
            base != null && url.startsWith(base) -> "derp:" + url.removePrefix(base).substringBefore('?')
            else -> url
        }
    }

    private fun resolve(saved: String): String =
        if (saved.startsWith("derp:")) (pagesBase ?: "") + saved.removePrefix("derp:") else saved

    // ── Each tab's engine callbacks ────────────────────────────────────────

    private fun attach(tab: Tab) {
        val session = tab.session
        session.navigationDelegate = Navigation(tab)
        session.historyDelegate = Visits(tab)
        session.progressDelegate = Progress(tab)
        session.contentDelegate = Content(tab)
        session.permissionDelegate = Permissions(this)
        session.promptDelegate = Prompts(this)
        session.mediaSessionDelegate = Media(tab)
        pages?.let { session.webExtensionController.setMessageDelegate(it, messages, "derp") }
    }

    /** Whether a tab is playing something (Memory Saver leaves those awake). */
    private inner class Media(val tab: Tab) : MediaSession.Delegate {
        override fun onPlay(session: GeckoSession, mediaSession: MediaSession) {
            tab.playing = true
        }

        override fun onPause(session: GeckoSession, mediaSession: MediaSession) {
            tab.playing = false
        }

        override fun onStop(session: GeckoSession, mediaSession: MediaSession) {
            tab.playing = false
        }

        override fun onDeactivated(session: GeckoSession, mediaSession: MediaSession) {
            tab.playing = false
        }
    }

    // ── Memory Saver ───────────────────────────────────────────────────────

    var memorySaver: Boolean
        get() = prefs.getBoolean("memorySaver", true)
        set(value) = prefs.edit().putBoolean("memorySaver", value).apply()

    /** Memory Saver: tabs you haven't looked at for half an hour (or, when
     * Android is short of memory, all but the one you're on) fall asleep. Their
     * page is unloaded, and comes back, history and all, when you look at it.
     * Tabs playing something stay awake. */
    fun sleepIdleTabs(all: Boolean = false) {
        if (!memorySaver) return
        val idle = System.currentTimeMillis() - IDLE
        tabs.filter { it !== current && !it.asleep && !it.playing && it.pending == null && it.session.isOpen && (all || it.seen < idle) }
            .forEach { sleep(it) }
    }

    private fun sleep(tab: Tab) {
        tab.session.saveState().accept({ state: GeckoSession.SessionState? ->
            if (state == null || tab === current || tab !in tabs || tab.asleep) return@accept
            tab.sleeping = state
            tab.page = null
            tab.readable = false
            tab.session.close()
            Log.i("Derp", "Memory Saver: a tab fell asleep")
            ui?.onTabsChanged()
        }, { error -> Log.w("Derp", "Memory Saver: couldn't save a tab", error) })
    }

    /** A sleeping tab you look at again wakes up where it was. */
    private fun wake(tab: Tab) {
        val state = tab.sleeping ?: return
        tab.sleeping = null
        pages?.let { tab.session.webExtensionController.setMessageDelegate(it, messages, "derp") }
        tab.session.restoreState(state)
        Log.i("Derp", "Memory Saver: a tab woke up")
        ui?.onTabsChanged()
    }

    // ── Reader view ────────────────────────────────────────────────────────

    /** Whether the page in [tab] reads well as an article. */
    fun canRead(tab: Tab) = tab.readable && tab.page != null && tab.pageUrl == tab.url

    /** Asks the page for itself; Reader view opens when it answers. */
    fun openReader(tab: Tab) {
        if (canRead(tab)) tab.page?.postMessage(JSONObject().put("type", "reader"))
    }

    fun isReader(tab: Tab) = pagesBase?.let { tab.url.startsWith(it + "reader.html") } ?: false

    private inner class Navigation(val tab: Tab) : GeckoSession.NavigationDelegate {
        override fun onLocationChange(
            session: GeckoSession,
            url: String?,
            perms: MutableList<GeckoSession.PermissionDelegate.ContentPermission>,
            hasUserGesture: Boolean,
        ) {
            tab.url = url.orEmpty()
            changed(tab)
            save()
        }

        override fun onCanGoBack(session: GeckoSession, canGoBack: Boolean) {
            tab.canGoBack = canGoBack
            changed(tab)
        }

        override fun onCanGoForward(session: GeckoSession, canGoForward: Boolean) {
            tab.canGoForward = canGoForward
            changed(tab)
        }

        /** Links that open a new window open a new tab. */
        override fun onNewSession(session: GeckoSession, uri: String): GeckoResult<GeckoSession> {
            val child = newTab(null, private = tab.private, parent = tab, open = false)
            return GeckoResult.fromValue(child.session)
        }

        /** Other apps' links (mailto:, tel:, intent:…) go to those apps. */
        override fun onLoadRequest(
            session: GeckoSession,
            request: GeckoSession.NavigationDelegate.LoadRequest,
        ): GeckoResult<AllowOrDeny>? {
            val scheme = Uri.parse(request.uri).scheme?.lowercase() ?: return null
            if (scheme in WEB_SCHEMES) return null
            ui?.openExternal(request.uri, tab)
            return GeckoResult.fromValue(AllowOrDeny.DENY)
        }
    }

    /** History: the pages you go to, except in private tabs. */
    private inner class Visits(val tab: Tab) : GeckoSession.HistoryDelegate {
        override fun onVisited(session: GeckoSession, url: String, lastVisitedURL: String?, flags: Int): GeckoResult<Boolean>? {
            val skip = GeckoSession.HistoryDelegate.VISIT_REDIRECT_SOURCE or
                GeckoSession.HistoryDelegate.VISIT_REDIRECT_SOURCE_PERMANENT or
                GeckoSession.HistoryDelegate.VISIT_UNRECOVERABLE_ERROR
            val topLevel = flags and GeckoSession.HistoryDelegate.VISIT_TOP_LEVEL != 0
            if (tab.private || !topLevel || flags and skip != 0 || !Imports.isWeb(url)) return GeckoResult.fromValue(false)
            app.library.visit(url)
            return GeckoResult.fromValue(true)
        }
    }

    private inner class Progress(val tab: Tab) : GeckoSession.ProgressDelegate {
        override fun onPageStart(session: GeckoSession, url: String) {
            tab.progress = 5
            changed(tab)
        }

        override fun onProgressChange(session: GeckoSession, progress: Int) {
            tab.progress = progress
            changed(tab)
        }

        override fun onPageStop(session: GeckoSession, success: Boolean) {
            tab.progress = 100
            changed(tab)
        }
    }

    private inner class Content(val tab: Tab) : GeckoSession.ContentDelegate {
        override fun onTitleChange(session: GeckoSession, title: String?) {
            tab.title = title.orEmpty()
            if (!tab.private && Imports.isWeb(tab.url)) app.library.title(tab.url, tab.title)
            changed(tab)
        }

        override fun onFullScreen(session: GeckoSession, fullScreen: Boolean) {
            ui?.onFullScreen(fullScreen)
        }

        override fun onCloseRequest(session: GeckoSession) = close(tab)

        override fun onContextMenu(
            session: GeckoSession,
            screenX: Int,
            screenY: Int,
            element: GeckoSession.ContentDelegate.ContextElement,
        ) {
            ui?.contextMenu(tab, element)
        }

        override fun onExternalResponse(session: GeckoSession, response: WebResponse) {
            val activity = ui
            if (activity != null) activity.download(response) else response.body?.close()
        }

        override fun onCrash(session: GeckoSession) = recover(tab)

        override fun onKill(session: GeckoSession) = recover(tab)
    }

    /** A tab's page crashed: start it again where it was. */
    private fun recover(tab: Tab) {
        if (!tab.session.isOpen) tab.session.open(app.runtime)
        if (tab.url.isNotBlank()) tab.session.loadUri(tab.url)
        if (current === tab) ui?.showTab(tab)
    }

    // ── Messages from Derp's pages ─────────────────────────────────────────

    private inner class Messages : WebExtension.MessageDelegate {
        /** Answers go back as JSON text (GeckoView can't pass a JSONObject to a
         * page); pages.js parses it. */
        override fun onMessage(nativeApp: String, message: Any, sender: WebExtension.MessageSender): GeckoResult<Any> {
            val msg = message as? JSONObject
            // Only Derp's own pages ask for things; scripts in web pages talk over a port.
            if (msg == null || sender.environmentType != WebExtension.MessageSender.ENV_TYPE_EXTENSION) {
                return GeckoResult.fromValue(JSONObject().put("ok", false).toString())
            }
            val type = msg.optString("type")
            Log.d("Derp", "page asks: $type")
            later(type, msg)?.let { return it }
            val reply = JSONObject().put("ok", true)
            val tab = tabs.firstOrNull { it.session === sender.session }
            runCatching { answer(type, msg, reply, tab) }.onFailure { reply.put("ok", false).put("error", it.toString()) }
            return GeckoResult.fromValue(reply.toString())
        }

        /** A web page's script (page.js) says hello: it tells Derp about the
         * page, and hands the page over for Reader view when asked. */
        override fun onConnect(port: WebExtension.Port) {
            val tab = tabs.firstOrNull { it.session === port.sender.session }
            if (tab == null || port.sender.environmentType != WebExtension.MessageSender.ENV_TYPE_CONTENT_SCRIPT) {
                port.disconnect()
                return
            }
            port.setDelegate(object : WebExtension.PortDelegate {
                override fun onPortMessage(message: Any, port: WebExtension.Port) {
                    val msg = message as? JSONObject ?: return
                    when (msg.optString("type")) {
                        "page" -> {
                            tab.page = port
                            tab.pageUrl = msg.optString("url")
                            tab.readable = msg.optBoolean("readable")
                            tab.icon = msg.optString("icon").ifBlank { null }
                            if (tab.readable) Log.i("Derp", "Reader view: this page reads well")
                        }
                        "reader.page" -> {
                            val base = pagesBase ?: return
                            tab.reading = JSONObject().put("url", msg.optString("url")).put("html", msg.optString("html"))
                            load(tab, base + "reader.html")
                        }
                    }
                }

                override fun onDisconnect(port: WebExtension.Port) {
                    if (tab.page === port) {
                        tab.page = null
                        tab.readable = false
                    }
                }
            })
        }

        private fun answer(type: String, msg: JSONObject, reply: JSONObject, tab: Tab?) {
            val library = app.library
            when (type) {
                "getState" -> {
                    app.dork.json?.let { reply.put("dork", it) }
                    reply.put("made", app.dork.made).put("version", BuildConfig.VERSION_NAME).put("engine", engine.label)
                }
                "setDork" -> app.dork.save(msg.getJSONObject("dork"), msg.getString("svg"))
                "made" -> app.dork.made = true
                "focusUrl" -> ui?.focusUrl()
                "bookmarks.list" -> reply.put("items", library.bookmarks(msg.optString("query"), msg.optInt("limit", 500)))
                "bookmarks.remove" -> library.unbookmark(msg.getString("url"))
                "history.list" -> reply.put(
                    "items",
                    library.history(msg.optString("query"), msg.optLong("before", Long.MAX_VALUE), msg.optInt("limit", 200)),
                )
                "history.remove" -> library.forget(msg.getString("url"))
                "history.clear" -> library.clearHistory()
                "logins.list" -> reply.put("items", app.logins.list(msg.optString("query"))).put("save", app.logins.offerToSave)
                "logins.remove" -> app.logins.remove(msg.getString("guid"))
                "logins.offer" -> app.logins.offerToSave = msg.getBoolean("on")
                "reader.get" -> tab?.reading?.let { reply.put("url", it.optString("url")).put("html", it.optString("html")) }
                else -> reply.put("ok", false)
            }
            (reply.opt("items") as? JSONArray)?.let { Log.d("Derp", "$type -> ${it.length()}") }
        }

        /** Questions answered later: ones that need you (a file to pick, your screen lock). */
        private fun later(type: String, msg: JSONObject): GeckoResult<Any>? {
            if (type != "import" && type != "logins.reveal" && type != "logins.copy") return null
            val result = GeckoResult<Any>()
            val ui = ui ?: return GeckoResult.fromValue(JSONObject().put("ok", false).toString())
            fun done(reply: JSONObject) = result.complete(reply.toString())
            when (type) {
                "import" -> ui.importFile(msg.optString("kind")) { done(it) }
                else -> {
                    val guid = msg.optString("guid")
                    ui.unlock { unlocked ->
                        val password = if (unlocked) runCatching { app.logins.password(guid) }.getOrNull() else null
                        when {
                            !unlocked -> done(JSONObject().put("ok", false).put("cancelled", true))
                            password == null -> done(JSONObject().put("ok", false))
                            type == "logins.copy" -> {
                                ui.copySecret(password)
                                done(JSONObject().put("ok", true))
                            }
                            else -> done(JSONObject().put("ok", true).put("password", password))
                        }
                    }
                }
            }
            return result
        }
    }

    companion object {
        /** Memory Saver puts tabs to sleep after half an hour unseen. */
        private const val IDLE = 30 * 60 * 1000L
        val WEB_SCHEMES = setOf("http", "https", "about", "data", "blob", "file", "moz-extension", "resource", "javascript", "view-source")
    }
}
