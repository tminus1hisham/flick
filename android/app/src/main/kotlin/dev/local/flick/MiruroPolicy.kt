package dev.local.flick

import java.net.URI

internal object MiruroPolicy {
    val origins = setOf("https://www.miruro.to", "https://www.miruro.ru", "https://www.miruro.bz", "https://www.miruro.tv")

    fun requestPath(path: String): Boolean = try {
        val uri = URI(path)
        uri.scheme == null && uri.rawAuthority == null && uri.rawFragment == null &&
            (uri.path == "/api/v1/anime" ||
                uri.path.matches(Regex("/api/v1/anime/[A-Za-z0-9_-]{1,100}/episodes(?:/[1-9][0-9]*/play)?")))
    } catch (_: Exception) { false }

    fun sameOrigin(origin: String, url: String): Boolean = try {
        val uri = URI(url)
        origin in origins && uri.scheme == "https" && uri.rawUserInfo == null &&
            (uri.port == -1 || uri.port == 443) && "https://${uri.host}" == origin
    } catch (_: Exception) { false }
}

/** A finished/cancelled request cannot accept late browser messages. */
internal class MiruroPending(val id: String, val origin: String) {
    private var finished = false
    private var verificationShown = false
    fun needsVerification(blocked: Boolean): Boolean {
        if (finished || !blocked || verificationShown) return false
        verificationShown = true
        return true
    }
    fun accepts(id: String, source: String, mainFrame: Boolean): Boolean =
        !finished && this.id == id && mainFrame && MiruroPolicy.sameOrigin(origin, source)
    fun finish(): Boolean {
        if (finished) return false
        finished = true
        return true
    }
}
