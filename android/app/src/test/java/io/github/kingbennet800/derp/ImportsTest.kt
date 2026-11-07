package io.github.kingbennet800.derp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ImportsTest {
    /** A bookmarks file as Chrome and Firefox export it (Netscape format). */
    private val bookmarksFile = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 ADD_DATE="1700000000" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://kingbennet800.github.io/derp/" ADD_DATE="1700000001" ICON="data:image/png;base64,AAAA">Derp browser</A>
                <DT><A HREF="https://en.wikipedia.org/wiki/Duck?a=1&amp;b=2" ADD_DATE="1700000002">Duck &#8211; Wikipedia &amp; more</A>
                <DT><H3>Games</H3>
                <DL><p>
                    <DT><A HREF="http://example.com/game">  <b>Game</b>  </A>
                    <DT><A HREF="javascript:alert(1)">A bookmarklet</A>
                    <DT><A HREF="place:sort=8&amp;maxResults=10">Most visited</A>
                </DL><p>
            </DL><p>
            <DT><a href="https://kingbennet800.github.io/derp/">Derp again</a>
            <DT><A HREF="https://example.org/"></A>
        </DL><p>
    """.trimIndent()

    @Test
    fun bookmarksFromAnExportedFile() {
        val marks = Imports.bookmarks(bookmarksFile)
        assertEquals(
            listOf(
                Imports.Bookmark("https://kingbennet800.github.io/derp/", "Derp browser"),
                Imports.Bookmark("https://en.wikipedia.org/wiki/Duck?a=1&b=2", "Duck – Wikipedia & more"),
                Imports.Bookmark("http://example.com/game", "Game"),
                Imports.Bookmark("https://example.org/", "https://example.org/"),
            ),
            marks,
        )
    }

    @Test
    fun noBookmarksInSomethingElse() {
        assertTrue(Imports.bookmarks("name,url,username,password\n").isEmpty())
        assertTrue(Imports.bookmarks("").isEmpty())
    }

    @Test
    fun passwordsFromChrome() {
        val csv = "name,url,username,password,note\r\n" +
            "accounts.google.com,https://accounts.google.com/signin/v2,derp@example.com,hunter2,\r\n" +
            "app,android://abc@com.example.app/,me,secret,\r\n" +
            "example.com,https://example.com:8443/login,\"Bennett, the dev\",\"pa\"\"ss,word\",\"a note\nover two lines\"\r\n"
        assertEquals(
            listOf(
                Imports.Login("https://accounts.google.com", "derp@example.com", "hunter2"),
                Imports.Login("https://example.com:8443", "Bennett, the dev", "pa\"ss,word"),
            ),
            Imports.logins(csv),
        )
    }

    @Test
    fun passwordsFromFirefoxAndDerp() {
        val csv = "﻿\"url\",\"username\",\"password\",\"httpRealm\",\"formActionOrigin\",\"guid\",\"timeCreated\",\"timeLastUsed\",\"timePasswordChanged\"\n" +
            "\"https://www.reddit.com\",\"duckfan\",\"quack quack\",,\"https://www.reddit.com\",\"{1}\",\"1\",\"2\",\"3\"\n" +
            "\"https://nopassword.example\",\"someone\",\"\",,,\"{2}\",\"1\",\"2\",\"3\"\n"
        assertEquals(listOf(Imports.Login("https://www.reddit.com", "duckfan", "quack quack")), Imports.logins(csv))
    }

    @Test
    fun passwordsFromSafari() {
        val csv = "Title,URL,Username,Password,Notes,OTPAuth\nGitHub,https://github.com/,KingBennet800,correct horse,,\n"
        assertEquals(listOf(Imports.Login("https://github.com", "KingBennet800", "correct horse")), Imports.logins(csv))
    }

    @Test
    fun noPasswordsWithoutTheColumns() {
        assertTrue(Imports.logins("a,b,c\n1,2,3\n").isEmpty())
        assertTrue(Imports.logins("").isEmpty())
        assertTrue(Imports.logins(bookmarksFile).isEmpty())
    }

    @Test
    fun origins() {
        assertEquals("https://example.com", Imports.origin("https://Example.com/path?q=1"))
        assertEquals("http://localhost:8123", Imports.origin(" http://localhost:8123/ "))
        assertNull(Imports.origin("android://abc@com.example.app/"))
        assertNull(Imports.origin("not a url"))
        assertNull(Imports.origin(""))
    }

    @Test
    fun csvQuoting() {
        assertEquals(
            listOf(listOf("a", "b,c", "d\"e", "f\ng"), listOf("1", "", "3", "")),
            Imports.csv("a,\"b,c\",\"d\"\"e\",\"f\ng\"\r\n1,,3,\n\n"),
        )
    }

    @Test
    fun characterReferences() {
        assertEquals("Tom & Jerry's — \"fun\" <3", Imports.unescape("Tom &amp; Jerry&#39;s &#x2014; &quot;fun&quot; &lt;3"))
        assertEquals("&bogus; &#99999999;", Imports.unescape("&bogus; &#99999999;"))
    }
}
