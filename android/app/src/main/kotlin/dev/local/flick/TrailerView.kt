package dev.local.flick

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject

internal fun validTrailerSource(source: String, youtube: Boolean): Boolean {
    if (youtube) return Regex("^[a-zA-Z0-9_-]{11}$").matches(source)
    return try {
        val uri = java.net.URI(source)
        (uri.scheme == "https" || uri.scheme == "http") && !uri.host.isNullOrEmpty() && uri.userInfo == null
    } catch (_: Exception) { false }
}

class TrailerViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val views = mutableSetOf<TrailerView>()
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return TrailerView(context, messenger, viewId, args as? Map<*, *> ?: emptyMap<Any, Any>()) { views.remove(it) }
            .also { views.add(it) }
    }
    fun pauseAll() = views.toList().forEach { it.pause() }
    fun dispose() = views.toList().forEach { it.dispose() }
}

private class TrailerView(
    context: Context, messenger: BinaryMessenger, id: Int, args: Map<*, *>,
    private val onDispose: (TrailerView) -> Unit
) : PlatformView {
    private val root = FrameLayout(context)
    private val channel = MethodChannel(messenger, "flick/trailer/$id")
    private val handler = Handler(Looper.getMainLooper())
    private var web: WebView? = null
    private var disposed = false
    private var started = false
    private val timeout = Runnable { if (!started) event("blocked") }

    init {
        root.post {
            if (!disposed) {
                try { load(context, args) } catch (_: Exception) { event("error") }
            }
        }
    }

    private fun event(value: String) {
        if (disposed) return
        if (value == "playing") { started = true; handler.removeCallbacks(timeout) }
        if (value == "error" || value == "blocked" || value == "ended") handler.removeCallbacks(timeout)
        channel.invokeMethod("event", value)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun load(context: Context, args: Map<*, *>) {
        val source = args["source"] as? String ?: return event("error")
        val youtube = args["youtube"] == true
        if (!validTrailerSource(source, youtube)) return event("error")
        val player = WebView(context)
        web = player
        player.settings.javaScriptEnabled = true
        player.settings.domStorageEnabled = true
        player.settings.mediaPlaybackRequiresUserGesture = false
        player.settings.allowFileAccess = false
        player.settings.allowContentAccess = false
        // Only this fixed page controls the player; addon text is never executable HTML.
        player.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = request.isForMainFrame
        }
        player.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                val value = message.message().removePrefix("flick-preview:")
                if (message.message().startsWith("flick-preview:") && value in setOf("playing", "paused", "ended", "error", "blocked")) {
                    event(value)
                    return true
                }
                return false
            }
        }
        root.addView(player, FrameLayout.LayoutParams(-1, -1))
        val quoted = JSONObject.quote(source).replace("<", "\\u003c")
        val script = if (youtube) """
            var player;
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {width:'100%',height:'100%',videoId:$quoted,
                playerVars:{playsinline:1,controls:1,autoplay:0,origin:'https://dev.local.flick'},
                events:{onReady:function(e){e.target.mute();e.target.playVideo();},
                  onStateChange:function(e){if(e.data===1)send('playing');if(e.data===2)send('paused');if(e.data===0)send('ended');},
                  onError:function(){send('error');},onAutoplayBlocked:function(){send('blocked');}}});
            }
            var tag=document.createElement('script');tag.src='https://www.youtube.com/iframe_api';document.head.appendChild(tag);
            function stopPreview(){if(player && player.pauseVideo){player.mute();player.pauseVideo();}}
        """ else """
            var player=document.createElement('video');player.controls=true;player.muted=true;player.autoplay=true;player.playsInline=true;
            player.style='width:100%;height:100%;object-fit:contain';
            ['playing','pause','ended','error'].forEach(function(e){player.addEventListener(e,function(){send(e==='pause'?'paused':e);});});
            document.getElementById('player').replaceWith(player);player.src=$quoted;
            player.play().catch(function(){send('blocked');});
            function stopPreview(){player.muted=true;player.pause();}
        """
        val baseUrl = if (!youtube && source.startsWith("http://")) "http://dev.local.flick/" else "https://dev.local.flick/"
        player.loadDataWithBaseURL(baseUrl, """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <meta name="referrer" content="strict-origin-when-cross-origin">
            <style>html,body,#player{margin:0;width:100%;height:100%;overflow:hidden;background:#080808}</style>
            </head><body><div id="player"></div><script>
            function send(e){console.log('flick-preview:'+e);} $script
            </script></body></html>
        """.trimIndent(), "text/html", "UTF-8", null)
        handler.postDelayed(timeout, 12000)
    }

    fun pause() {
        web?.evaluateJavascript("if(typeof stopPreview==='function')stopPreview();", null)
        web?.onPause()
    }

    override fun getView(): View = root

    override fun dispose() {
        if (disposed) return
        disposed = true
        handler.removeCallbacksAndMessages(null)
        web?.let { it.stopLoading(); it.loadUrl("about:blank"); root.removeView(it); it.destroy() }
        web = null
        channel.setMethodCallHandler(null)
        onDispose(this)
    }
}
