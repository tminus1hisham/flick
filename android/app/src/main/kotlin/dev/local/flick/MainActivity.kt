package dev.local.flick

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var miruroBrowser: MiruroBrowser? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(Torrents())
        miruroBrowser = MiruroBrowser(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        miruroBrowser?.dispose()
        miruroBrowser = null
        super.onDestroy()
    }
}
