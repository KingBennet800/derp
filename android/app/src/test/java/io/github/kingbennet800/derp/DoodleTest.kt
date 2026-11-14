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
        assertEquals("https://www.google.com/search?q=duck", Engine.GOOGLE.search("duck"))
    }

    @Test
    fun theLookHasDoodlesLogo() {
        val paths = Regex("""\sd="([^"]+)"""")
        val logo = paths.findAll(File(repo, "brand/doodle.svg").readText()).map { it.groupValues[1] }.toList()
        val look = File(repo, "src/features/doodle-look/doodle-page.js").readText()
        assertTrue("brand/doodle.svg has paths", logo.isNotEmpty())
        logo.forEach { assertTrue("doodle-page.js draws $it", look.contains("d=\"$it\"")) }
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
        assertTrue("desktop's hint", File(repo, "src/features/DerpFeatures.sys.mjs").readText().contains(hint))
        assertTrue("Android's hint", File("src/main/assets/derp/background.js").readText().contains(hint))
    }

    @Test
    fun theLookRunsOnDoodlesPages() {
        val pages = "\"https://www.google.com/search*\""
        assertTrue("desktop's look", File(repo, "src/features/doodle-look/manifest.json").readText().contains(pages))
        assertTrue("Android's look", File("src/main/assets/derp/manifest.json").readText().contains(pages))
    }
}
