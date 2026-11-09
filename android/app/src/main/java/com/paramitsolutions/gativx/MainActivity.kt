package com.paramitsolutions.gativx

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

private const val SUPABASE_URL = "https://crarbbsvcczwmtvxyrxo.supabase.co"
private const val SUPABASE_PUBLISHABLE_KEY = "sb_publishable_XAGRFtrWrFqJ-SfXh2WbRQ_jCcPnr-6"
private const val HEALTH_CONNECT_PROVIDER = "com.google.android.apps.healthdata"

data class GativxSession(val userId: String, val accessToken: String, val refreshToken: String)
data class DailyHealthSnapshot(val date: String, val steps: Long?, val activeEnergyKcal: Double?, val measuredAt: String)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { GativxAndroidScreen() }
    }
}

@Composable
private fun GativxAndroidScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val healthPermissions = remember {
        setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class)
        )
    }
    var healthClient by remember { mutableStateOf<HealthConnectClient?>(null) }
    var healthReady by remember { mutableStateOf(false) }
    var steps by remember { mutableStateOf<Long?>(null) }
    var activeEnergy by remember { mutableStateOf<Double?>(null) }
    var measuredDate by remember { mutableStateOf(LocalDate.now().toString()) }
    var measuredAt by remember { mutableStateOf<String?>(null) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var session by remember { mutableStateOf<GativxSession?>(null) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Connect Health Connect to read today's measured activity.") }

    suspend fun refreshHealthData() {
        val client = healthClient ?: return
        val granted = client.permissionController.getGrantedPermissions()
        val canReadSteps = HealthPermission.getReadPermission(StepsRecord::class) in granted
        val canReadEnergy = HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class) in granted
        if (!canReadSteps && !canReadEnergy) {
            healthReady = false
            status = "No Health Connect read permission is enabled. Grant Steps or Active Calories to continue."
            return
        }
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val start = today.atStartOfDay(zone).toInstant()
        val end = today.plusDays(1).atStartOfDay(zone).toInstant()
        val metrics = buildSet {
            if (canReadSteps) add(StepsRecord.COUNT_TOTAL)
            if (canReadEnergy) add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
        }
        val response = client.aggregate(
            AggregateRequest(metrics = metrics, timeRangeFilter = TimeRangeFilter.between(start, end))
        )
        steps = if (canReadSteps) response[StepsRecord.COUNT_TOTAL] else null
        activeEnergy = if (canReadEnergy) response[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories else null
        measuredDate = today.toString()
        measuredAt = Instant.now().toString()
        healthReady = true
        status = when {
            steps == null && activeEnergy == null -> "Health Connect is connected, but it has no measured values for the permitted data types today."
            !canReadSteps || !canReadEnergy -> "Partial Health Connect access. Available measured values were refreshed; denied metrics remain unknown."
            else -> "Measured Health Connect data refreshed. No estimates have been added."
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        if (granted.any { it in healthPermissions }) {
            scope.launch {
                busy = true
                try { refreshHealthData() }
                catch (error: Exception) { status = error.message ?: "Could not read Health Connect data." }
                finally { busy = false }
            }
        } else {
            healthReady = false
            status = "Health Connect read access was denied. You can review permissions and try again."
        }
    }

    fun connectHealthConnect() {
        val sdkStatus = HealthConnectClient.getSdkStatus(context, HEALTH_CONNECT_PROVIDER)
        when (sdkStatus) {
            HealthConnectClient.SDK_UNAVAILABLE -> {
                status = "Health Connect is unavailable on this device. Install or enable Health Connect, then retry."
                healthReady = false
            }
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> {
                status = "Please update Health Connect from Google Play, then retry."
                healthReady = false
            }
            else -> try {
                val client = HealthConnectClient.getOrCreate(context)
                healthClient = client
                scope.launch {
                    busy = true
                    try {
                        val granted = client.permissionController.getGrantedPermissions()
                        if (granted.containsAll(healthPermissions)) refreshHealthData()
                        else permissionLauncher.launch(healthPermissions)
                    } catch (error: Exception) {
                        status = error.message ?: "Could not connect to Health Connect."
                    } finally { busy = false }
                }
            } catch (error: Exception) {
                status = error.message ?: "Could not open Health Connect."
                healthReady = false
            }
        }
    }

    fun signIn() {
        if (email.isBlank() || password.isBlank()) {
            status = "Enter your email and password to sign in."
            return
        }
        scope.launch {
            busy = true
            try {
                session = SupabaseApi.signIn(email.trim(), password)
                password = ""
                status = "Signed in. Your Health Connect readings can now be backed up to your account."
            } catch (error: Exception) {
                status = error.message ?: "Sign-in failed. Check your details and try again."
            } finally { busy = false }
        }
    }

    fun syncToCloud() {
        val currentSession = session
        if (currentSession == null) {
            status = "Sign in before syncing your health readings."
            return
        }
        if (!healthReady || (steps == null && activeEnergy == null)) {
            status = "Refresh measured Health Connect data before syncing. Unknown values will remain empty."
            return
        }
        val snapshot = DailyHealthSnapshot(measuredDate, steps, activeEnergy, measuredAt ?: Instant.now().toString())
        scope.launch {
            busy = true
            try {
                session = SupabaseApi.syncDaily(currentSession, snapshot)
                status = "Cloud backup complete for $measuredDate. Measured values only."
            } catch (error: Exception) {
                status = error.message ?: "Cloud sync failed. Your Health Connect data remains on this device."
            } finally { busy = false }
        }
    }

    MaterialTheme {
        Surface(Modifier.fillMaxSize(), color = Color(0xFF0B1115)) {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text("GATIVX", color = Color(0xFFD8FF3E), fontSize = 34.sp, fontWeight = FontWeight.Black)
                Text("MOVE. GROW. EXCEL.", color = Color(0xFF9DAEB6), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Text("Android Health Connect", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)

                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("TODAY'S MEASURED ACTIVITY", color = Color(0xFFD8FF3E), fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        Text(measuredDate, color = Color(0xFF9DAEB6), fontSize = 12.sp)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            MetricTile("STEPS", steps?.toString() ?: "—", Modifier.weight(1f))
                            MetricTile("ACTIVE ENERGY", activeEnergy?.let { "\${it.toInt()} kcal" } ?: "—", Modifier.weight(1f))
                        }
                        Button(
                            onClick = { connectHealthConnect() },
                            enabled = !busy,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD8FF3E), contentColor = Color(0xFF111820))
                        ) { Text("Connect / refresh Health Connect", fontWeight = FontWeight.Bold) }
                        Text(
                            if (healthReady) "SOURCE: HEALTH CONNECT · AGGREGATED" else "SOURCE: NOT CONNECTED",
                            color = if (healthReady) Color(0xFFD8FF3E) else Color(0xFF9DAEB6),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("PRIVATE CLOUD BACKUP", color = Color.White, fontWeight = FontWeight.Bold)
                        if (session == null) {
                            OutlinedTextField(value = email, onValueChange = { email = it }, label = { Text("Email") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = password, onValueChange = { password = it }, label = { Text("Password") }, visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth())
                            Button(onClick = { signIn() }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Sign in to GATIVX") }
                        } else {
                            Text("Signed in · \${session?.userId?.take(8)}…", color = Color(0xFFD8FF3E))
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Button(onClick = { syncToCloud() }, enabled = !busy && healthReady) { Text("Sync measured data") }
                                Button(onClick = { session = null; status = "Signed out. Health readings remain on this device." }, enabled = !busy) { Text("Sign out") }
                            }
                        }
                    }
                }

                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                    Column(Modifier.padding(16.dp)) {
                        Text("STATUS", color = Color(0xFFD8FF3E), fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        Spacer(Modifier.height(8.dp))
                        Text(status, color = Color.White, fontSize = 14.sp)
                        Text("GATIVX reads aggregated Health Connect totals to reduce duplicate-source counting. It does not estimate missing steps or calories.", color = Color(0xFF9DAEB6), fontSize = 11.sp)
                        Text("This early build keeps the sign-in session in memory; sign in again after closing the app.", color = Color(0xFF9DAEB6), fontSize = 11.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun MetricTile(label: String, value: String, modifier: Modifier = Modifier) {
    Card(modifier = modifier, colors = CardDefaults.cardColors(containerColor = Color(0xFF0D171D))) {
        Column(Modifier.padding(12.dp)) {
            Text(label, color = Color(0xFF9DAEB6), fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(value, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        }
    }
}

private object SupabaseApi {
    private const val TIMEOUT_MS = 15_000

    suspend fun signIn(email: String, password: String): GativxSession = withContext(Dispatchers.IO) {
        val response = request("POST", "/auth/v1/token?grant_type=password", null,
            JSONObject().put("email", email).put("password", password).toString())
        if (response.first !in 200..299) throw IllegalStateException(parseError(response.second, "Sign-in failed."))
        val json = JSONObject(response.second)
        GativxSession(json.getJSONObject("user").getString("id"), json.getString("access_token"), json.getString("refresh_token"))
    }

    suspend fun syncDaily(session: GativxSession, snapshot: DailyHealthSnapshot): GativxSession = withContext(Dispatchers.IO) {
        var activeSession = session
        val lookupPath = "/rest/v1/daily_logs?select=steps,steps_source,steps_updated_at,active_energy_kcal,active_energy_source,active_energy_updated_at&user_id=eq.${session.userId}&log_date=eq.${snapshot.date}"
        var lookup = request("GET", lookupPath, activeSession.accessToken, "")
        if (lookup.first == 401) {
            activeSession = refresh(activeSession)
            lookup = request("GET", lookupPath, activeSession.accessToken, "")
        }
        if (lookup.first !in 200..299) throw IllegalStateException(parseError(lookup.second, "Could not compare existing daily measurements."))
        val remote = JSONArray(lookup.second).optJSONObject(0)
        val localMeasuredAt = parseTimestamp(snapshot.measuredAt)
        val remoteStepsSource = remote?.optString("steps_source")?.takeIf { it.isNotBlank() }
        val remoteStepsAt = parseTimestamp(remote?.optString("steps_updated_at"))
        val preserveRemoteSteps = remoteStepsSource == "manual" || remoteStepsAt.isAfter(localMeasuredAt)
        val remoteEnergyAt = parseTimestamp(remote?.optString("active_energy_updated_at"))
        val preserveRemoteEnergy = remoteEnergyAt.isAfter(localMeasuredAt)

        val row = JSONObject().put("user_id", session.userId).put("log_date", snapshot.date)
        if (snapshot.steps != null && !preserveRemoteSteps) {
            row.put("steps", snapshot.steps)
                .put("steps_source", "health_connect")
                .put("steps_updated_at", snapshot.measuredAt)
        }
        if (snapshot.activeEnergyKcal != null && !preserveRemoteEnergy) {
            row.put("active_energy_kcal", snapshot.activeEnergyKcal.toInt())
                .put("active_energy_source", "health_connect")
                .put("active_energy_updated_at", snapshot.measuredAt)
        }
        if (row.length() <= 2) return@withContext activeSession

        val payload = JSONArray().put(row).toString()
        var response = request("POST", "/rest/v1/daily_logs?on_conflict=user_id,log_date", activeSession.accessToken, payload, true)
        if (response.first == 401) {
            activeSession = refresh(activeSession)
            response = request("POST", "/rest/v1/daily_logs?on_conflict=user_id,log_date", activeSession.accessToken, payload, true)
        }
        if (response.first !in 200..299) throw IllegalStateException(parseError(response.second, "Cloud sync failed."))
        activeSession
    }

    private fun parseTimestamp(value: String?): Instant = try {
        if (value.isNullOrBlank()) Instant.MIN else Instant.parse(value)
    } catch (_: Exception) {
        Instant.MIN
    }

    private suspend fun refresh(session: GativxSession): GativxSession = withContext(Dispatchers.IO) {
        val response = request("POST", "/auth/v1/token?grant_type=refresh_token", null,
            JSONObject().put("refresh_token", session.refreshToken).toString())
        if (response.first !in 200..299) throw IllegalStateException(parseError(response.second, "Your session expired. Sign in again."))
        val json = JSONObject(response.second)
        GativxSession(json.getJSONObject("user").getString("id"), json.getString("access_token"), json.getString("refresh_token"))
    }

    private fun request(method: String, path: String, bearer: String?, body: String, preferMerge: Boolean = false): Pair<Int, String> {
        val connection = (URL(SUPABASE_URL + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            doOutput = body.isNotEmpty()
            setRequestProperty("apikey", SUPABASE_PUBLISHABLE_KEY)
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
            if (bearer != null) setRequestProperty("Authorization", "Bearer $bearer")
            if (preferMerge) setRequestProperty("Prefer", "resolution=merge-duplicates,return=minimal")
        }
        return try {
            if (body.isNotEmpty()) connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader()?.use { it.readText() } ?: ""
            code to response
        } finally { connection.disconnect() }
    }

    private fun parseError(body: String, fallback: String): String = try {
        val json = JSONObject(body)
        json.optString("msg").ifBlank {
            json.optString("message").ifBlank { json.optString("error_description").ifBlank { fallback } }
        }
    } catch (_: Exception) { fallback }
}
