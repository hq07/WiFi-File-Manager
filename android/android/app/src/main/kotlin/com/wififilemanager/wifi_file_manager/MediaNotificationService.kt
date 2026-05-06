package com.wififilemanager.wifi_file_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.util.Log

class MediaNotificationService : Service() {

    companion object {
        private const val TAG = "MediaNotifService"
        private const val CHANNEL_ID = "media_playback"
        private const val NOTIFICATION_ID = 1

        const val ACTION_PLAY = "com.wififilemanager.PLAY"
        const val ACTION_PAUSE = "com.wififilemanager.PAUSE"
        const val ACTION_NEXT = "com.wififilemanager.NEXT"
        const val ACTION_PREV = "com.wififilemanager.PREV"
        const val ACTION_STOP = "com.wififilemanager.STOP"

        var isRunning = false
            private set

        private var instance: MediaNotificationService? = null

        fun updatePlaybackState(isPlaying: Boolean, positionMs: Long, durationMs: Long) {
            instance?.doUpdatePlaybackState(isPlaying, positionMs, durationMs)
        }

        fun updateMetadata(title: String, durationMs: Long) {
            instance?.doUpdateMetadata(title, durationMs)
        }

        fun show() {
            instance?.doShow()
        }

        fun stopService() {
            instance?.let {
                it.stopForeground(STOP_FOREGROUND_REMOVE)
                it.stopSelf()
            }
        }
    }

    private lateinit var mediaSession: MediaSession
    private var title: String = ""
    private var durationMs: Long = 0L
    private var isPlaying: Boolean = false
    private var positionMs: Long = 0L

    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_PLAY -> {
                    sendCommandToFlutter("play")
                    doUpdatePlaybackState(true, positionMs, durationMs)
                    doShow()
                }
                ACTION_PAUSE -> {
                    sendCommandToFlutter("pause")
                    doUpdatePlaybackState(false, positionMs, durationMs)
                    doShow()
                }
                ACTION_NEXT -> sendCommandToFlutter("next")
                ACTION_PREV -> sendCommandToFlutter("prev")
                ACTION_STOP -> {
                    sendCommandToFlutter("stop")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        Log.d(TAG, "onCreate")
        createChannel()

        mediaSession = MediaSession(this, "WiFiFileManager").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() {
                    sendCommandToFlutter("play")
                    doUpdatePlaybackState(true, positionMs, durationMs)
                    doShow()
                }
                override fun onPause() {
                    sendCommandToFlutter("pause")
                    doUpdatePlaybackState(false, positionMs, durationMs)
                    doShow()
                }
                override fun onSkipToNext() { sendCommandToFlutter("next") }
                override fun onSkipToPrevious() { sendCommandToFlutter("prev") }
                override fun onStop() {
                    sendCommandToFlutter("stop")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
                override fun onSeekTo(pos: Long) {
                    sendCommandToFlutter("seek:$pos")
                }
            })
            isActive = true
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_PLAY)
            addAction(ACTION_PAUSE)
            addAction(ACTION_NEXT)
            addAction(ACTION_PREV)
            addAction(ACTION_STOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(actionReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(actionReceiver, filter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        if (intent?.action == ACTION_STOP) {
            sendCommandToFlutter("stop")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        doShow()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        isRunning = false
        instance = null
        try { unregisterReceiver(actionReceiver) } catch (_: Exception) {}
        mediaSession.isActive = false
        mediaSession.release()
        super.onDestroy()
    }

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "音乐播放",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "音乐播放控制"
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
        Log.d(TAG, "Channel created")
    }

    private fun doUpdatePlaybackState(playing: Boolean, posMs: Long, durMs: Long) {
        isPlaying = playing
        positionMs = posMs
        durationMs = durMs

        val state = PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                PlaybackState.ACTION_SEEK_TO or
                PlaybackState.ACTION_STOP
            )
            .setState(
                if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                posMs,
                1.0f
            )
            .build()
        mediaSession.setPlaybackState(state)
    }

    private fun doUpdateMetadata(t: String, durMs: Long) {
        title = t
        durationMs = durMs
        val metadata = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, t)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "WiFi File Manager")
            .putLong(MediaMetadata.METADATA_KEY_DURATION, durMs)
            .build()
        mediaSession.setMetadata(metadata)
    }

    private fun doShow() {
        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause
                            else android.R.drawable.ic_media_play
        val playPauseAction = if (isPlaying) ACTION_PAUSE else ACTION_PLAY

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("WiFi File Manager")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(contentPi)
            .setOngoing(isPlaying)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(Notification.Action.Builder(
                null, "上一曲", actionPendingIntent(ACTION_PREV)).build())
            .addAction(Notification.Action.Builder(
                null, if (isPlaying) "暂停" else "播放",
                actionPendingIntent(playPauseAction)).build())
            .addAction(Notification.Action.Builder(
                null, "下一曲", actionPendingIntent(ACTION_NEXT)).build())
            .setStyle(Notification.MediaStyle()
                .setMediaSession(mediaSession.sessionToken)
                .setShowActionsInCompactView(0, 1, 2))
            .build()

        startForeground(NOTIFICATION_ID, notification)
        Log.d(TAG, "Notification shown: title=$title isPlaying=$isPlaying")
    }

    private fun actionPendingIntent(action: String): PendingIntent {
        val intent = Intent(action).setPackage(packageName)
        return PendingIntent.getBroadcast(
            this, action.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun sendCommandToFlutter(command: String) {
        Log.d(TAG, "sendCommandToFlutter: $command")
        MainActivity.channel?.invokeMethod("onMediaCommand", command)
    }
}
