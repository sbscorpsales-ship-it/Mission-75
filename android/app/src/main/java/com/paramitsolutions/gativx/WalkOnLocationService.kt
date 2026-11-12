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
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.time.Instant
import java.util.UUID

/** Foreground GPS service. It continues recording while the screen is locked. */
class WalkOnLocationService : Service(), LocationListener, SensorEventListener {
    companion object {
        const val ACTION_START = "com.paramitsolutions.gativx.walkon.START"
        const val ACTION_STOP = "com.paramitsolutions.gativx.walkon.STOP"
        const val ACTION_UPDATED = "com.paramitsolutions.gativx.walkon.UPDATED"
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
    private var lastUiUpdateMillis = 0L
    private lateinit var sensorManager: SensorManager
    private var stepCounter: Sensor? = null
    private var sessionSteps = 0L
    private var lastStepCounterValue: Float? = null

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounter = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            finishWalk()
            return START_NOT_STICKY
        }
        if (intent == null && WalkOnStore.active(this) == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            startAsForeground()
        } catch (_: SecurityException) {
            WalkOnStore.setStatus(this, "Android denied the location foreground service. Re-enable precise location and start WalkOn again.")
            broadcastUpdate()
            stopSelf()
            return START_NOT_STICKY
        }
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
            sessionSteps = 0L
            lastStepCounterValue = null
            val initialDraftSaved = WalkOnStore.saveActive(
                this,
                WalkOnSession(
                    id = sessionId,
                    activity = "Walking",
                    startedAt = Instant.ofEpochMilli(startedAtMillis).toString(),
                    finishedAt = null,
                    durationSeconds = 0,
                    distanceMeters = 0.0,
                    points = emptyList(),
                    sessionSteps = 0L,
                    stepCounterLastValue = null,
                    ownerUserId = ownerUserId
                )
            )
            if (!initialDraftSaved) {
                WalkOnStore.setStatus(this, "WalkOn could not verify encrypted draft storage. GPS was not started, so no route can be lost.")
                broadcastUpdate()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return
            }
        } else {
            sessionId = existing.id
            ownerUserId = existing.ownerUserId
            startedAtMillis = runCatching { Instant.parse(existing.startedAt).toEpochMilli() }.getOrDefault(System.currentTimeMillis())
            distanceMeters = existing.distanceMeters
            points.clear()
            points.addAll(existing.points.takeLast(MAX_LOCAL_POINTS))
            sessionSteps = existing.sessionSteps
            lastStepCounterValue = existing.stepCounterLastValue
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
            broadcastUpdate()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .filter { provider -> runCatching { locationManager.isProviderEnabled(provider) }.getOrDefault(false) }
        if (providers.isEmpty()) {
            if (isNewSession) WalkOnStore.clearActive(this)
            WalkOnStore.setStatus(this, "Location services are off. Enable GPS and try WalkOn again.")
            broadcastUpdate()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        if (Build.VERSION.SDK_INT >= 29 && checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED) {
            stepCounter?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        }

        try {
            providers.forEach { provider ->
                locationManager.requestLocationUpdates(provider, 1_000L, 3f, this, Looper.getMainLooper())
            }
            recording = true
            WalkOnStore.setStatus(this, if (stepCounter != null && Build.VERSION.SDK_INT >= 29 && checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED) "WalkOn is recording GPS and measured session steps. You can lock your screen." else "WalkOn GPS is recording. Measured session steps are unavailable: this device needs a step counter and Activity Recognition permission.")
            updateNotification("GPS route recording · screen may be locked")
            broadcastUpdate()
        } catch (error: SecurityException) {
            if (isNewSession) WalkOnStore.clearActive(this)
            WalkOnStore.setStatus(this, "Location permission was removed. Re-enable precise location to continue.")
            broadcastUpdate()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } catch (error: Exception) {
            if (isNewSession) WalkOnStore.clearActive(this)
            WalkOnStore.setStatus(this, error.message ?: "Could not start GPS route recording.")
            broadcastUpdate()
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
            updateNotification("Route point limit reached · finish this walk")
            broadcastUpdate()
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
            } else if (delta > MAX_JUMP_METERS || delta.toDouble() / elapsed > MAX_SPEED_METERS_PER_SECOND) {
                // Keep this fix as a new segment anchor, but never count the jump as distance.
                breakBefore = true
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
        val now = System.currentTimeMillis()
        if (now - lastUiUpdateMillis >= 10_000L) {
            WalkOnStore.setStatus(this, "WalkOn recording · %.2f km · %d GPS points".format(distanceMeters / 1000.0, points.size))
            updateNotification("Recording · %.2f km".format(distanceMeters / 1000.0))
            lastUiUpdateMillis = now
            broadcastUpdate()
        }
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
            sessionSteps = sessionSteps,
            stepCounterLastValue = lastStepCounterValue,
            ownerUserId = ownerUserId
        )
        runCatching { WalkOnStore.saveActive(this, session) }
            .onSuccess { saved ->
                if (saved) lastPersistedPointCount = points.size
                else WalkOnStore.setStatus(this, "Route is still recording, but encrypted draft storage could not be verified. Keep GATIVX open and finish only after storage recovers.")
            }
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
        runCatching { sensorManager.unregisterListener(this) }
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
            when {
                finished != null -> "WalkOn saved · %.2f km · %d GPS points. Sync it to your GATIVX account when signed in.".format(distanceMeters / 1000.0, points.size)
                points.isNotEmpty() -> "WalkOn could not verify the completed route history write. Your active GPS draft has been retained; reopen GATIVX and retry saving."
                else -> "WalkOn finished. No reliable route points were available to save."
            }
        )
        broadcastUpdate()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (!recording || event?.sensor?.type != Sensor.TYPE_STEP_COUNTER || event.values.isEmpty()) return
        val current = event.values[0]
        if (!current.isFinite() || current < 0f) return
        val previous = lastStepCounterValue
        if (previous != null && current >= previous) {
            sessionSteps = (sessionSteps + (current - previous).toLong()).coerceAtLeast(0L)
        }
        // If the device rebooted, the hardware counter may reset. Preserve the session
        // total and establish a new baseline rather than subtracting across the reset.
        lastStepCounterValue = current
        persistDraft()
        broadcastUpdate()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onProviderEnabled(provider: String) {
        WalkOnStore.setStatus(this, "Location provider enabled. WalkOn is recording when a reliable GPS fix arrives.")
        broadcastUpdate()
    }

    override fun onProviderDisabled(provider: String) {
        WalkOnStore.setStatus(this, "GPS provider disabled. Enable Location Services to continue route recording.")
        broadcastUpdate()
    }

    override fun onDestroy() {
        if (recording) {
            runCatching { locationManager.removeUpdates(this) }
            runCatching { sensorManager.unregisterListener(this) }
            persistDraft()
        }
        recording = false
        super.onDestroy()
    }

    private fun broadcastUpdate() {
        sendBroadcast(Intent(ACTION_UPDATED).setPackage(packageName))
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
