package io.github.kingbennet800.derp

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DoodleTest {
    /** The repo, from the app module (where Gradle runs unit tests). */
    private val repo = File("../..")

    @Test
    fun doodleIsTheDefaultAndFirst() {
        assertEquals(Engine.DOODLE, Engine.values().first())
    }

    @Test
    fun searchesInDerpsColors() {
        val light = Engine.DOODLE.search("googly%20eyes", dark = false)
        assertEquals("https://duckduckgo.com/?q=googly%20eyes&$DOODLE_LIGHT&kt=system-ui&ka=system-ui", light)
        val dark = Engine.DOODLE.search("googly%20eyes", dark = true)
        assertEquals("https://duckduckgo.com/?q=googly%20eyes&$DOODLE_DARK&kt=system-ui&ka=system-ui", dark)
        // Other engines don't change with dark mode.
        assertEquals("https://www.google.com/search?q=duck", Engine.GOOGLE.search("duck", dark = true))
    }

    @Test
    fun sameColorsAsDesktop() {
        val policies = File(repo, "config/policies.json").readText()
        assertTrue("policies.json has Doodle's light colors", policies.contains("q={searchTerms}&$DOODLE_LIGHT&kt=system-ui&ka=system-ui"))
        val features = File(repo, "src/features/DerpFeatures.sys.mjs").readText()
        assertTrue("DerpFeatures has Doodle's light colors", features.contains("LIGHT: \"$DOODLE_LIGHT\""))
        assertTrue("DerpFeatures has Doodle's dark colors", features.contains("DARK: \"$DOODLE_DARK\""))
    }
}
