package dev.local.flick

/** A checked replacement remains separate until the player confirms it still wants the switch. */
internal class LiveMediaSession<T : AutoCloseable> : AutoCloseable {
    private var active: T? = null
    private var pending: T? = null
    private var pendingKey: String? = null

    fun stage(key: String, candidate: T?) {
        cancel()
        pendingKey = key
        pending = candidate
    }

    fun commit(key: String) {
        check(pendingKey == key) { "Live selection expired" }
        active?.close()
        active = pending
        pending = null
        pendingKey = null
    }

    fun cancel() {
        pending?.close()
        pending = null
        pendingKey = null
    }

    override fun close() {
        cancel()
        active?.close()
        active = null
    }
}
