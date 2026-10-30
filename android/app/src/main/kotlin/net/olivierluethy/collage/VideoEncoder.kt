package net.olivierluethy.collage

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Encodes RGBA frames sent from Dart into an H.264 MP4 (no audio), for
 * video collages. Frames are drawn onto the encoder's input surface, so the
 * timestamps follow the real time between frames — which matches how the
 * collage (and any playing video cells) moved while it was captured.
 *
 * Channel "collage/video_encoder":
 *   start {path, width, height, fps, bitrate}
 *   frame {rgba: ByteArray}
 *   finish -> path
 */
class VideoEncoder : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var surface: Surface? = null
    private var bitmap: Bitmap? = null
    private var track = -1
    private var muxing = false
    private var path: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "start" -> {
                        start(
                            call.argument<String>("path")!!,
                            call.argument<Int>("width")!!,
                            call.argument<Int>("height")!!,
                            call.argument<Int>("fps") ?: 15,
                            call.argument<Int>("bitrate") ?: 8_000_000,
                        ); null
                    }
                    "frame" -> { frame(call.argument<ByteArray>("rgba")!!); null }
                    "finish" -> finish()
                    else -> { main.post { result.notImplemented() }; return@execute }
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                release()
                main.post { result.error("encoder", e.message, null) }
            }
        }
    }

    private fun start(path: String, width: Int, height: Int, fps: Int, bitrate: Int) {
        release()
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        surface = c.createInputSurface()
        c.start()
        codec = c
        muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        track = -1
        muxing = false
        this.path = path
    }

    private fun frame(rgba: ByteArray) {
        val bmp = bitmap ?: error("not started")
        val s = surface ?: error("not started")
        bmp.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
        val canvas = s.lockHardwareCanvas()
        try {
            canvas.drawBitmap(bmp, 0f, 0f, null)
        } finally {
            s.unlockCanvasAndPost(canvas)
        }
        drain(false)
    }

    private fun finish(): String? {
        val c = codec ?: return null
        c.signalEndOfInputStream()
        drain(true)
        val out = path
        release()
        return out
    }

    private fun drain(endOfStream: Boolean) {
        val c = codec ?: return
        val m = muxer ?: return
        val info = MediaCodec.BufferInfo()
        var idle = 0
        while (true) {
            val index = c.dequeueOutputBuffer(info, if (endOfStream) 10_000L else 0L)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++idle > 300) return // ~3 s without output at the end
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = m.addTrack(c.outputFormat)
                    m.start()
                    muxing = true
                }
                index >= 0 -> {
                    idle = 0
                    val buffer = c.getOutputBuffer(index)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (buffer != null && info.size > 0 && muxing) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        m.writeSampleData(track, buffer, info)
                    }
                    c.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    private fun release() {
        try { codec?.stop() } catch (_: Exception) {}
        try { codec?.release() } catch (_: Exception) {}
        try { if (muxing) muxer?.stop() } catch (_: Exception) {}
        try { muxer?.release() } catch (_: Exception) {}
        try { surface?.release() } catch (_: Exception) {}
        bitmap?.recycle()
        codec = null
        muxer = null
        surface = null
        bitmap = null
        muxing = false
    }
}
