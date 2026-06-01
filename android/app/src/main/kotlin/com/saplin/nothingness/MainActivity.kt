package com.saplin.nothingness

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.media.AudioManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val MEDIA_CHANNEL = "com.saplin.nothingness/media"
        private const val SPECTRUM_CHANNEL = "com.saplin.nothingness/spectrum"
        private const val MEDIASTORE_CHANNEL = "com.saplin.nothingness/mediastore"
        private const val MEDIASTORE_EVENTS_CHANNEL = "com.saplin.nothingness/mediastore/events"
        private const val AUTOMATION_CHANNEL = "com.saplin.nothingness/automation"
        private const val PERMISSION_REQUEST_CODE = 1001

        // B-031: external automation actions (MacroDroid / Tasker / adb).
        private const val ACTION_PLAY = "com.saplin.nothingness.action.PLAY"
        private const val ACTION_PAUSE = "com.saplin.nothingness.action.PAUSE"
        private const val ACTION_PLAY_PAUSE = "com.saplin.nothingness.action.PLAY_PAUSE"
    }

    private var audioCaptureService: AudioCaptureService? = null
    private var spectrumEventSink: EventChannel.EventSink? = null
    private var lastSpectrumSessionId: Int? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var mediaStoreEventSink: EventChannel.EventSink? = null
    private var mediaStoreObserver: ContentObserver? = null

    private var automationChannel: MethodChannel? = null
    // Holds a decoded automation action that arrived before the Dart side
    // attached its handler (cold start). Dart drains this via
    // `consumePendingAutomationAction` on startup.
    private var pendingAutomationAction: String? = null

    private val mediaSession get() = MediaSessionService.getInstance()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // B-031: an automation intent that cold-starts the app is buffered
        // here. The Flutter engine isn't attached yet, so we cannot push
        // to Dart — Dart drains via `consumePendingAutomationAction` once
        // its handler is registered.
        pendingAutomationAction = extractAutomationAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop launch mode: subsequent automation intents re-deliver
        // through here instead of recreating the activity.
        setIntent(intent)
        val action = extractAutomationAction(intent) ?: return
        // Push to Dart immediately if it's already listening; also stash
        // as pending in case the engine is mid-attach.
        pendingAutomationAction = action
        automationChannel?.invokeMethod("onAutomationAction", action)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        audioCaptureService = AudioCaptureService(this)

        // Method channel for media controls and song info
        MethodChannel(messenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSongInfo" -> result.success(mediaSession?.getCurrentSongInfo()?.let {
                    mapOf(
                        "title" to it.title,
                        "artist" to it.artist,
                        "album" to it.album,
                        "isPlaying" to it.isPlaying,
                        "position" to it.position,
                        "duration" to it.duration,
                    )
                })
                "play" -> { mediaSession?.play(); result.success(null) }
                "pause" -> { mediaSession?.pause(); result.success(null) }
                "playPause" -> { mediaSession?.playPause(); result.success(null) }
                "next" -> { mediaSession?.next(); result.success(null) }
                "previous" -> { mediaSession?.previous(); result.success(null) }
                "dispatchExternalMediaKey" -> {
                    val keyCode = call.argument<Number>("keyCode")?.toInt()
                    if (keyCode == null) result.error("INVALID", "keyCode required", null)
                    else result.success(dispatchExternalMediaKey(keyCode))
                }
                "seekTo" -> { mediaSession?.seekTo(call.argument<Long>("position") ?: 0L); result.success(null) }
                "isNotificationAccessGranted" -> result.success(isNotificationAccessGranted())
                "openNotificationSettings" -> { openNotificationAccessSettings(); result.success(null) }
                "refreshSessions" -> { mediaSession?.refreshSessions(); result.success(null) }
                "hasAudioPermission" -> result.success(audioCaptureService?.hasPermission() ?: false)
                "requestAudioPermission" -> { requestAudioPermission(); result.success(null) }
                "readAudioBytes" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) result.error("INVALID", "path required", null)
                    else readAudioBytes(path, result)
                }
                "updateSpectrumSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    (call.arguments as? Map<String, Any>)?.let { s ->
                        audioCaptureService?.updateSettings(
                            (s["noiseGateDb"] as? Number)?.toDouble() ?: -35.0,
                            (s["barCount"] as? Number)?.toInt() ?: 12,
                            (s["decaySpeed"] as? Number)?.toDouble() ?: 0.12,
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // B-031: automation channel for external intent dispatch.
        // Kotlin → Dart: invokeMethod("onAutomationAction", "play"|"pause"|"playPause")
        // Dart → Kotlin: consumePendingAutomationAction (drain on startup)
        automationChannel = MethodChannel(messenger, AUTOMATION_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingAutomationAction" -> {
                        result.success(pendingAutomationAction)
                        pendingAutomationAction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // MediaStore channel: change notifications + version checks
        MethodChannel(messenger, MEDIASTORE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMediaStoreVersion" -> result.success(
                    try {
                        // Available on Android 11+ (API 30). For older devices, return null.
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R)
                            MediaStore.getVersion(applicationContext, MediaStore.VOLUME_EXTERNAL)
                        else null
                    } catch (e: Exception) {
                        Log.w(TAG, "getMediaStoreVersion failed", e)
                        null
                    }
                )
                "rescanFolder" -> result.success(rescanFolder(call.argument<String>("path")))
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, MEDIASTORE_EVENTS_CHANNEL).setStreamHandler(
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
        EventChannel(messenger, SPECTRUM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    spectrumEventSink = events
                    lastSpectrumSessionId = (arguments as? Number)?.toInt()
                    startSpectrumCapture(lastSpectrumSessionId)
                }
                override fun onCancel(arguments: Any?) {
                    stopSpectrumCapture()
                    spectrumEventSink = null
                    lastSpectrumSessionId = null
                }
            }
        )
    }

    private fun startSpectrumCapture(sessionId: Int? = null) {
        // Player spectrum is handled by SoLoud FFT in Dart.
        // Native capture is only used for the microphone path (sessionId == null).
        if (sessionId != null) {
            Log.d(TAG, "Ignoring native spectrum request for player sessionId=$sessionId (handled by SoLoud)")
            return
        }
        if (audioCaptureService?.hasPermission() != true) {
            Log.w(TAG, "Cannot start spectrum capture (mic) - no permission")
            return
        }
        audioCaptureService?.startCapture { spectrumData ->
            mainHandler.post { spectrumEventSink?.success(spectrumData) }
        }
    }

    private fun stopSpectrumCapture() = audioCaptureService?.stopCapture()

    private fun registerMediaStoreObserver() {
        if (mediaStoreObserver != null) return
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                mediaStoreEventSink?.success(mapOf("changed" to true))
            }
        }
        try {
            contentResolver.registerContentObserver(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, true, observer)
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

    private fun rescanFolder(folderPath: String?): Boolean {
        if (folderPath.isNullOrBlank()) {
            Log.w(TAG, "rescanFolder called without a path")
            return false
        }
        return try {
            val directory = File(folderPath)
            if (!directory.exists() || !directory.isDirectory) {
                Log.w(TAG, "rescanFolder target is not a directory: $folderPath")
                return false
            }
            val filePaths = directory.listFiles()
                ?.filter { it.isFile }?.map { it.absolutePath }?.toTypedArray() ?: emptyArray()
            if (filePaths.isNotEmpty()) {
                MediaScannerConnection.scanFile(applicationContext, filePaths, null, null)
            }
            Log.d(TAG, "Issued MediaScanner scan requests for ${filePaths.size} file(s) in $folderPath")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to rescan folder $folderPath", e)
            false
        }
    }

    /// Reads an audio file's bytes for playback. Android 11+ scoped storage
    /// blocks raw-path access to shared storage, so we resolve the `_data` path
    /// to a MediaStore content:// URI and stream it via the ContentResolver
    /// (which honours READ_MEDIA_AUDIO). Runs off the platform thread; replies
    /// with null on any failure so Dart can fall back to a direct file load.
    private fun readAudioBytes(path: String, result: MethodChannel.Result) {
        Thread {
            val bytes: ByteArray? = try {
                resolveAudioUri(path)?.let { uri ->
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                }
            } catch (e: Exception) {
                Log.w(TAG, "readAudioBytes failed for $path: ${e.message}")
                null
            }
            mainHandler.post { result.success(bytes) }
        }.start()
    }

    /// Maps a path (or pass-through content:// URI) to a playable content URI.
    private fun resolveAudioUri(path: String): Uri? {
        if (path.startsWith("content://")) return Uri.parse(path)
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        return contentResolver.query(
            collection,
            arrayOf(MediaStore.Audio.Media._ID),
            "${MediaStore.Audio.Media.DATA}=?",
            arrayOf(path),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID))
                ContentUris.withAppendedId(collection, id)
            } else null
        }
    }

    /// Dispatch a media-button key event to whichever external session is
    /// currently active. Preferred path: the NotificationListenerService that
    /// already holds the active MediaController (single permission, already
    /// requested for `getSongInfo`). Falls back to AudioManager broadcast for
    /// older vendor stacks or when the listener has not connected yet. Returns
    /// `true` if any path accepted the dispatch.
    private fun dispatchExternalMediaKey(keyCode: Int): Boolean {
        val listenerDispatched = try {
            mediaSession?.dispatchMediaButtonEvent(keyCode) == true
        } catch (e: Exception) {
            Log.w(TAG, "dispatchExternalMediaKey listener path failed", e)
            false
        }
        if (listenerDispatched) return true

        return try {
            val am = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val now = SystemClock.uptimeMillis()
            am.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0))
            am.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0))
            true
        } catch (e: Exception) {
            Log.w(TAG, "dispatchExternalMediaKey AudioManager fallback failed", e)
            false
        }
    }

    /// B-031: map an incoming intent's action to one of the short tokens
    /// Dart understands (`play`, `pause`, `playPause`). Returns null for
    /// MAIN/LAUNCHER and anything else we don't own.
    private fun extractAutomationAction(intent: Intent?): String? = when (intent?.action) {
        ACTION_PLAY -> "play"
        ACTION_PAUSE -> "pause"
        ACTION_PLAY_PAUSE -> "playPause"
        else -> null
    }

    private fun isNotificationAccessGranted(): Boolean =
        Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?.contains(packageName) == true

    private fun openNotificationAccessSettings() =
        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))

    private fun requestAudioPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            Log.d(TAG, "Audio permission granted")
            // Restart spectrum capture if event sink is active
            if (spectrumEventSink != null) startSpectrumCapture(lastSpectrumSessionId)
        } else {
            Log.w(TAG, "Audio permission denied")
        }
    }

    override fun onResume() {
        super.onResume()
        // Refresh sessions when returning to the app (e.g., after granting notification access)
        mediaSession?.refreshSessions()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopSpectrumCapture()
        unregisterMediaStoreObserver()
    }
}
