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
    fun searchesGoogleMarkedAsDoodle() {
        assertEquals("https://www.google.com/search?q=googly%20eyes&doodle=1", Engine.DOODLE.search("googly%20eyes"))
        assertEquals("https://www.google.com/search?q=googly%20eyes&doodle=1", Engine.DOODLE.search("googly%20eyes", DoodleResults.GOOGLE, dark = true))
        assertEquals("https://www.google.com/search?q=duck", Engine.GOOGLE.search("duck"))
    }

    @Test
    fun searchesDuckDuckGoInDerpsColors() {
        val light = Engine.DOODLE.search("googly%20eyes", DoodleResults.DUCKDUCKGO, dark = false)
        assertEquals("https://duckduckgo.com/?q=googly%20eyes&$DOODLE_LIGHT&kt=system-ui&ka=system-ui", light)
        val dark = Engine.DOODLE.search("googly%20eyes", DoodleResults.DUCKDUCKGO, dark = true)
        assertEquals("https://duckduckgo.com/?q=googly%20eyes&$DOODLE_DARK&kt=system-ui&ka=system-ui", dark)
        // Other engines aren't Doodle.
        assertEquals("https://duckduckgo.com/?q=duck", Engine.DUCKDUCKGO.search("duck", DoodleResults.DUCKDUCKGO, dark = true))
    }

    @Test
    fun sameDuckDuckGoColorsAsDesktop() {
        val desktop = File(repo, "src/features/DerpDoodle.sys.mjs").readText()
        assertTrue("DerpDoodle has Doodle's light colors", desktop.contains("DDG_LIGHT = \"$DOODLE_LIGHT\""))
        assertTrue("DerpDoodle has Doodle's dark colors", desktop.contains("DDG_DARK = \"$DOODLE_DARK\""))
    }

    @Test
    fun theLookHasDoodlesLogo() {
        val paths = Regex("""\sd="([^"]+)"""")
        val logo = paths.findAll(File(repo, "brand/doodle.svg").readText()).map { it.groupValues[1] }.toList()
        assertTrue("brand/doodle.svg has paths", logo.isNotEmpty())
        for (name in listOf("doodle-page.js", "doodle-ddg.js")) {
            val look = File(repo, "src/features/doodle-look/$name").readText()
            logo.forEach { assertTrue("$name draws $it", look.contains("d=\"$it\"")) }
        }
    }

    @Test
    fun sameSearchAsDesktop() {
        val policies = File(repo, "config/policies.json").readText()
        val desktop = Engine.DOODLE.template.replace("%s", "{searchTerms}")
        assertTrue("policies.json searches $desktop", policies.contains("\"URLTemplate\": \"$desktop\""))
    }

    @Test
    fun bothTellGoogleDerpsTheme() {
        val hint = "Sec-CH-Prefers-Color-Scheme"
        assertTrue("desktop's hint", File(repo, "src/features/DerpDoodle.sys.mjs").readText().contains(hint))
        assertTrue("Android's hint", File("src/main/assets/derp/background.js").readText().contains(hint))
    }

    @Test
    fun theLookRunsOnDoodlesPages() {
        for (pages in listOf("\"https://www.google.com/search*\"", "\"https://duckduckgo.com/*\"")) {
            assertTrue("desktop's look on $pages", File(repo, "src/features/doodle-look/manifest.json").readText().contains(pages))
            assertTrue("Android's look on $pages", File("src/main/assets/derp/manifest.json").readText().contains(pages))
        }
    }
}
