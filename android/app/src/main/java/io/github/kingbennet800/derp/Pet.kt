package io.github.kingbennet800.derp

import android.content.Context
import java.time.LocalDate

/** Dork pet, a Just for fun setting (off until you turn it on): each day you
 * use Derp is a day together, and some days unlock an outfit for your dork.
 * Desktop Derp has the same pet (src/features/DerpPet.sys.mjs), with the same
 * outfits (UNLOCKS in DerpDork.sys.mjs, which dork-art.js has too). */
class Pet(private val context: Context) {
    /** An outfit, after so many days together; [what] is how it's said ("a crown"). */
    data class Unlock(val part: String, val value: String, val days: Int, val what: String)

    private val prefs = context.getSharedPreferences("dork", Context.MODE_PRIVATE)

    val on get() = Gag.PET.on(context)

    /** Your days together, or null if your dork isn't a pet. */
    val days: Int? get() = if (on) prefs.getInt("petDays", 0) else null

    /** Today counts as a day together (once); an outfit it just earned, if any. */
    fun count(today: LocalDate = LocalDate.now()): Unlock? {
        if (!on) return null
        var days = prefs.getInt("petDays", 0)
        if (prefs.getString("petLastDay", null) != today.toString()) {
            days += 1
            prefs.edit().putString("petLastDay", today.toString()).putInt("petDays", days).apply()
        }
        val shown = prefs.getInt("petShown", 0)
        val earned = UNLOCKS.filter { it.days in (shown + 1)..days }
        if (earned.isEmpty()) return null
        prefs.edit().putInt("petShown", days).apply()
        return earned.last()
    }

    companion object {
        val UNLOCKS = listOf(
            Unlock("hair", "flower", 3, "a flower"),
            Unlock("extras", "bowtie", 7, "a bow tie"),
            Unlock("hair", "crown", 14, "a crown"),
            Unlock("hair", "wizard", 30, "a wizard hat"),
            Unlock("extras", "monocle", 45, "a monocle"),
            Unlock("backdrop", "stars", 60, "a starry night"),
        )
    }
}
