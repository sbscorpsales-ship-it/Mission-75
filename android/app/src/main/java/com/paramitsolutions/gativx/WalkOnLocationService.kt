package com.paramitsolutions.gativx

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.time.Instant
import java.util.UUID

/** Foreground GPS service. It continues recording while the screen is locked. */
class WalkOnLocationService : Service(), LocationListener {
    companion object {
        const val ACTION_START = "com.paramitsolutions.gativx.walkon.START"
        const val ACTION_STOP = "com.paramitsolutions.gativx.walkon.STOP"
        private const val CHANNEL_ID = "gativx_walkon_location"
        private const val NOTIFICATION_ID = 7401
        private const val MAX_ACCURACY_METERS = 50f
        private const val MAX_GAP_SECONDS = 30.0
        private const val MAX_JUMP_METERS = 150f
        private const val MAX_SPEED_METERS_PER_SECOND = 8.0
        private const val MAX_LOCAL_POINTS = 20_000
    }

    private lateinit var locationManager: LocationManager
    private val points = mutableListOf<WalkOnPoint>()
    private var sessionId = ""
    private var ownerUserId: String? = null
    private var startedAtMillis = 0L
    private var distanceMeters = 0.0
    private var lastAcceptedLocation: Location? = null
    private var segmentBreak = true
    private var recording = false
    private var lastPersistedPointCount = 0

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            finishWalk()
            return START_NOT_STICKY
        }
        startAsForeground()
        beginOrResumeWalk()
        return START_STICKY
    }

    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun beginOrResumeWalk() {
        val existing = WalkOnStore.active(this)
        val isNewSession = existing == null
        if (existing == null) {
            sessionId = UUID.randomUUID().toString()
            ownerUserId = SessionVault.load(this)?.userId
            startedAtMillis = System.currentTimeMillis()
            distanceMeters = 0.0
            points.clear()
            lastAcceptedLocation = null
            segmentBreak = true
            lastPersistedPointCount = 0
            WalkOnStore.saveActive(
                this,
                WalkOnSession(
                    id = sessionId,
                    activity = "Walking",
                    startedAt = Instant.ofEpochMilli(startedAtMillis).toString(),
                    finishedAt = null,
                    durationSeconds = 0,
                    distanceMeters = 0.0,
                    points = emptyList(),
                    ownerUserId = ownerUserId
                )
            )
        } else {
            sessionId = existing.id
            ownerUserId = existing.ownerUserId
            startedAtMillis = runCatching { Instant.parse(existing.startedAt).toEpochMilli() }.getOrDefault(System.currentTimeMillis())
            distanceMeters = existing.distanceMeters
            points.clear()
            points.addAll(existing.points.takeLast(MAX_LOCAL_POINTS))
            lastAcceptedLocation = points.lastOrNull()?.let { point ->
                Location("gativx-walkon-recovered").apply {
                    latitude = point.latitude
                    longitude = point.longitude
                    time = point.timestampMillis
                    accuracy = point.accuracyMeters.toFloat()
                }
            }
            // Never draw or count a straight line across an app/service interruption.
            segmentBreak = true
            lastPersistedPointCount = points.size
        }

        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            if (isNewSession) WalkOnStore.clearActive(this)
            WalkOnStore.setStatus(this, "Precise location permission is required to record a reliable WalkOn route.")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .filter { provider -> runCatching { locationManager.isProviderEnabled(provider) }.getOrDefault(false) }
        if (providers.isEmpty()) {
            if (isNewSession) WalkOnStore.clearActive(this)
            WalkOnStore.setStatus(this, "Location services are off. Enable GPS and try WalkOn again.")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        try {
            providers.forEach { provider ->
                locationManager.requestLocationUpdates(provider, 1_000L, 3f, this, Looper.getMainLooper())
            }
            recording = true
            WalkOnStore.setStatus(this, "WalkOn is recording GPS in the foreground service. You can lock your screen.")
            updateNotification("GPS route recording · screen may be locked")
        } catch (error: SecurityException) {
            if (isNewSession) WalkOnStore.clearActive(this)
            WalkOnStore.setStatus(this, "Location permission was removed. Re-enable precise location to continue.")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } catch (error: Exception) {
            if (isNewSession) WalkOnStore.clearActive(this)
            WalkOnStore.setStatus(this, error.message ?: "Could not start GPS route recording.")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    override fun onLocationChanged(location: Location) {
        if (!recording) return
        if (!location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy > MAX_ACCURACY_METERS) return
        if (!location.latitude.isFinite() || !location.longitude.isFinite()) return
        if (location.latitude !in -90.0..90.0 || location.longitude !in -180.0..180.0) return
        if (points.size >= MAX_LOCAL_POINTS) {
            WalkOnStore.setStatus(this, "WalkOn reached the 20,000-point route limit. Finish this walk to save it safely.")
            return
        }

        var breakBefore = segmentBreak || points.isEmpty()
        val previous = lastAcceptedLocation
        if (previous != null) {
            val elapsed = (location.time - previous.time) / 1000.0
            if (elapsed <= 0.0) return
            val delta = previous.distanceTo(location)
            if (!delta.isFinite() || delta < 0f) return
            if (elapsed > MAX_GAP_SECONDS) {
                breakBefore = true
            } else if (delta > MAX_JUMP_METERS || delta / elapsed > MAX_SPEED_METERS_PER_SECOND) {
                // Reject this fix. The next accepted fix starts a fresh segment.
                segmentBreak = true
                return
            }
            if (!breakBefore) distanceMeters += delta.toDouble()
        }

        points.add(
            WalkOnPoint(
                latitude = location.latitude,
                longitude = location.longitude,
                timestampMillis = location.time,
                accuracyMeters = location.accuracy.toDouble(),
                breakBefore = breakBefore
            )
        )
        lastAcceptedLocation = Location(location)
        segmentBreak = false

        if (points.size - lastPersistedPointCount >= 5) persistDraft()
        WalkOnStore.setStatus(this, "WalkOn recording · %.2f km · %d GPS points".format(distanceMeters / 1000.0, points.size))
        updateNotification("Recording · %.2f km".format(distanceMeters / 1000.0))
    }

    private fun persistDraft() {
        if (sessionId.isBlank()) return
        val session = WalkOnSession(
            id = sessionId,
            activity = "Walking",
            startedAt = Instant.ofEpochMilli(startedAtMillis).toString(),
            finishedAt = null,
            durationSeconds = 0,
            distanceMeters = distanceMeters,
            points = points.toList(),
            ownerUserId = ownerUserId
        )
        runCatching { WalkOnStore.saveActive(this, session) }
            .onSuccess { lastPersistedPointCount = points.size }
            .onFailure { WalkOnStore.setStatus(this, "Route is still recording, but encrypted draft storage needs attention.") }
    }

    private fun restoreActiveIfNeeded() {
        if (sessionId.isNotBlank()) return
        val existing = WalkOnStore.active(this) ?: return
        sessionId = existing.id
        ownerUserId = existing.ownerUserId
        startedAtMillis = runCatching { Instant.parse(existing.startedAt).toEpochMilli() }.getOrDefault(System.currentTimeMillis())
        distanceMeters = existing.distanceMeters
        points.clear()
        points.addAll(existing.points.takeLast(MAX_LOCAL_POINTS))
        lastAcceptedLocation = points.lastOrNull()?.let { point ->
            Location("gativx-walkon-recovered").apply {
                latitude = point.latitude
                longitude = point.longitude
                time = point.timestampMillis
                accuracy = point.accuracyMeters.toFloat()
            }
        }
        segmentBreak = true
        lastPersistedPointCount = points.size
    }

    private fun finishWalk() {
        restoreActiveIfNeeded()
        if (!recording && WalkOnStore.active(this) == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        runCatching { locationManager.removeUpdates(this) }
        recording = false
        persistDraft()
        val finishedMillis = System.currentTimeMillis()
        val duration = ((finishedMillis - startedAtMillis).coerceAtLeast(0L) / 1000L).coerceAtMost(86_400L)
        val finished = WalkOnStore.finishActive(
            this,
            finishedAt = Instant.ofEpochMilli(finishedMillis).toString(),
            durationSeconds = duration,
            distanceMeters = distanceMeters,
            points = points.toList()
        )
        WalkOnStore.setStatus(
            this,
            if (finished != null) "WalkOn saved · %.2f km · %d GPS points. Sync it to your GATIVX account when signed in.".format(distanceMeters / 1000.0, points.size)
            else "WalkOn finished. No reliable route points were available to save."
        )
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onProviderEnabled(provider: String) {
        WalkOnStore.setStatus(this, "Location provider enabled. WalkOn is recording when a reliable GPS fix arrives.")
    }

    override fun onProviderDisabled(provider: String) {
        WalkOnStore.setStatus(this, "GPS provider disabled. Enable Location Services to continue route recording.")
    }

    override fun onDestroy() {
        if (recording) {
            runCatching { locationManager.removeUpdates(this) }
            persistDraft()
        }
        recording = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "WalkOn GPS tracking", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Visible while GATIVX records a WalkOn route."
                    setShowBadge(false)
                }
            )
        }
    }

    private fun buildNotification(message: String = "GPS route recording is active."): Notification {
        val stopIntent = Intent(this, WalkOnLocationService::class.java).setAction(ACTION_STOP)
        val stopPending = PendingIntent.getService(
            this,
            NOTIFICATION_ID,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openPending = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID + 1,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("GATIVX · WalkOn")
            .setContentText(message)
            .setContentIntent(openPending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_media_pause, "Finish walk", stopPending)
            .build()
    }

    private fun updateNotification(message: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(message))
    }
}
