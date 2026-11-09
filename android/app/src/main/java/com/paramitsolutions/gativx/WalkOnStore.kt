package com.paramitsolutions.gativx

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class WalkOnPoint(
    val latitude: Double,
    val longitude: Double,
    val timestampMillis: Long,
    val accuracyMeters: Double,
    val breakBefore: Boolean
)

internal data class WalkOnSession(
    val id: String,
    val activity: String,
    val startedAt: String,
    val finishedAt: String?,
    val durationSeconds: Long,
    val distanceMeters: Double,
    val points: List<WalkOnPoint>,
    val synced: Boolean = false,
    val ownerUserId: String? = null
)

/** Encrypted local storage for sensitive GPS route drafts and completed walks. */
internal object WalkOnStore {
    private const val PREFS = "gativx_walkon_secure"
    private const val ACTIVE_KEY = "active_route"
    private const val COMPLETED_KEY = "completed_routes"
    private const val STATUS_KEY = "status"
    private const val KEY_ALIAS = "gativx_walkon_route_key_v1"
    private const val KEYSTORE = "AndroidKeyStore"

    fun active(context: Context): WalkOnSession? =
        readSession(context, ACTIVE_KEY)

    fun completed(context: Context): List<WalkOnSession> =
        readSessions(context, COMPLETED_KEY)

    fun pending(context: Context): List<WalkOnSession> =
        completed(context).filter { !it.synced }

    fun pendingFor(context: Context, userId: String): List<WalkOnSession> =
        completed(context).filter { !it.synced && it.ownerUserId == userId }

    fun unassigned(context: Context): List<WalkOnSession> =
        completed(context).filter { !it.synced && it.ownerUserId == null }

    fun completedFor(context: Context, userId: String): List<WalkOnSession> =
        completed(context).filter { it.ownerUserId == userId }

    fun assignUnowned(context: Context, userId: String) {
        val history = completed(context).map {
            if (it.ownerUserId == null && !it.synced) it.copy(ownerUserId = userId) else it
        }
        writeEncrypted(context, COMPLETED_KEY, encodeSessions(history))
    }

    fun status(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(STATUS_KEY, "WalkOn is ready. Start a walk when you are outdoors.") ?: "WalkOn is ready."

    fun setStatus(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(STATUS_KEY, value.take(240))
            .apply()
    }

    fun saveActive(context: Context, session: WalkOnSession) {
        writeEncrypted(context, ACTIVE_KEY, encodeSession(session))
    }

    fun clearActive(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(ACTIVE_KEY)
            .apply()
    }

    fun finishActive(
        context: Context,
        finishedAt: String,
        durationSeconds: Long,
        distanceMeters: Double,
        points: List<WalkOnPoint>
    ): WalkOnSession? {
        val current = active(context) ?: return null
        val finished = current.copy(
            finishedAt = finishedAt,
            durationSeconds = durationSeconds.coerceIn(0, 86_400),
            distanceMeters = distanceMeters.coerceAtLeast(0.0),
            points = points.toList(),
            synced = false
        )
        if (finished.points.isNotEmpty()) {
            val history = completed(context).filterNot { it.id == finished.id }
                .toMutableList()
            history.add(0, finished)
            writeEncrypted(context, COMPLETED_KEY, encodeSessions(history.take(100)))
            setStatus(context, "WalkOn route saved on this device. Cloud backup is pending.")
        } else {
            setStatus(context, "No reliable GPS points were recorded. No route was saved.")
        }
        clearActive(context)
        return finished.takeIf { it.points.isNotEmpty() }
    }

    fun markSynced(context: Context, id: String) {
        val history = completed(context).map { if (it.id == id) it.copy(synced = true) else it }
        writeEncrypted(context, COMPLETED_KEY, encodeSessions(history))
    }

    private fun readSession(context: Context, key: String): WalkOnSession? {
        val raw = readEncrypted(context, key) ?: return null
        return try { decodeSession(JSONObject(raw)) } catch (_: Exception) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(key).apply()
            null
        }
    }

    private fun readSessions(context: Context, key: String): List<WalkOnSession> {
        val raw = readEncrypted(context, key) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                try { decodeSession(array.getJSONObject(index)) } catch (_: Exception) { null }
            }
        } catch (_: Exception) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(key).apply()
            emptyList()
        }
    }

    private fun writeEncrypted(context: Context, key: String, plain: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        val packed = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(encrypted, Base64.NO_WRAP)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(key, packed)
            .apply()
    }

    private fun readEncrypted(context: Context, key: String): String? {
        val packed = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(key, null) ?: return null
        return try {
            val pieces = packed.split(":", limit = 2)
            require(pieces.size == 2)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateKey(),
                GCMParameterSpec(128, Base64.decode(pieces[0], Base64.NO_WRAP))
            )
            String(cipher.doFinal(Base64.decode(pieces[1], Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (_: Exception) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(key).apply()
            null
        }
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    private fun encodePoint(point: WalkOnPoint) = JSONObject()
        .put("latitude", point.latitude)
        .put("longitude", point.longitude)
        .put("timestampMillis", point.timestampMillis)
        .put("accuracyMeters", point.accuracyMeters)
        .put("breakBefore", point.breakBefore)

    private fun decodePoint(json: JSONObject) = WalkOnPoint(
        latitude = json.getDouble("latitude"),
        longitude = json.getDouble("longitude"),
        timestampMillis = json.getLong("timestampMillis"),
        accuracyMeters = json.optDouble("accuracyMeters", 999.0),
        breakBefore = json.optBoolean("breakBefore", false)
    )

    private fun encodeSession(session: WalkOnSession): String = JSONObject()
        .put("id", session.id)
        .put("activity", session.activity)
        .put("startedAt", session.startedAt)
        .put("finishedAt", session.finishedAt ?: JSONObject.NULL)
        .put("durationSeconds", session.durationSeconds)
        .put("distanceMeters", session.distanceMeters)
        .put("synced", session.synced)
        .put("ownerUserId", session.ownerUserId ?: JSONObject.NULL)
        .put("points", JSONArray().also { array -> session.points.forEach { array.put(encodePoint(it)) } })
        .toString()

    private fun decodeSession(json: JSONObject): WalkOnSession {
        val pointsJson = json.optJSONArray("points") ?: JSONArray()
        val points = (0 until pointsJson.length()).mapNotNull { index ->
            try { decodePoint(pointsJson.getJSONObject(index)) } catch (_: Exception) { null }
        }
        return WalkOnSession(
            id = json.getString("id"),
            activity = json.optString("activity", "Walking"),
            startedAt = json.getString("startedAt"),
            finishedAt = json.optString("finishedAt").takeIf { it.isNotBlank() && it != "null" },
            durationSeconds = json.optLong("durationSeconds", 0),
            distanceMeters = json.optDouble("distanceMeters", 0.0),
            points = points,
            synced = json.optBoolean("synced", false),
            ownerUserId = json.optString("ownerUserId").takeIf { it.isNotBlank() && it != "null" }
        )
    }

    private fun encodeSessions(sessions: List<WalkOnSession>): String =
        JSONArray().also { array -> sessions.forEach { array.put(JSONObject(encodeSession(it))) } }.toString()
}
