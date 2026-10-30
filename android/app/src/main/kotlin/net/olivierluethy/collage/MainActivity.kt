package net.olivierluethy.collage

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // MP4 export for video collages (see VideoEncoder.kt).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collage/video_encoder")
            .setMethodCallHandler(VideoEncoder())
    }
}
