package net.olivierluethy.collage

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var files: FileBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // MP4 export for video collages (see VideoEncoder.kt).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collage/video_encoder")
            .setMethodCallHandler(VideoEncoder())
        // Export destinations: picked folders, Save as, Downloads (see FileBridge.kt).
        val bridge = FileBridge(this)
        files = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collage/files")
            .setMethodCallHandler(bridge)
    }

    @Deprecated("Still the simplest hook for one-off pickers from a FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (files?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
