package com.saplin.nothingness

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.view.KeyEvent

class MediaSessionService : NotificationListenerService() {

    companion object {
        private const val TAG = "MediaSessionService"

        @Volatile private var instance: MediaSessionService? = null
        fun getInstance(): MediaSessionService? = instance

        data class SongInfo(
            val title: String,
            val artist: String,
            val album: String,
            val isPlaying: Boolean,
            val position: Long,
            val duration: Long,
        )
    }

    private var mediaSessionManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private var songInfoCallback: ((SongInfo?) -> Unit)? = null

    private val mediaControllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) { updateSongInfo() }
        override fun onMetadataChanged(metadata: MediaMetadata?) { updateSongInfo() }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        Log.d(TAG, "MediaSessionService created")
    }

    override fun onDestroy() {
        super.onDestroy()
        activeController?.unregisterCallback(mediaControllerCallback)
        instance = null
        Log.d(TAG, "MediaSessionService destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) = updateActiveController()
    override fun onNotificationRemoved(sbn: StatusBarNotification?) = updateActiveController()

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "NotificationListener connected")
        updateActiveController()
    }

    fun setSongInfoCallback(callback: ((SongInfo?) -> Unit)?) {
        songInfoCallback = callback
        updateSongInfo()
    }

    private fun updateActiveController() {
        try {
            val componentName = ComponentName(this, MediaSessionService::class.java)
            val controllers = mediaSessionManager?.getActiveSessions(componentName)
            activeController?.unregisterCallback(mediaControllerCallback)
            activeController = controllers?.firstOrNull()
            activeController?.registerCallback(mediaControllerCallback)
            updateSongInfo()
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception accessing media sessions", e)
        }
    }

    private fun updateSongInfo() = songInfoCallback?.invoke(songInfoFrom(activeController))

    fun getCurrentSongInfo(): SongInfo? {
        val controller = activeController ?: return null
        if (controller.metadata == null) return null
        return songInfoFrom(controller)
    }

    private fun songInfoFrom(controller: MediaController?): SongInfo? {
        controller ?: return null
        val metadata = controller.metadata
        val playbackState = controller.playbackState
        return SongInfo(
            title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Unknown",
            artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "Unknown Artist",
            album = metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: "",
            isPlaying = playbackState?.state == PlaybackState.STATE_PLAYING,
            position = playbackState?.position ?: 0L,
            duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L,
        )
    }

    fun play() { activeController?.transportControls?.play() }
    fun pause() { activeController?.transportControls?.pause() }
    fun playPause() = if (activeController?.playbackState?.state == PlaybackState.STATE_PLAYING) pause() else play()
    fun next() { activeController?.transportControls?.skipToNext() }
    fun previous() { activeController?.transportControls?.skipToPrevious() }
    fun seekTo(positionMs: Long) { activeController?.transportControls?.seekTo(positionMs) }
    fun refreshSessions() = updateActiveController()

    /// Dispatches a media-button KeyEvent (down+up pair) to the active external
    /// MediaController obtained via the notification listener. Returns true if
    /// the dispatch was accepted, false if no active controller was available
    /// or the call threw.
    fun dispatchMediaButtonEvent(keyCode: Int): Boolean {
        val controller = activeController ?: return false
        return try {
            val now = SystemClock.uptimeMillis()
            val down = KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0)
            val up = KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0)
            controller.dispatchMediaButtonEvent(down) or controller.dispatchMediaButtonEvent(up)
        } catch (e: Exception) {
            Log.w(TAG, "dispatchMediaButtonEvent failed for keyCode=$keyCode", e)
            false
        }
    }
}
