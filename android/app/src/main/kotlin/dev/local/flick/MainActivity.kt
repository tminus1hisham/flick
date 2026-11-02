package dev.local.flick

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var miruroBrowser: MiruroBrowser? = null
    private var fctv: Fctv? = null
    private var trailers: TrailerViewFactory? = null
    private var pip: MethodChannel? = null
    private var pipPlaying = false
    private val supportsPip: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipPlaying)
        }
        return builder.build()
    }

    private fun enterPip(): Boolean {
        if (!supportsPip || !pipPlaying) return false
        return try {
            enterPictureInPictureMode(pipParams())
        } catch (_: IllegalStateException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        trailers = TrailerViewFactory(flutterEngine.dartExecutor.binaryMessenger).also {
            flutterEngine.platformViewsController.registry.registerViewFactory("flick/trailer", it)
        }
        flutterEngine.plugins.add(Torrents())
        miruroBrowser = MiruroBrowser(this, flutterEngine.dartExecutor.binaryMessenger)
        fctv = Fctv(flutterEngine.dartExecutor.binaryMessenger)
        pip = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flick/pip").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "supported" -> result.success(supportsPip)
                    "playing" -> {
                        pipPlaying = call.arguments == true
                        if (supportsPip) setPictureInPictureParams(pipParams())
                        result.success(null)
                    }
                    "enter" -> result.success(enterPip())
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        pip?.invokeMethod("changed", inPip)
    }

    override fun onPause() {
        trailers?.pauseAll()
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        pip?.invokeMethod("stopped", null)
    }

    override fun onDestroy() {
        trailers?.dispose()
        trailers = null
        pip?.setMethodCallHandler(null)
        pip = null
        miruroBrowser?.dispose()
        miruroBrowser = null
        fctv?.dispose()
        fctv = null
        super.onDestroy()
    }
}
