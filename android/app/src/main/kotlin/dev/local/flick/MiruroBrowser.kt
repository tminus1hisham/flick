package dev.local.flick

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.SslErrorHandler
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** One ordinary browser session; verification is visible only when the site requires it. */
class MiruroBrowser(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "flick/miruro")
    private val handler = Handler(Looper.getMainLooper())
    private var current: MiruroPending? = null
    private var session: Session? = null
    private var cancel: (() -> Unit)? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "request" -> {
                    val id = call.argument<String>("id")
                    val origin = call.argument<String>("origin")
                    val path = call.argument<String>("path")
                    if (id == null || id.length !in 1..100 || origin !in MiruroPolicy.origins ||
                        path == null || path.length > 16384 || !MiruroPolicy.requestPath(path)) {
                        result.error("changed", "Invalid browser request", null)
                    } else if (current != null) {
                        result.error("busy", "A browser request is already open", null)
                    } else {
                        try {
                            open(MiruroPending(id, origin!!), path, result)
                        } catch (_: Exception) {
                            val end = cancel
                            if (end != null) end() else {
                                current = null
                                discard()
                                result.error("unsupported", "Android System WebView is unavailable", null)
                            }
                        }
                    }
                }
                "cancel" -> {
                    if (call.argument<String>("id") == current?.id) cancel?.invoke()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private inner class Session(val origin: String) {
        val dialog = Dialog(activity)
        val web = WebView(activity)
        val instruction = TextView(activity).apply {
            text = "Complete the browser check, then tap Continue."
            setPadding(16, 16, 16, 16)
        }
        val proceed = Button(activity).apply { text = "Continue" }
        var ready = false
        var started = false
        var onReady: (() -> Unit)? = null
        var onReply: ((String, String, Boolean) -> Unit)? = null
        var onFailure: (() -> Unit)? = null

        init {
            web.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                setSupportMultipleWindows(false)
            }
            web.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                    request.isForMainFrame && !MiruroPolicy.sameOrigin(origin, request.url.toString())

                override fun onPageFinished(view: WebView, url: String) {
                    if (!MiruroPolicy.sameOrigin(origin, url)) return
                    ready = true
                    val next = onReady
                    onReady = null
                    next?.invoke()
                }

                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                    handler.cancel()
                    val fail = onFailure
                    if (fail != null) fail() else discard()
                }
            }
            WebViewCompat.addWebMessageListener(web, "flickMiruro", setOf(origin)) { _, message, source, mainFrame, _ ->
                message.data?.let { onReply?.invoke(it, source.toString(), mainFrame) }
            }
            val layout = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
            val buttons = LinearLayout(activity)
            val dismiss = Button(activity).apply {
                text = "Cancel"
                setOnClickListener { cancel?.invoke() }
            }
            buttons.addView(proceed, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            buttons.addView(dismiss, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            layout.addView(instruction)
            layout.addView(web, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            layout.addView(buttons)
            dialog.setContentView(layout)
            dialog.setOnCancelListener { cancel?.invoke() }
        }
    }

    private fun discard() {
        val s = session ?: return
        session = null
        s.onReady = null
        s.onReply = null
        s.onFailure = null
        s.proceed.setOnClickListener(null)
        WebViewCompat.removeWebMessageListener(s.web, "flickMiruro")
        s.web.stopLoading()
        (s.web.parent as? ViewGroup)?.removeView(s.web)
        s.web.destroy()
        s.dialog.dismiss()
    }

    private fun open(pending: MiruroPending, path: String, result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            result.error("unsupported", "Update Android System WebView to use browser access", null)
            return
        }
        if (session?.origin != pending.origin) discard()
        val s = session ?: Session(pending.origin).also { session = it }
        current = pending
        val timeout = Runnable { s.onFailure?.invoke() }

        fun finish(error: String? = null, data: Map<String, Any>? = null) {
            if (!pending.finish()) return
            handler.removeCallbacks(timeout)
            current = null
            cancel = null
            s.onReady = null
            s.onReply = null
            s.onFailure = null
            s.proceed.setOnClickListener(null)
            s.dialog.dismiss()
            if (error != null || data?.get("status") != 200) discard()
            if (error == null) result.success(data) else result.error(error, "Browser request ended", null)
        }
        cancel = { finish("cancelled") }
        s.onFailure = { finish("unreachable") }

        fun fetch() {
            if (!pending.accepts(pending.id, s.web.url ?: "", true)) { finish("unreachable"); return }
            s.proceed.isEnabled = false
            s.instruction.text = "Asking Miruro…"
            val requestPath = JSONObject.quote(path)
            val id = JSONObject.quote(pending.id)
            // Credentials and TLS stay in this browser, including for requests after verification.
            s.web.evaluateJavascript("""
                (async () => {
                    const id = $id;
                    const controller = new AbortController();
                    const timer = setTimeout(() => controller.abort(), 20000);
                    const send = data => flickMiruro.postMessage(JSON.stringify({id, ...data}));
                    try {
                        const r = await fetch($requestPath, {credentials:'same-origin', redirect:'error', signal:controller.signal});
                        const reader = r.body.getReader();
                        let size = 0, chunks = [];
                        while (true) {
                            const part = await reader.read();
                            if (part.done) break;
                            size += part.value.byteLength;
                            if (size > 2097152) { await reader.cancel(); send({error:'changed'}); return; }
                            chunks.push(part.value);
                        }
                        let body = '';
                        for (const chunk of chunks) {
                            for (let i = 0; i < chunk.length; i += 8192) {
                                body += String.fromCharCode(...chunk.subarray(i, i + 8192));
                            }
                        }
                        const type = r.headers.get('content-type') || '';
                        const blocked = r.status === 403 || r.status === 444 || r.headers.get('cf-mitigated') === 'challenge' ||
                            (type.includes('text/html') && /cf-chl-|<title>just a moment/i.test(body));
                        send({status:r.status, body:btoa(body), type, blocked});
                    } catch (_) { send({error:'unreachable'}); }
                    finally { clearTimeout(timer); }
                })();
            """.trimIndent(), null)
        }
        s.onReply = reply@{ raw, source, mainFrame ->
            if (!pending.accepts(pending.id, source, mainFrame)) return@reply
            if (raw.length > 4 * 1024 * 1024) { finish("changed"); return@reply }
            try {
                val body = JSONObject(raw)
                if (!pending.accepts(body.optString("id"), source, mainFrame)) return@reply
                if (body.has("error")) {
                    finish(if (body.optString("error") == "changed") "changed" else "unreachable")
                } else if (pending.needsVerification(body.optBoolean("blocked"))) {
                    s.instruction.text = "Complete the browser check, then tap Continue."
                    s.proceed.isEnabled = true
                    s.dialog.show()
                    s.dialog.window?.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
                    handler.removeCallbacks(timeout)
                    handler.postDelayed(timeout, 180000)
                } else {
                    val status = body.getInt("status")
                    val text = body.getString("body")
                    if (status !in 100..599 || text.length > 3 * 1024 * 1024) finish("changed")
                    else finish(data = mapOf("status" to status, "body" to text, "type" to body.optString("type"),
                        "blocked" to body.optBoolean("blocked")))
                }
            } catch (_: Exception) { finish("changed") }
        }
        s.proceed.setOnClickListener { fetch() }
        handler.postDelayed(timeout, 30000)
        if (s.ready) fetch() else {
            s.onReady = { fetch() }
            if (!s.started) {
                s.started = true
                s.web.loadUrl(pending.origin + "/")
            }
        }
    }

    fun dispose() {
        cancel?.invoke()
        discard()
        channel.setMethodCallHandler(null)
    }
}
