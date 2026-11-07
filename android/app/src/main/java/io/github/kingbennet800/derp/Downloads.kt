package io.github.kingbennet800.derp

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.webkit.URLUtil
import org.mozilla.geckoview.WebResponse
import java.io.File

/** Files a page hands over (downloads, including ones a page makes itself,
 * like your dork's picture) go to Downloads. */
object Downloads {
    fun save(context: Context, response: WebResponse, done: (String?) -> Unit) {
        val body = response.body ?: return done(null)
        fun header(name: String) = response.headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
        val type = header("Content-Type")?.substringBefore(';')?.trim()?.ifBlank { null }
        val name = URLUtil.guessFileName(response.uri, header("Content-Disposition"), type)
        Thread {
            val saved = runCatching {
                body.use { input ->
                    if (Build.VERSION.SDK_INT >= 29) {
                        val resolver = context.contentResolver
                        val values = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, name)
                            if (type != null) put(MediaStore.Downloads.MIME_TYPE, type)
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            ?: error("couldn't create the file")
                        resolver.openOutputStream(uri)!!.use { input.copyTo(it) }
                        values.clear()
                        values.put(MediaStore.Downloads.IS_PENDING, 0)
                        resolver.update(uri, values, null, null)
                    } else {
                        val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir
                        File(dir, name).outputStream().use { input.copyTo(it) }
                    }
                }
                name
            }.getOrNull()
            Handler(Looper.getMainLooper()).post { done(saved) }
        }.start()
    }
}
