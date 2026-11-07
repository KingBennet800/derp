package io.github.kingbennet800.derp

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Intent
import android.net.Uri
import android.text.InputType
import android.widget.EditText
import android.widget.LinearLayout
import org.mozilla.geckoview.AllowOrDeny
import org.mozilla.geckoview.Autocomplete
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSession.PromptDelegate
import org.mozilla.geckoview.GeckoSession.PromptDelegate.PromptResponse
import java.util.Calendar
import java.util.Locale

/** Answers a page's question exactly once, however the dialog closes. The
 * answer is only worked out if it's the first: GeckoView throws if a prompt is
 * confirmed and then dismissed (a button press closes the dialog too). */
private class Reply<T>(private val result: GeckoResult<T> = GeckoResult()) {
    private var done = false
    fun send(value: () -> T) {
        if (!done) {
            done = true
            result.complete(value())
        }
    }
    val future: GeckoResult<T> get() = result
}

/** Pages' dialogs: alert/confirm/prompt, <select> menus, logins, file and
 * date pickers, "leave this page?", sharing, and saving passwords. */
class Prompts(private val browser: Browser) : PromptDelegate {
    private val activity: MainActivity? get() = browser.ui

    private fun dialog(a: Activity, title: String?, message: String?) =
        AlertDialog.Builder(a).apply {
            if (!title.isNullOrBlank()) setTitle(title)
            if (!message.isNullOrBlank()) setMessage(message)
        }

