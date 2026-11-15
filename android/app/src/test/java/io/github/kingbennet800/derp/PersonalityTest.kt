package io.github.kingbennet800.derp

import java.io.File
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Dork pet, Looks and Seasons: the same on Android as on desktop. */
class PersonalityTest {
    /** The repo, from the app module (where Gradle runs unit tests). */
    private val repo = File("../..")

    @Test
    fun petOutfitsAreDesktops() {
        val source = File(repo, "src/features/DerpDork.sys.mjs").readText()
        val desktop = Regex("""\{ part: "(\w+)", value: "(\w+)", days: (\d+) \}""").findAll(source)
            .map { Triple(it.groupValues[1], it.groupValues[2], it.groupValues[3].toInt()) }.toList()
        assertEquals(desktop, Pet.UNLOCKS.map { Triple(it.part, it.value, it.days) })
    }

    @Test
    fun looksAreDesktops() {
        val css = File(repo, "theme/derp-theme.css").readText()
        for (look in Look.values().filter { it != Look.DERP }) {
            val block = Regex("""-moz-pref\("derp.look", "${look.name.lowercase()}"\) \{(.*?)\n\}""", RegexOption.DOT_MATCHES_ALL)
                .find(css)?.groupValues?.get(1)
            assertNotNull("derp-theme.css has ${look.label}", block)
            val accent = Regex("""--derp-accent: light-dark\((#\w+), (#\w+)\)""").find(block!!)
            assertNotNull("${look.label} has an accent", accent)
            assertEquals(look.accents.first.lowercase(), accent!!.groupValues[1].lowercase())
            assertEquals(look.accents.second.lowercase(), accent.groupValues[2].lowercase())
        }
    }

    @Test
    fun seasonsAreDesktops() {
        val days = mapOf(
            "2026-02-10" to listOf("heart"),
            "2026-10-28" to listOf("pumpkin", "leaf", "redLeaf"),
            "2026-01-05" to listOf("snow"),
            "2026-12-24" to listOf("snow"),
            "2026-04-10" to listOf("blossom"),
            "2026-07-04" to listOf("sun"),
            "2026-11-14" to listOf("leaf", "redLeaf"),
        )
        for ((day, art) in days) assertEquals(day, art, Seasons.of(LocalDate.parse(day)))
        // And there's art for each.
        val source = File(repo, "src/features/DerpFun.sys.mjs").readText()
        for (name in days.values.flatten().toSet()) {
            assertNotNull("DerpFun.sys.mjs draws $name", Regex("""\n  $name: svg\(""").find(source))
        }
    }

    @Test
    fun versionsCompare() {
        assertTrue(WhatsNew.newer("2.1.0", "2.0.1"))
        assertTrue(WhatsNew.newer("2.10.0", "2.9.9"))
        assertTrue(WhatsNew.newer("3.0", "2.99.99"))
        assertFalse(WhatsNew.newer("2.1.0", "2.1.0"))
        assertFalse(WhatsNew.newer("2.0.9", "2.1.0"))
    }

    @Test
    fun newsIsNewestFirst() {
        // Both apps show whatsnew.json's releases in its order, the newest first.
        val listed = Regex(""""version": "([\d.]+)"""").findAll(File(repo, "src/features/whatsnew.json").readText()).map { it.groupValues[1] }.toList()
        assertTrue("whatsnew.json lists versions", listed.isNotEmpty())
        for ((a, b) in listed.zipWithNext()) assertTrue("$a is listed before $b", WhatsNew.newer(a, b))
    }
}
