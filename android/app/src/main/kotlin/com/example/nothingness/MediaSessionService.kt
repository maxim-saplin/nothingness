package com.example.nothingness

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class MediaSessionService : NotificationListenerService() {
    
    companion object {
        private const val TAG = "MediaSessionService"
        
        @Volatile
        private var instance: MediaSessionService? = null
        
        fun getInstance(): MediaSessionService? = instance
        
        // Data class for song info
        data class SongInfo(
            val title: String,
            val artist: String,
            val album: String,
            val isPlaying: Boolean,
            val position: Long,
            val duration: Long
        )
    }
    
    private var mediaSessionManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private var songInfoCallback: ((SongInfo?) -> Unit)? = null
    
    private val mediaControllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) {
            updateSongInfo()
        }
        
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            updateSongInfo()
        }
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
    
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        // We don't need to handle individual notifications
        // Just use this to trigger media session check
        updateActiveController()
    }
    
    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        updateActiveController()
    }
    
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
            
            // Unregister from old controller
            activeController?.unregisterCallback(mediaControllerCallback)
            
            // Find first active controller
            activeController = controllers?.firstOrNull()
            activeController?.registerCallback(mediaControllerCallback)
            
            updateSongInfo()
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception accessing media sessions", e)
        }
    }
    
    private fun updateSongInfo() {
        val controller = activeController
        if (controller == null) {
            songInfoCallback?.invoke(null)
            return
        }
        
        val metadata = controller.metadata
        val playbackState = controller.playbackState
        
        val songInfo = SongInfo(
            title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Unknown",
            artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "Unknown Artist",
            album = metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: "",
            isPlaying = playbackState?.state == PlaybackState.STATE_PLAYING,
            position = playbackState?.position ?: 0L,
            duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
        )
        
        songInfoCallback?.invoke(songInfo)
    }
    
    fun getCurrentSongInfo(): SongInfo? {
        val controller = activeController ?: return null
        val metadata = controller.metadata ?: return null
        val playbackState = controller.playbackState
        
        return SongInfo(
            title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Unknown",
            artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "Unknown Artist",
            album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: "",
            isPlaying = playbackState?.state == PlaybackState.STATE_PLAYING,
            position = playbackState?.position ?: 0L,
            duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)
        )
    }
    
    fun play() {
        activeController?.transportControls?.play()
    }
    
    fun pause() {
        activeController?.transportControls?.pause()
    }
    
    fun playPause() {
        val state = activeController?.playbackState?.state
        if (state == PlaybackState.STATE_PLAYING) {
            pause()
        } else {
            play()
        }
    }
    
    fun next() {
        activeController?.transportControls?.skipToNext()
    }
    
    fun previous() {
        activeController?.transportControls?.skipToPrevious()
    }
    
    fun seekTo(positionMs: Long) {
        activeController?.transportControls?.seekTo(positionMs)
    }
    
    fun refreshSessions() {
        updateActiveController()
    }
}

