package com.saplin.nothingness

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    
    companion object {
        private const val TAG = "MainActivity"
        private const val MEDIA_CHANNEL = "com.saplin.nothingness/media"
        private const val SPECTRUM_CHANNEL = "com.saplin.nothingness/spectrum"
        private const val PERMISSION_REQUEST_CODE = 1001
    }
    
    private var audioCaptureService: AudioCaptureService? = null
    private var visualizerService: VisualizerService? = null
    private var spectrumEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        audioCaptureService = AudioCaptureService(this)
        visualizerService = VisualizerService()
        
        // Method channel for media controls and song info
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSongInfo" -> {
                    val songInfo = MediaSessionService.getInstance()?.getCurrentSongInfo()
                    if (songInfo != null) {
                        result.success(mapOf(
                            "title" to songInfo.title,
                            "artist" to songInfo.artist,
                            "album" to songInfo.album,
                            "isPlaying" to songInfo.isPlaying,
                            "position" to songInfo.position,
                            "duration" to songInfo.duration
                        ))
                    } else {
                        result.success(null)
                    }
                }
                "play" -> {
                    MediaSessionService.getInstance()?.play()
                    result.success(null)
                }
                "pause" -> {
                    MediaSessionService.getInstance()?.pause()
                    result.success(null)
                }
                "playPause" -> {
                    MediaSessionService.getInstance()?.playPause()
                    result.success(null)
                }
                "next" -> {
                    MediaSessionService.getInstance()?.next()
                    result.success(null)
                }
                "previous" -> {
                    MediaSessionService.getInstance()?.previous()
                    result.success(null)
                }
                "seekTo" -> {
                    val position = call.argument<Long>("position") ?: 0L
                    MediaSessionService.getInstance()?.seekTo(position)
                    result.success(null)
                }
                "isNotificationAccessGranted" -> {
                    result.success(isNotificationAccessGranted())
                }
                "openNotificationSettings" -> {
                    openNotificationAccessSettings()
                    result.success(null)
                }
                "refreshSessions" -> {
                    MediaSessionService.getInstance()?.refreshSessions()
                    result.success(null)
                }
                "hasAudioPermission" -> {
                    result.success(audioCaptureService?.hasPermission() ?: false)
                }
                "requestAudioPermission" -> {
                    requestAudioPermission()
                    result.success(null)
                }
                "updateSpectrumSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    val settings = call.arguments as? Map<String, Any>
                    if (settings != null) {
                        val noiseGateDb = (settings["noiseGateDb"] as? Number)?.toDouble() ?: -35.0
                        val barCount = (settings["barCount"] as? Number)?.toInt() ?: 12
                        val decaySpeed = (settings["decaySpeed"] as? Number)?.toDouble() ?: 0.12
                        audioCaptureService?.updateSettings(noiseGateDb, barCount, decaySpeed)
                        visualizerService?.updateSettings(noiseGateDb, barCount, decaySpeed)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        
        // Event channel for spectrum data stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SPECTRUM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    spectrumEventSink = events
                    val sessionId = arguments as? Int
                    startSpectrumCapture(sessionId)
                }
                
                override fun onCancel(arguments: Any?) {
                    stopSpectrumCapture()
                    spectrumEventSink = null
                }
            }
        )
        
        // Set up song info callback
        setupSongInfoCallback(flutterEngine)
    }
    
    private fun setupSongInfoCallback(flutterEngine: FlutterEngine) {
        // Poll for song info updates since the service might not be ready immediately
        val songInfoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
        
        MediaSessionService.getInstance()?.setSongInfoCallback { songInfo ->
            mainHandler.post {
                // Notify Flutter of song info changes if needed
                // The Flutter side polls getSongInfo, but we could also push updates here
            }
        }
    }
    
    private fun startSpectrumCapture(sessionId: Int? = null) {
        if (audioCaptureService?.hasPermission() != true) {
            Log.w(TAG, "Cannot start spectrum capture - no permission")
            return
        }

        if (sessionId != null) {
            audioCaptureService?.stopCapture()
            visualizerService?.startCapture(sessionId) { spectrumData ->
                mainHandler.post { spectrumEventSink?.success(spectrumData) }
            }
        } else {
            visualizerService?.stopCapture()
            audioCaptureService?.startCapture { spectrumData ->
                mainHandler.post { spectrumEventSink?.success(spectrumData) }
            }
        }
    }

    private fun stopSpectrumCapture() {
        audioCaptureService?.stopCapture()
        visualizerService?.stopCapture()
    }
    
    private fun isNotificationAccessGranted(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )
        return enabledListeners?.contains(packageName) == true
    }
    
    private fun openNotificationAccessSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        startActivity(intent)
    }
    
    private fun requestAudioPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                PERMISSION_REQUEST_CODE
            )
        }
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "Audio permission granted")
                // Restart spectrum capture if event sink is active
                if (spectrumEventSink != null) {
                    startSpectrumCapture()
                }
            } else {
                Log.w(TAG, "Audio permission denied")
            }
        }
    }
    
    override fun onResume() {
        super.onResume()
        // Refresh sessions when returning to the app (e.g., after granting notification access)
        MediaSessionService.getInstance()?.refreshSessions()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopSpectrumCapture()
    }
}
