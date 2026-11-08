package io.github.kingbennet800.derp

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pairing's protocol matches the reference (tests/pairing.py), which also
 * stands in for desktop Derp: these values came from it. */
class PairingTest {
    private val secret = ByteArray(32) { it.toByte() }
    private val device = "00112233445566778899aabbccddeeff"
    private val link = "https://kingbennet800.github.io/derp/pair/#AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8~http%3A%2F%2F127.0.0.1%3A8124%2F"
    private val plain = """{"v": 1, "device": "00112233445566778899aabbccddeeff", "name": "Derp on a test machine", "bookmarks": {"https://example.com/": {"title": "Example", "at": 1, "gone": false}}}"""
    private val blob = "013ff30f3b7e1931e17b321f7dada702612d4f188e3e5981af1800835b1aae8477457671f3eb39d2f851e2923064b74a82b25a64cf52b9342dd6cf1add13e66839d1d56fe0b09da598fa8c62443eacbe44ab9824f1aa0e0cc0fcfd368dddbce873b2e9a9a59f7a969ef29c1e7200bb2d6562407c417368ed097923b6ebd8f006261f782fc86b986cb756d28a6bc9c339d5be46ce1e0dbea37cca1c63743691166f1d950781a29a77d105e57e49b43b14129a2a6626"

    private fun bytes(hex: String) = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    @Test
    fun readsPairingLinks() {
        val (parsed, relay) = Pairing.parse(link)!!
        assertArrayEquals(secret, parsed)
        assertEquals("http://127.0.0.1:8124/", relay)
        // Without a relay, the usual one.
        assertEquals(Pairing.RELAY, Pairing.parse(link.substringBefore('~'))!!.second)
        // Not a pairing link, a short secret, or a relay that isn't HTTPS (or this device).
        assertNull(Pairing.parse("https://example.com/#AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"))
        assertNull(Pairing.parse(Pairing.LINK + "AAECAwQF"))
        assertNull(Pairing.parse(link.substringBefore('~') + "~http%3A%2F%2Fevil.example%2F"))
    }

    @Test
    fun derivesTheSameKeys() {
        val keys = Pairing.Keys(secret)
        assertEquals("2a86655fb8d6d7b920b0b62c85111b06bdc44011d371747738831e97e6668905", keys.box)
        assertEquals("d294c1cfff9148da26130d42e70379dcab77d260ab4692dbab618f68a90b7a9a", keys.token)
    }

    @Test
    fun opensTheReferencesSlots() {
        assertEquals(plain, Pairing.unseal(Pairing.Keys(secret), device, bytes(blob)))
    }

    @Test
    fun sealsWhatItOpens() {
        val keys = Pairing.Keys(secret)
        val sealed = Pairing.seal(keys, device, plain)
        assertEquals(1, sealed[0].toInt())
        assertEquals(plain, Pairing.unseal(keys, device, sealed))
        // A slot is tied to its device: under another device's name it won't open.
        assertTrue(runCatching { Pairing.unseal(keys, "ffeeddccbbaa99887766554433221100", sealed) }.isFailure)
    }
}