    override fun onAlertPrompt(session: GeckoSession, prompt: PromptDelegate.AlertPrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.dismiss())
        val reply = Reply<PromptResponse>()
        dialog(a, prompt.title, prompt.message)
            .setPositiveButton(android.R.string.ok, null)
            .setOnDismissListener { reply.send { prompt.dismiss() } }
            .show()
        return reply.future
    }

    override fun onButtonPrompt(session: GeckoSession, prompt: PromptDelegate.ButtonPrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.dismiss())
        val reply = Reply<PromptResponse>()
        dialog(a, prompt.title, prompt.message)
            .setPositiveButton(android.R.string.ok) { _, _ -> reply.send { prompt.confirm(PromptDelegate.ButtonPrompt.Type.POSITIVE) } }
            .setNegativeButton(android.R.string.cancel) { _, _ -> reply.send { prompt.confirm(PromptDelegate.ButtonPrompt.Type.NEGATIVE) } }
            .setOnDismissListener { reply.send { prompt.dismiss() } }
            .show()
        return reply.future
    }

    override fun onTextPrompt(session: GeckoSession, prompt: PromptDelegate.TextPrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.dismiss())
        val reply = Reply<PromptResponse>()
        val field = EditText(a).apply {
            setText(prompt.defaultValue.orEmpty())
            setSingleLine()
        }
        dialog(a, prompt.title, prompt.message)
            .setView(padded(a, field))
            .setPositiveButton(android.R.string.ok) { _, _ -> reply.send { prompt.confirm(field.text.toString()) } }
            .setNegativeButton(android.R.string.cancel, null)
            .setOnDismissListener { reply.send { prompt.dismiss() } }
            .show()
        return reply.future
    }

    override fun onAuthPrompt(session: GeckoSession, prompt: PromptDelegate.AuthPrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.dismiss())
        val reply = Reply<PromptResponse>()
        val options = prompt.authOptions
        val onlyPassword = (options.flags and PromptDelegate.AuthPrompt.AuthOptions.Flags.ONLY_PASSWORD) != 0
        val user = EditText(a).apply {
            hint = "Username"
            setText(options.username.orEmpty())
            setSingleLine()
        }
        val password = EditText(a).apply {
            hint = "Password"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setText(options.password.orEmpty())
        }
        val fields = LinearLayout(a).apply {
            orientation = LinearLayout.VERTICAL
            if (!onlyPassword) addView(user)
            addView(password)
        }
        dialog(a, prompt.title ?: "Sign in", prompt.message)
            .setView(padded(a, fields))
            .setPositiveButton("Sign in") { _, _ ->
                reply.send {
                    if (onlyPassword) prompt.confirm(password.text.toString())
                    else prompt.confirm(user.text.toString(), password.text.toString())
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .setOnDismissListener { reply.send { prompt.dismiss() } }
            .show()
        return reply.future
    }

    /** <select> menus, including grouped options. */
    override fun onChoicePrompt(session: GeckoSession, prompt: PromptDelegate.ChoicePrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.dismiss())
        val reply = Reply<PromptResponse>()
        val choices = mutableListOf<PromptDelegate.ChoicePrompt.Choice>()
        fun flatten(list: Array<out PromptDelegate.ChoicePrompt.Choice>) {
            for (choice in list) {
                val items = choice.items
                if (items != null) flatten(items) else if (!choice.separator && !choice.disabled) choices += choice
            }
        }
        flatten(prompt.choices)
        val labels = choices.map { it.label }.toTypedArray()
        val builder = dialog(a, prompt.title, prompt.message).setOnDismissListener { reply.send { prompt.dismiss() } }
        if (prompt.type == PromptDelegate.ChoicePrompt.Type.MULTIPLE) {
            val checked = choices.map { it.selected }.toBooleanArray()
            builder.setMultiChoiceItems(labels, checked) { _, which, isChecked -> checked[which] = isChecked }
                .setPositiveButton(android.R.string.ok) { _, _ ->
                    reply.send { prompt.confirm(choices.filterIndexed { i, _ -> checked[i] }.toTypedArray()) }
                }
                .setNegativeButton(android.R.string.cancel, null)
        } else {
            val selected = choices.indexOfFirst { it.selected }
            builder.setSingleChoiceItems(labels, selected) { d, which ->
                reply.send { prompt.confirm(choices[which]) }
                d.dismiss()
            }
        }
        builder.show()
        return reply.future
    }

    override fun onFilePrompt(session: GeckoSession, prompt: PromptDelegate.FilePrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.dismiss())
        val reply = Reply<PromptResponse>()
        val type = prompt.mimeTypes?.firstOrNull { it.contains('/') } ?: "*/*"
        val intent = Intent(Intent.ACTION_GET_CONTENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(type)
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, prompt.type == PromptDelegate.FilePrompt.Type.MULTIPLE)
        a.pickFiles(intent) { resultCode, data ->
            val uris = mutableListOf<Uri>()
            data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris += clip.getItemAt(i).uri }
            if (uris.isEmpty()) data?.data?.let { uris += it }
            reply.send {
                when {
                    resultCode != Activity.RESULT_OK || uris.isEmpty() -> prompt.dismiss()
                    uris.size == 1 -> prompt.confirm(a, uris[0])
                    else -> prompt.confirm(a, uris.toTypedArray())
                }
            }
        }
        return reply.future
    }

    override fun onDateTimePrompt(session: GeckoSession, prompt: PromptDelegate.DateTimePrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.dismiss())
        val reply = Reply<PromptResponse>()
        val now = Calendar.getInstance()
        when (prompt.type) {
            PromptDelegate.DateTimePrompt.Type.DATE -> {
                val parts = prompt.defaultValue?.split("-")?.mapNotNull { it.toIntOrNull() }
                val (y, m, d) = if (parts != null && parts.size == 3) parts
                else listOf(now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1, now.get(Calendar.DAY_OF_MONTH))
                DatePickerDialog(a, { _, year, month, day ->
                    reply.send { prompt.confirm(String.format(Locale.ROOT, "%04d-%02d-%02d", year, month + 1, day)) }
                }, y, m - 1, d).apply {
                    setOnDismissListener { reply.send { prompt.dismiss() } }
                    show()
                }
            }
            PromptDelegate.DateTimePrompt.Type.TIME -> {
                val parts = prompt.defaultValue?.split(":")?.mapNotNull { it.toIntOrNull() }
                val h = parts?.getOrNull(0) ?: now.get(Calendar.HOUR_OF_DAY)
                val m = parts?.getOrNull(1) ?: now.get(Calendar.MINUTE)
                TimePickerDialog(a, { _, hour, minute ->
                    reply.send { prompt.confirm(String.format(Locale.ROOT, "%02d:%02d", hour, minute)) }
                }, h, m, true).apply {
                    setOnDismissListener { reply.send { prompt.dismiss() } }
                    show()
                }
            }
            else -> reply.send { prompt.dismiss() }
        }
        return reply.future
    }

    override fun onBeforeUnloadPrompt(session: GeckoSession, prompt: PromptDelegate.BeforeUnloadPrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.confirm(AllowOrDeny.ALLOW))
        val reply = Reply<PromptResponse>()
        dialog(a, "Leave this page?", "Changes you made may not be saved.")
            .setPositiveButton("Leave") { _, _ -> reply.send { prompt.confirm(AllowOrDeny.ALLOW) } }
            .setNegativeButton("Stay") { _, _ -> reply.send { prompt.confirm(AllowOrDeny.DENY) } }
            .setOnDismissListener { reply.send { prompt.confirm(AllowOrDeny.DENY) } }
            .show()
        return reply.future
    }

    override fun onRepostConfirmPrompt(session: GeckoSession, prompt: PromptDelegate.RepostConfirmPrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.confirm(AllowOrDeny.DENY))
        val reply = Reply<PromptResponse>()
        dialog(a, "Send this form again?", "Reloading this page sends the information you entered again.")
            .setPositiveButton("Send again") { _, _ -> reply.send { prompt.confirm(AllowOrDeny.ALLOW) } }
            .setNegativeButton(android.R.string.cancel) { _, _ -> reply.send { prompt.confirm(AllowOrDeny.DENY) } }
            .setOnDismissListener { reply.send { prompt.confirm(AllowOrDeny.DENY) } }
            .show()
        return reply.future
    }

    /** You signed in somewhere: offer to save the password (or update it). Not
     * in private tabs, and not if you turned it off on the Passwords page. */
    override fun onLoginSave(
        session: GeckoSession,
        request: PromptDelegate.AutocompleteRequest<Autocomplete.LoginSaveOption>,
    ): GeckoResult<PromptResponse>? {
        val a = activity
        val option = request.options.firstOrNull()
        val tab = browser.tabs.firstOrNull { it.session === session }
        if (a == null || option == null || tab == null || tab.private || !browser.app.logins.offerToSave) {
            return GeckoResult.fromValue(request.dismiss())
        }
        val login = option.value
        val site = Logins.host(login.origin)
        val update = login.guid != null
        val reply = Reply<PromptResponse>()
        dialog(a, if (update) "Update your password for $site?" else "Save your password for $site?", login.username.ifBlank { null })
            .setPositiveButton(if (update) "Update" else "Save") { _, _ -> reply.send { request.confirm(option) } }
            .setNegativeButton("Not now") { _, _ -> reply.send { request.dismiss() } }
            .setOnDismissListener { reply.send { request.dismiss() } }
            .show()
        return reply.future
    }

    /** More than one saved login fits this sign-in form: pick one. */
    override fun onLoginSelect(
        session: GeckoSession,
        request: PromptDelegate.AutocompleteRequest<Autocomplete.LoginSelectOption>,
    ): GeckoResult<PromptResponse>? {
        val a = activity ?: return GeckoResult.fromValue(request.dismiss())
        val options = request.options
        if (options.isEmpty()) return GeckoResult.fromValue(request.dismiss())
        val reply = Reply<PromptResponse>()
        AlertDialog.Builder(a)
            .setTitle("Sign in as")
            .setItems(options.map { it.value.username.ifBlank { "(no username)" } }.toTypedArray()) { _, which ->
                reply.send { request.confirm(options[which]) }
            }
            .setOnDismissListener { reply.send { request.dismiss() } }
            .show()
        return reply.future
    }

    /** navigator.share(): Android's share sheet. */
    override fun onSharePrompt(session: GeckoSession, prompt: PromptDelegate.SharePrompt): GeckoResult<PromptResponse> {
        val a = activity ?: return GeckoResult.fromValue(prompt.dismiss())
        val text = listOfNotNull(prompt.text, prompt.uri).joinToString("\n")
        a.share(text, prompt.title)
        return GeckoResult.fromValue(prompt.confirm(PromptDelegate.SharePrompt.Result.SUCCESS))
    }

    private fun padded(a: Activity, view: android.view.View) = LinearLayout(a).apply {
        val pad = a.dp(20)
        setPadding(pad, a.dp(8), pad, 0)
        addView(view, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
    }
}
