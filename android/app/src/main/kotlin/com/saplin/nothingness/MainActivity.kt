package com.saplin.nothingness

import android.Manifest
import android.database.ContentObserver
import android.content.Intent
import android.content.pm.PackageManager
import android.media.audiofx.Equalizer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
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
        private const val MEDIASTORE_CHANNEL = "com.saplin.nothingness/mediastore"
        private const val PERMISSION_REQUEST_CODE = 1001
    }
    
    private var audioCaptureService: AudioCaptureService? = null
    private var visualizerService: VisualizerService? = null
    private var spectrumEventSink: EventChannel.EventSink? = null
    private var lastSpectrumSessionId: Int? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var mediaStoreEventSink: EventChannel.EventSink? = null
    private var mediaStoreObserver: ContentObserver? = null

    // --- EQ (Android AudioEffect) ---
    private var equalizer: Equalizer? = null
    private var eqSessionId: Int? = null
    private var eqEnabled: Boolean = false
    private var eqGainsDb: List<Double> = listOf(0.0, 0.0, 0.0, 0.0, 0.0)
    private val eqUiCentersHz: IntArray = intArrayOf(60, 230, 910, 3600, 14000)
    
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
                "setEqualizerSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    val settings = call.arguments as? Map<String, Any>
                    if (settings != null) {
                        eqEnabled = (settings["enabled"] as? Boolean) ?: false
                        val rawGains = settings["gainsDb"]
                        eqGainsDb = if (rawGains is List<*>) {
                            rawGains.map { (it as? Number)?.toDouble() ?: 0.0 }
                        } else {
                            listOf(0.0, 0.0, 0.0, 0.0, 0.0)
                        }
                        Log.d(TAG, "EQ settings updated: enabled=$eqEnabled gainsDb=$eqGainsDb sessionId=$eqSessionId")
                        applyEqSettings()
                    }
                    result.success(null)
                }
                "setEqualizerSessionId" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    val sessionId = (args?.get("sessionId") as? Number)?.toInt()
                    Log.d(TAG, "EQ session id set: $sessionId")
                    setEqualizerSession(sessionId)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // MediaStore channel: change notifications + version checks
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIASTORE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMediaStoreVersion" -> {
                    try {
                        // Available on Android 11+ (API 30). For older devices, return null.
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                            val version = MediaStore.getVersion(
                                applicationContext,
                                MediaStore.VOLUME_EXTERNAL
                            )
                            result.success(version)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "getMediaStoreVersion failed", e)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIASTORE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    mediaStoreEventSink = events
                    registerMediaStoreObserver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterMediaStoreObserver()
                    mediaStoreEventSink = null
                }
            }
        )
        
        // Event channel for spectrum data stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SPECTRUM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    spectrumEventSink = events
                    val sessionId = (arguments as? Number)?.toInt()
                    lastSpectrumSessionId = sessionId
                    startSpectrumCapture(sessionId)
                }
                
                override fun onCancel(arguments: Any?) {
                    stopSpectrumCapture()
                    spectrumEventSink = null
                    lastSpectrumSessionId = null
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
        if (sessionId != null) {
            // Visualizer-based capture (player output). Do not gate on mic permission.
            // If the platform requires RECORD_AUDIO for Visualizer, VisualizerService
            // will fail gracefully and logs will show the reason.
            audioCaptureService?.stopCapture()
            visualizerService?.startCapture(sessionId) { spectrumData ->
                mainHandler.post { spectrumEventSink?.success(spectrumData) }
            }
        } else {
            // Microphone capture requires RECORD_AUDIO permission.
            if (audioCaptureService?.hasPermission() != true) {
                Log.w(TAG, "Cannot start spectrum capture (mic) - no permission")
                return
            }
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

    private fun setEqualizerSession(sessionId: Int?) {
        // Disable/release when no session id.
        if (sessionId == null || sessionId < 0) {
            releaseEqualizer()
            return
        }
        try {
            // Recreate if different session or missing.
            if (equalizer == null || eqSessionId != sessionId) {
                releaseEqualizer()
                equalizer = Equalizer(0, sessionId)
                eqSessionId = sessionId
            }
            applyEqSettings()
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to create Equalizer for sessionId=$sessionId", t)
            releaseEqualizer()
        }
    }

    private fun applyEqSettings() {
        val eq = equalizer ?: return
        try {
            eq.enabled = eqEnabled
            if (!eqEnabled) return

            val bandRange = eq.bandLevelRange
            val minMb = bandRange[0].toInt()
            val maxMb = bandRange[1].toInt()

            val numBands = eq.numberOfBands.toInt().coerceAtLeast(0)
            if (numBands == 0) return

            // Map 5 UI bands to nearest device bands (by center frequency).
            val deviceCentersHz = IntArray(numBands) { b ->
                // getCenterFreq returns milliHz.
                (eq.getCenterFreq(b.toShort()).toInt() / 1000).coerceAtLeast(0)
            }

            // Targets -> device band index.
            val mappedBand = IntArray(eqUiCentersHz.size) { i ->
                val target = eqUiCentersHz[i]
                var bestIdx = 0
                var bestDist = Int.MAX_VALUE
                for (b in 0 until numBands) {
                    val dist = kotlin.math.abs(deviceCentersHz[b] - target)
                    if (dist < bestDist) {
                        bestDist = dist
                        bestIdx = b
                    }
                }
                bestIdx
            }

            // Combine if collisions: average gains for all UI sliders mapped to same device band.
            val sumDb = DoubleArray(numBands) { 0.0 }
            val count = IntArray(numBands) { 0 }
            for (i in mappedBand.indices) {
                val b = mappedBand[i]
                val gain = eqGainsDb.getOrNull(i) ?: 0.0
                sumDb[b] += gain
                count[b] += 1
            }

            for (b in 0 until numBands) {
                if (count[b] == 0) continue
                val avgDb = sumDb[b] / count[b].toDouble()
                val mb = (avgDb * 100.0).toInt().coerceIn(minMb, maxMb)
                eq.setBandLevel(b.toShort(), mb.toShort())
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Failed applying EQ settings", t)
        }
    }

    private fun releaseEqualizer() {
        try {
            equalizer?.release()
        } catch (_: Throwable) {
            // ignore
        } finally {
            equalizer = null
            eqSessionId = null
        }
    }

    private fun registerMediaStoreObserver() {
        if (mediaStoreObserver != null) return
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                mediaStoreEventSink?.success(mapOf("changed" to true))
            }
        }
        try {
            contentResolver.registerContentObserver(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                true,
                observer
            )
            mediaStoreObserver = observer
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register MediaStore observer", e)
        }
    }

    private fun unregisterMediaStoreObserver() {
        val observer = mediaStoreObserver ?: return
        try {
            contentResolver.unregisterContentObserver(observer)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister MediaStore observer", e)
        } finally {
            mediaStoreObserver = null
        }
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
                    startSpectrumCapture(lastSpectrumSessionId)
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
        unregisterMediaStoreObserver()
        releaseEqualizer()
    }
}
