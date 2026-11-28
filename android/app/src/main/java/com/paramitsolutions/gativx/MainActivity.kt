package com.paramitsolutions.gativx

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
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
import androidx.compose.material3.darkColorScheme
import androidx.compose.ui.Alignment
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
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
private const val ACTION_GativX_APP_RESUMED = "com.paramitsolutions.gativx.APP_RESUMED"

data class GativxSession(val userId: String, val accessToken: String, val refreshToken: String)
data class DailyHealthSnapshot(val date: String, val steps: Long?, val activeEnergyKcal: Double?, val measuredAt: String)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { GativxAndroidScreen() }
    }

    override fun onResume() {
        super.onResume()
        sendBroadcast(Intent(ACTION_GativX_APP_RESUMED).setPackage(packageName))
    }
}

@Composable
private fun GativxAndroidScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // Explicit high-contrast auth field colours prevent OEM/theme defaults from
    // making typed email/password text disappear on darker handset displays.
    val authFieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = Color.White,
        unfocusedTextColor = Color.White,
        disabledTextColor = Color(0xFF9DAEB6),
        errorTextColor = Color(0xFFFFDAD6),
        focusedContainerColor = Color(0xFF17232A),
        unfocusedContainerColor = Color(0xFF17232A),
        disabledContainerColor = Color(0xFF17232A),
        errorContainerColor = Color(0xFF17232A),
        cursorColor = Color(0xFFD8FF3E),
        errorCursorColor = Color(0xFFFFB4AB),
        focusedBorderColor = Color(0xFFD8FF3E),
        unfocusedBorderColor = Color(0xFF9DAEB6),
        disabledBorderColor = Color(0xFF60727B),
        errorBorderColor = Color(0xFFFFB4AB),
        focusedLabelColor = Color(0xFFD8FF3E),
        unfocusedLabelColor = Color(0xFFB8C5CC),
        disabledLabelColor = Color(0xFF9DAEB6),
        errorLabelColor = Color(0xFFFFB4AB)
    )
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
    var confirmPassword by remember { mutableStateOf("") }
    var isRegistering by remember { mutableStateOf(false) }
    var selectedFeature by remember { mutableStateOf("Home") }
    var selectedSubsection by remember { mutableStateOf<String?>(null) }
    var session by remember { mutableStateOf(SessionVault.load(context)) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Connect Health Connect to read today's measured activity.") }
    var activeWalk by remember { mutableStateOf(WalkOnStore.active(context)?.takeIf { it.ownerUserId == session?.userId }) }
    var latestWalk by remember { mutableStateOf(session?.userId?.let { WalkOnStore.completedFor(context, it).firstOrNull() } ?: if (session == null) WalkOnStore.unassigned(context).firstOrNull() else null) }
    var walkStatus by remember { mutableStateOf(WalkOnStore.status(context)) }
    var walkSyncBusy by remember { mutableStateOf(false) }
    var walkRevision by remember { mutableStateOf(0) }

    val locationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        if (result[Manifest.permission.ACCESS_FINE_LOCATION] == true) {
            startWalkOnService(context)
            walkStatus = "Starting GativX™ Activity GPS tracking…"
        } else {
            walkStatus = "Precise location permission is required for reliable GativX™ Activity route recording."
        }
    }

    fun startWalkOn() {
        val existingWalk = WalkOnStore.active(context)
        if (existingWalk != null && existingWalk.ownerUserId != session?.userId) {
            walkStatus = "A GativX™ Activity route belongs to another account or was recorded offline. Finish or explicitly assign it before starting a new route."
            return
        }
        val requested = buildList {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                add(Manifest.permission.ACCESS_FINE_LOCATION)
                add(Manifest.permission.ACCESS_COARSE_LOCATION)
            }
            if (Build.VERSION.SDK_INT >= 29 &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
                add(Manifest.permission.ACTIVITY_RECOGNITION)
            }
            if (Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        if (requested.isEmpty()) {
            startWalkOnService(context)
            walkStatus = "Starting GativX™ Activity GPS and measured step tracking…"
        } else {
            locationPermissionLauncher.launch(requested.toTypedArray())
        }
    }

    fun stopWalkOn() {
        context.startService(
            Intent(context, WalkOnLocationService::class.java).setAction(WalkOnLocationService.ACTION_STOP)
        )
        walkStatus = "Finishing and saving your GativX™ Activity route…"
    }

    fun syncWalkOnRoutes() {
        val currentSession = session ?: run {
            walkStatus = "Sign in to back up saved GativX™ Activity routes."
            return
        }
        val pending = WalkOnStore.pendingFor(context, currentSession.userId)
        if (pending.isEmpty()) {
            walkStatus = if (WalkOnStore.unassigned(context).isNotEmpty()) {
                "Some routes were recorded while signed out. Assign them to this account explicitly before upload."
            } else {
                "All saved GativX™ Activity routes for this account are already backed up."
            }
            return
        }
        scope.launch {
            walkSyncBusy = true
            try {
                var activeSession = currentSession
                for (walk in pending) {
                    activeSession = SupabaseApi.syncWalkSessionRoute(context, activeSession, walk)
                    SessionVault.save(context, activeSession)
                    WalkOnStore.markSynced(context, walk.id)
                }
                session = activeSession
                walkStatus = "GativX™ Activity route backup complete. Your GPS history is in your GativX™ account."
                WalkOnStore.setStatus(context, walkStatus)
            } catch (error: Exception) {
                session = SessionVault.load(context) ?: currentSession
                walkStatus = error.message ?: "GativX™ Activity cloud backup failed. Your encrypted local route remains saved."
                WalkOnStore.setStatus(context, walkStatus)
            } finally {
                latestWalk = WalkOnStore.completedFor(context, currentSession.userId).firstOrNull()
                walkSyncBusy = false
            }
        }
    }

    DisposableEffect(context) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context?, intent: Intent?) {
                walkRevision += 1
            }
        }
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(WalkOnLocationService.ACTION_UPDATED),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        onDispose { runCatching { context.unregisterReceiver(receiver) } }
    }

    LaunchedEffect(walkRevision, session?.userId) {
        val storedActive = WalkOnStore.active(context)
        activeWalk = storedActive?.takeIf { it.ownerUserId == session?.userId }
        latestWalk = if (session != null) {
            WalkOnStore.completedFor(context, session!!.userId).firstOrNull()
        } else {
            WalkOnStore.unassigned(context).firstOrNull()
        }
        walkStatus = WalkOnStore.status(context)
    }

    LaunchedEffect(session?.userId) {
        val userId = session?.userId ?: return@LaunchedEffect
        if (WalkOnStore.pendingFor(context, userId).isNotEmpty()) {
            syncWalkOnRoutes()
        }
    }

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
        steps = if (canReadSteps) {
            val response = client.aggregate(
                AggregateRequest(metrics = setOf(StepsRecord.COUNT_TOTAL), timeRangeFilter = TimeRangeFilter.between(start, end))
            )
            response[StepsRecord.COUNT_TOTAL]
        } else null
        activeEnergy = if (canReadEnergy) {
            val response = client.aggregate(
                AggregateRequest(metrics = setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL), timeRangeFilter = TimeRangeFilter.between(start, end))
            )
            response[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories
        } else null
        measuredDate = today.toString()
        measuredAt = Instant.now().toString()
        healthReady = true
        status = when {
            steps == null && activeEnergy == null -> "Health Connect is connected, but it has no measured values for the permitted data types today."
            !canReadSteps || !canReadEnergy -> "Partial Health Connect access. Available measured values were refreshed; denied metrics remain unknown."
            else -> "Measured Health Connect data refreshed. No estimates have been added."
        }

        // A successful device read should not require a second manual button press
        // to reach the signed-in member's private GativX account.
        val currentSession = session
        if (currentSession != null && (steps != null || activeEnergy != null)) {
            val snapshot = DailyHealthSnapshot(
                measuredDate,
                steps,
                activeEnergy,
                measuredAt ?: Instant.now().toString()
            )
            try {
                val refreshedSession = SupabaseApi.syncDaily(context, currentSession, snapshot)
                SessionVault.save(context, refreshedSession)
                session = refreshedSession
                status += " Cloud backup complete for $measuredDate."
            } catch (error: Exception) {
                session = SessionVault.load(context) ?: currentSession
                status += " Cloud sync pending: ${error.message ?: "your measured data remains on this device"}."
            }
        }
    }

    // Reconnect silently on launch when the member previously granted Health Connect access.
    // No permission dialog is ever started from this automatic path.
    LaunchedEffect(Unit) {
        val sdkStatus = HealthConnectClient.getSdkStatus(context, HEALTH_CONNECT_PROVIDER)
        if (sdkStatus == HealthConnectClient.SDK_AVAILABLE) {
            try {
                val client = HealthConnectClient.getOrCreate(context)
                val granted = client.permissionController.getGrantedPermissions()
                if (healthPermissions.any { it in granted }) {
                    healthClient = client
                    refreshHealthData()
                }
            } catch (error: Exception) {
                status = error.message ?: "Could not reconnect to Health Connect."
            }
        }
    }

    // Refresh measured aggregates whenever the app returns to the foreground.
    // This never launches a permission prompt: it only reads permissions already granted.
    DisposableEffect(context, healthClient) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context?, intent: Intent?) {
                if (healthClient != null) {
                    scope.launch {
                        try { refreshHealthData() }
                        catch (error: Exception) {
                            status = error.message ?: "Could not refresh Health Connect data."
                        }
                    }
                }
            }
        }
        ContextCompat.registerReceiver(context, receiver, IntentFilter(ACTION_GativX_APP_RESUMED), ContextCompat.RECEIVER_NOT_EXPORTED)
        onDispose { runCatching { context.unregisterReceiver(receiver) } }
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
                        val missingPermissions = healthPermissions - granted
                        if (missingPermissions.isEmpty()) refreshHealthData()
                        else permissionLauncher.launch(missingPermissions)
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

    fun register() {
        val cleanEmail = email.trim()
        if (cleanEmail.isBlank() || !android.util.Patterns.EMAIL_ADDRESS.matcher(cleanEmail).matches()) {
            status = "Enter a valid email address to create your GativX™ account."
            return
        }
        if (password.length < 8) {
            status = "Choose a password with at least 8 characters."
            return
        }
        if (password != confirmPassword) {
            status = "Your passwords do not match. Please check and try again."
            return
        }
        scope.launch {
            busy = true
            try {
                val createdSession = SupabaseApi.signUp(cleanEmail, password)
                password = ""
                confirmPassword = ""
                if (createdSession != null) {
                    SessionVault.save(context, createdSession)
                    session = createdSession
                    isRegistering = false
                    status = "Welcome to GativX™! Your account is created and you are signed in securely."
                } else {
                    isRegistering = false
                    status = "Account request received. Check your email and confirm your address, then return here and sign in."
                }
            } catch (error: Exception) {
                status = error.message ?: "Could not create your GativX™ account. Please try again."
            } finally { busy = false }
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
                val signedIn = SupabaseApi.signIn(email.trim(), password)
                SessionVault.save(context, signedIn)
                session = signedIn
                password = ""
                status = "Signed in securely. Your session is encrypted on this device."
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
                val refreshedSession = SupabaseApi.syncDaily(context, currentSession, snapshot)
                SessionVault.save(context, refreshedSession)
                session = refreshedSession
                status = "Cloud backup complete for $measuredDate. Measured values only."
            } catch (error: Exception) {
                session = SessionVault.load(context) ?: currentSession
                status = error.message ?: "Cloud sync failed. Your Health Connect data remains on this device."
            } finally { busy = false }
        }
    }

    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Color(0xFFD8FF3E), onPrimary = Color(0xFF111820),
            background = Color(0xFF0B1115), onBackground = Color.White,
            surface = Color(0xFF17232A), onSurface = Color.White,
            onSurfaceVariant = Color(0xFFB8C5CC), outline = Color(0xFF9DAEB6),
            secondary = Color(0xFFD8FF3E), onSecondary = Color(0xFF111820)
        )
    ) {
        Surface(Modifier.fillMaxSize(), color = Color(0xFF0B1115)) {
            Column(Modifier.fillMaxSize()) {
                Column(
                    modifier = Modifier.weight(1f).fillMaxWidth()
                        .verticalScroll(rememberScrollState()).padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Text("GativX™", color = Color(0xFFD8FF3E), fontSize = 32.sp, fontWeight = FontWeight.Black)
                    Text("MOVE. GROW. EXCEL.", color = Color(0xFF9DAEB6), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    Text(
                        when (selectedFeature) {
                            "Home" -> "YOUR DAILY COMMAND CENTRE"
                            "Missions" -> "PURPOSE · GOALS · COMMITMENTS"
                            "Activity" -> "MEASURED MOVEMENT · GativX™ Activity"
                            "Community" -> "GROW TOGETHER · SUPPORT EACH OTHER"
                            "Guru" -> "YOUR PERSONAL GROWTH COMPANION"
                            else -> "YOUR IDENTITY · DEVICES · SETTINGS"
                        },
                        color = Color(0xFFD8FF3E), fontSize = 11.sp, fontWeight = FontWeight.Bold
                    )

                    if (selectedSubsection != null) {
                        when (selectedSubsection) {
                            "Purpose & Ikigai" -> GativxPurposeScreen(onBack = { selectedSubsection = null })
                            "Explore & Listen" -> GativxExploreListenScreen(onBack = { selectedSubsection = null })
                            else -> GativxSubsectionScreen(
                                parent = selectedFeature,
                                title = selectedSubsection!!,
                                onBack = { selectedSubsection = null }
                            )
                        }
                    } else {
                        when (selectedFeature) {
                            "Home" -> {
                                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                                    Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Text("TODAY, ONE STEP AT A TIME", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                                        Text("Your measured progress, your personal mission and one achievable next action.", color = Color(0xFF9DAEB6), fontSize = 12.sp)
                                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                            MetricTile("TODAY'S STEPS", steps?.toString() ?: "—", Modifier.weight(1f))
                                            MetricTile("ACTIVE ENERGY", activeEnergy?.let { "${it.toInt()} kcal" } ?: "—", Modifier.weight(1f))
                                        }
                                        Text(
                                            if (healthReady) "Measured source: Health Connect" else "Connect a health data source in Activity to see measured progress.",
                                            color = if (healthReady) Color(0xFFD8FF3E) else Color(0xFF9DAEB6),
                                            fontSize = 11.sp
                                        )
                                        Button(
                                            onClick = { if (activeWalk == null) startWalkOn() else selectedFeature = "Activity" },
                                            modifier = Modifier.fillMaxWidth(),
                                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD8FF3E), contentColor = Color(0xFF111820))
                                        ) {
                                            Text(if (activeWalk == null) "Start GativX™ Activity" else "View active GativX™ Activity", fontWeight = FontWeight.Bold)
                                        }
                                        Text("Your movement records live in Activity. Your goals live in Missions. Your purpose reflections live in Purpose & Ikigai. Guru helps you reconnect with your why.", color = Color(0xFFB8C5CC), fontSize = 11.sp)
                                        Button(onClick = { selectedFeature = "Guru" }, modifier = Modifier.fillMaxWidth()) { Text("Talk to Guru") }
                                        Button(onClick = { selectedSubsection = "Purpose & Ikigai" }, modifier = Modifier.fillMaxWidth()) { Text("Open Purpose & Ikigai") }
                                        Button(onClick = { selectedSubsection = "Explore & Listen" }, modifier = Modifier.fillMaxWidth()) { Text("Explore & Listen") }
                                    }
                                }
                            }
                            "Missions" -> GativxSectionLanding(
                                title = "Your goals begin with your purpose",
                                description = "Connect each goal to the personal meaning and emotion that make it matter.",
                                sections = listOf(
                                    "Purpose & Ikigai" to "Explore what you love, your strengths, what the world needs and what gives you energy",
                                    "My Goals" to "Set meaningful 30, 90, 180 and 365-day goals",
                                    "Challenges" to "Track commitments and shared challenges",
                                    "Milestones & Habits" to "Build consistency through achievable next actions",
                                    "Explore & Listen" to "YouTube, music, podcasts and guided audio"
                                ),
                                onOpen = { selectedSubsection = it }
                            )
                            "Community" -> GativxCommunityScreen()
                            "Activity" -> {
                                                Text("Android Health Connect", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)

                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("TODAY'S MEASURED ACTIVITY", color = Color(0xFFD8FF3E), fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        Text(measuredDate, color = Color(0xFF9DAEB6), fontSize = 12.sp)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            MetricTile("STEPS", steps?.toString() ?: "—", Modifier.weight(1f))
                            MetricTile("ACTIVE ENERGY", activeEnergy?.let { "${it.toInt()} kcal" } ?: "—", Modifier.weight(1f))
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
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("GativX™ Activity · GPS ROUTE TRACKING", color = Color(0xFFD8FF3E), fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        val foreignActiveWalk = WalkOnStore.active(context) != null && activeWalk == null
                        if (foreignActiveWalk) {
                            Text("A GativX™ Activity route from another account or an offline session is active. Its route details are hidden here.", color = Color(0xFFFFC66D), fontSize = 12.sp)
                            Button(onClick = { stopWalkOn() }, enabled = !busy && !walkSyncBusy, modifier = Modifier.fillMaxWidth()) {
                                Text("Finish active device route")
                            }
                        } else if (activeWalk != null) {
                            Text("RECORDING · %.2f km · %d GPS points".format(activeWalk!!.distanceMeters / 1000.0, activeWalk!!.points.size), color = Color.White, fontWeight = FontWeight.Bold)
                            Button(onClick = { stopWalkOn() }, enabled = !busy && !walkSyncBusy, modifier = Modifier.fillMaxWidth()) {
                                Text("Finish & save GativX™ Activity")
                            }
                        } else {
                            Text("Record a GPS route while your screen is locked. Precise location and the ongoing notification are required.", color = Color(0xFF9DAEB6), fontSize = 12.sp)
                            Button(
                                onClick = { startWalkOn() },
                                enabled = !busy && !walkSyncBusy,
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD8FF3E), contentColor = Color(0xFF111820))
                            ) { Text("Start GativX™ Activity", fontWeight = FontWeight.Bold) }
                        }
                        val routePreviewPoints = activeWalk?.points?.takeIf { it.size > 1 }
                            ?: latestWalk?.points?.takeIf { it.size > 1 }
                        if (routePreviewPoints != null) {
                            WalkOnRoutePreview(routePreviewPoints)
                            Text("GPS route trace preview · not a street map", color = Color(0xFF9DAEB6), fontSize = 10.sp)
                        }
                        latestWalk?.let { walk ->
                            Text(
                                "Last route · %.2f km · %d seconds · %d measured steps".format(walk.distanceMeters / 1000.0, walk.durationSeconds, walk.sessionSteps),
                                color = Color.White,
                                fontSize = 12.sp
                            )
                            Text(
                                if (walk.synced) "CLOUD BACKUP · COMPLETE" else "SAVED ON DEVICE · BACKUP PENDING",
                                color = if (walk.synced) Color(0xFFD8FF3E) else Color(0xFFFFC66D),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                        val pendingWalkCount = session?.userId?.let { WalkOnStore.pendingFor(context, it).size } ?: 0
                        val unassignedWalkCount = WalkOnStore.unassigned(context).size
                        if (session != null && unassignedWalkCount > 0) {
                            Button(
                                onClick = {
                                    val userId = session?.userId
                                    if (userId != null) {
                                        WalkOnStore.assignUnowned(context, userId)
                                        WalkOnStore.setStatus(context, "Device-only routes assigned to this account by your request.")
                                        walkStatus = WalkOnStore.status(context)
                                        syncWalkOnRoutes()
                                    }
                                },
                                enabled = !busy && !walkSyncBusy && activeWalk == null && !foreignActiveWalk,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("Assign offline routes to this account ($unassignedWalkCount)")
                            }
                        } else if (session == null && unassignedWalkCount > 0) {
                            Text("$unassignedWalkCount device-only route(s) saved while signed out. Sign in to choose an account before uploading.", color = Color(0xFF9DAEB6), fontSize = 11.sp)
                        }
                        if (pendingWalkCount > 0) {
                            Button(
                                onClick = { syncWalkOnRoutes() },
                                enabled = session != null && !busy && !walkSyncBusy && activeWalk == null && !foreignActiveWalk,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(if (walkSyncBusy) "Backing up routes…" else "Sync saved routes ($pendingWalkCount)")
                            }
                        }
                        Text(walkStatus, color = Color(0xFF9DAEB6), fontSize = 11.sp)
                    }
                }
                                                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                    Column(Modifier.padding(16.dp)) {
                        Text("STATUS", color = Color(0xFFD8FF3E), fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        Spacer(Modifier.height(8.dp))
                        Text(status, color = Color.White, fontSize = 14.sp)
                        Text("GativX™ reads aggregated Health Connect totals to reduce duplicate-source counting. It does not estimate missing steps or calories.", color = Color(0xFF9DAEB6), fontSize = 11.sp)
                        Text("Your session is encrypted with Android Keystore and can be revoked when you sign out.", color = Color(0xFF9DAEB6), fontSize = 11.sp)
                    }
                }
                            }
                            "Guru" -> GativxSectionLanding(
                                title = "Guidance for your whole journey",
                                description = "A single place for coaching, wellbeing, nutrition and personal growth.",
                                sections = listOf(
                                    "Guru Coach" to "Purpose-led reflection and your next achievable action",
                                    "Wellness & Recovery" to "Sleep, rest, stress and hydration",
                                    "Nutrition" to "Food diary and practical nutrition guidance",
                                    "Explore & Listen" to "YouTube-first discovery, music, podcasts and guided audio",
                                    "Learning Library" to "Habits, self-control and personal development"
                                ),
                                onOpen = { selectedSubsection = it }
                            )
                            "Profile" -> {
                                                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("PRIVATE CLOUD BACKUP", color = Color.White, fontWeight = FontWeight.Bold)
                        if (session == null) {
                            Text(
                                if (isRegistering) "Create your free GativX™ account to keep your walks and measured activity backed up privately."
                                else "Sign in to access your private GativX™ cloud backup, or create a free account to get started.",
                                color = Color(0xFF9DAEB6),
                                fontSize = 12.sp
                            )
                            OutlinedTextField(value = email, onValueChange = { email = it }, label = { Text("Email") }, singleLine = true, modifier = Modifier.fillMaxWidth(), colors = authFieldColors)
                            OutlinedTextField(value = password, onValueChange = { password = it }, label = { Text(if (isRegistering) "Create password (8+ characters)" else "Password") }, visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth(), colors = authFieldColors)
                            if (isRegistering) {
                                OutlinedTextField(value = confirmPassword, onValueChange = { confirmPassword = it }, label = { Text("Confirm password") }, visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth(), colors = authFieldColors)
                                Button(onClick = { register() }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                                    Text(if (busy) "Creating account…" else "Create GativX™ Account")
                                }
                                TextButtonCompat(
                                    text = "Already have an account? Sign in",
                                    enabled = !busy,
                                    onClick = { isRegistering = false; password = ""; confirmPassword = "" }
                                )
                            } else {
                                Button(onClick = { signIn() }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(if (busy) "Signing in…" else "Sign in to GativX™") }
                                TextButtonCompat(
                                    text = "New to GativX™? Create a free account",
                                    enabled = !busy,
                                    onClick = { isRegistering = true; password = ""; confirmPassword = "" }
                                )
                            }
                        } else {
                            Text("Signed in · ${session?.userId?.take(8)}…", color = Color(0xFFD8FF3E))
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Button(onClick = { syncToCloud() }, enabled = !busy && healthReady) { Text("Sync measured data") }
                                Button(
                                    onClick = {
                                        val activeSession = session
                                        scope.launch {
                                            busy = true
                                            try {
                                                if (activeSession != null) SupabaseApi.signOut(activeSession)
                                                status = "Signed out. Health readings remain on this device."
                                            } catch (_: Exception) {
                                                status = "Signed out on this device. Server revocation could not be confirmed."
                                            } finally {
                                                SessionVault.clear(context)
                                                session = null
                                                busy = false
                                            }
                                        }
                                    },
                                    enabled = !busy && !walkSyncBusy && WalkOnStore.active(context) == null
                                ) { Text("Sign out") }
                            }
                        }
                    }
                }
                                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text("PARAM IT SOLUTIONS", color = Color(0xFFD8FF3E), fontWeight = FontWeight.Bold)
                                        Text("GativX™ · MOVE. GROW. EXCEL.", color = Color.White, fontWeight = FontWeight.Bold)
                                        Text("Company information, connected devices, privacy, preferences, referrals and support belong here as their respective workflows are released.", color = Color(0xFF9DAEB6), fontSize = 12.sp)
                                    }
                                }
                            }
                        }
                    }
                }
                Row(
                    Modifier.fillMaxWidth().background(Color(0xFF111B21)).padding(horizontal = 4.dp, vertical = 5.dp),
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    listOf("Home", "Activity", "Missions", "Community", "Profile").forEach { destination ->
                        TextButton(
                            onClick = { selectedFeature = destination; selectedSubsection = null },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(
                                destination,
                                color = if (selectedFeature == destination) Color(0xFFD8FF3E) else Color(0xFF9DAEB6),
                                fontSize = 10.sp,
                                fontWeight = if (selectedFeature == destination) FontWeight.Bold else FontWeight.Medium
                            )
                        }
                    }
                }
            }
        }
    }
}



@Composable
private fun GativxPurposeScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember(context) { context.getSharedPreferences("gativx_purpose_reflections", Context.MODE_PRIVATE) }
    var love by remember { mutableStateOf(prefs.getString("love", "") ?: "") }
    var strengths by remember { mutableStateOf(prefs.getString("strengths", "") ?: "") }
    var needs by remember { mutableStateOf(prefs.getString("needs", "") ?: "") }
    var energy by remember { mutableStateOf(prefs.getString("energy", "") ?: "") }
    var purpose by remember { mutableStateOf(prefs.getString("purpose", "") ?: "") }
    var saved by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        TextButton(onClick = onBack) { Text("Back to Missions", color = Color(0xFFD8FF3E)) }
        Text("PURPOSE & IKIGAI", color = Color(0xFFD8FF3E), fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Text("Find the meaning behind the goal", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text("Your reflections are saved on this device only in this version; they are not uploaded to your account.", color = Color(0xFFB8C5CC), fontSize = 12.sp)
        OutlinedTextField(love, { love = it; saved = false }, label = { Text("What do I love?") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
        OutlinedTextField(strengths, { strengths = it; saved = false }, label = { Text("What am I good at?") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
        OutlinedTextField(needs, { needs = it; saved = false }, label = { Text("What does the world need that I care about?") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
        OutlinedTextField(energy, { energy = it; saved = false }, label = { Text("What gives me energy, and what can I be paid for?") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
        OutlinedTextField(purpose, { purpose = it; saved = false }, label = { Text("My purpose — in my own words") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
        Button(onClick = {
            prefs.edit().putString("love", love).putString("strengths", strengths).putString("needs", needs).putString("energy", energy).putString("purpose", purpose).apply()
            saved = true
        }, modifier = Modifier.fillMaxWidth()) { Text("Save my reflections on this device") }
        if (saved) Text("Saved on this device.", color = Color(0xFFD8FF3E), fontSize = 12.sp)
        Text("Next step: connect this purpose to one meaningful goal and one small action.", color = Color(0xFFB8C5CC), fontSize = 12.sp)
    }
}

@Composable
private fun GativxExploreListenScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    var language by remember { mutableStateOf("English") }
    val languages = listOf("Hindi", "Kannada", "Marathi", "English", "Telugu", "Tamil")
    val topics = listOf("Walking motivation and self-control", "Personal growth and discipline", "Mindfulness and meditation", "Yoga and Tai Chi walking", "Zumba, gym and strength training", "Diet and nutrition")
    fun openYouTube(query: String) {
        val url = "https://www.youtube.com/results?search_query=" + Uri.encode(query)
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        TextButton(onClick = onBack) { Text("Back", color = Color(0xFFD8FF3E)) }
        Text("EXPLORE & LISTEN", color = Color(0xFFD8FF3E), fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Text("Learn, move and reset your mind", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text("Free-first discovery. YouTube opens in its official app or website. Check the creator, content and provider restrictions before playing.", color = Color(0xFFB8C5CC), fontSize = 12.sp)
        Text("Choose language", color = Color.White, fontWeight = FontWeight.Bold)
        languages.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { item ->
                    TextButton(onClick = { language = item }) {
                        Text(item, color = if (language == item) Color(0xFFD8FF3E) else Color(0xFFB8C5CC), fontWeight = if (language == item) FontWeight.Bold else FontWeight.Normal)
                    }
                }
            }
        }
        Text("YouTube · first-class discovery", color = Color(0xFFD8FF3E), fontWeight = FontWeight.Bold)
        topics.forEach { topic ->
            Card(modifier = Modifier.fillMaxWidth().clickable { openYouTube("$topic $language") }, colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
                Column(Modifier.fillMaxWidth().padding(14.dp)) {
                    Text(topic, color = Color.White, fontWeight = FontWeight.Bold)
                    Text("Search YouTube in $language", color = Color(0xFFB8C5CC), fontSize = 11.sp)
                }
            }
        }
        Text("Music · Podcasts · Guided Audio", color = Color(0xFFD8FF3E), fontWeight = FontWeight.Bold)
        listOf("Walking music", "Personal-growth podcasts", "Guided meditation and breathing").forEach { topic ->
            Button(onClick = { openYouTube("$topic $language") }, modifier = Modifier.fillMaxWidth()) { Text("$topic · $language") }
        }
        Text("This is discovery search, not an editorially verified channel catalogue. Provider ads, account limits, background play and offline rules apply. Listening time never contributes to activity metrics.", color = Color(0xFFB8C5CC), fontSize = 11.sp)
    }
}

@Composable
private fun GativxCommunityScreen() {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("COMMUNITY", color = Color(0xFFD8FF3E), fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Text("Grow together", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text("The Community destination is restored in the approved navigation. A live member feed, posts, comments and moderation are not yet connected to an account-scoped backend, so no sample members or fabricated posts are shown.", color = Color(0xFFB8C5CC), fontSize = 13.sp)
        Button(onClick = {
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, "I'm working towards a meaningful goal with GativX™. Join me in moving with purpose.")
            }
            context.startActivity(Intent.createChooser(share, "Share your GativX™ journey"))
        }, modifier = Modifier.fillMaxWidth()) { Text("Invite someone to join your journey") }
        Text("Live community feed: pending backend security review and account isolation.", color = Color(0xFFFFC66D), fontSize = 11.sp)
    }
}


@Composable
private fun GativxSectionLanding(
    title: String,
    description: String,
    sections: List<Pair<String, String>>,
    onOpen: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, color = Color.White, fontSize = 21.sp, fontWeight = FontWeight.Bold)
        Text(description, color = Color(0xFF9DAEB6), fontSize = 13.sp)
        sections.forEach { (name, detail) ->
            Card(
                modifier = Modifier.fillMaxWidth().clickable { onOpen(name) },
                colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A)),
                shape = RoundedCornerShape(14.dp)
            ) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(name, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                    Text(detail, color = Color(0xFF9DAEB6), fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun GativxSubsectionScreen(parent: String, title: String, onBack: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF17232A))) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(parent.uppercase(), color = Color(0xFFD8FF3E), fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(title, color = Color.White, fontSize = 21.sp, fontWeight = FontWeight.Bold)
            Text(
                "This destination is now separated in the app structure. Its data and actions will be connected in a verified implementation pass. No sample records or invented measurements are displayed.",
                color = Color(0xFF9DAEB6), fontSize = 13.sp
            )
            Text("MODULE STATUS · NOT YET CONNECTED", color = Color(0xFFFFC66D), fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Button(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("Back to $parent") }
        }
    }
}

private fun startWalkOnService(context: Context) {
    val intent = Intent(context, WalkOnLocationService::class.java).setAction(WalkOnLocationService.ACTION_START)
    ContextCompat.startForegroundService(context, intent)
}

@Composable
private fun WalkOnRoutePreview(points: List<WalkOnPoint>) {
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(132.dp)
            .background(Color(0xFF0D171D), RoundedCornerShape(12.dp))
    ) {
        if (points.size < 2) return@Canvas
        val minLatitude = points.minOf { it.latitude }
        val maxLatitude = points.maxOf { it.latitude }
        val minLongitude = points.minOf { it.longitude }
        val maxLongitude = points.maxOf { it.longitude }
        val latitudeRange = (maxLatitude - minLatitude).coerceAtLeast(0.000001)
        val longitudeRange = (maxLongitude - minLongitude).coerceAtLeast(0.000001)
        val inset = 12.dp.toPx()
        val drawWidth = (size.width - inset * 2).coerceAtLeast(1f)
        val drawHeight = (size.height - inset * 2).coerceAtLeast(1f)
        fun position(point: WalkOnPoint): Offset = Offset(
            inset + ((point.longitude - minLongitude) / longitudeRange).toFloat() * drawWidth,
            inset + ((maxLatitude - point.latitude) / latitudeRange).toFloat() * drawHeight
        )
        for (index in 1 until points.size) {
            if (points[index].breakBefore) continue
            drawLine(
                color = Color(0xFFD8FF3E),
                start = position(points[index - 1]),
                end = position(points[index]),
                strokeWidth = 4.dp.toPx(),
                cap = StrokeCap.Round
            )
        }
    }
}

@Composable
private fun FeatureHubTile(
    name: String,
    status: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val active = status == "Available"
    Card(
        modifier = modifier.clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = if (selected) Color(0xFF344329) else Color(0xFF0D171D)
        ),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            Modifier.fillMaxWidth().padding(vertical = 12.dp, horizontal = 5.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Text(name, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth())
            Text(
                status.uppercase(),
                color = if (active) Color(0xFFD8FF3E) else Color(0xFFFFC66D),
                fontSize = 8.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun TextButtonCompat(text: String, enabled: Boolean, onClick: () -> Unit) {
    TextButton(onClick = onClick, enabled = enabled, modifier = Modifier.fillMaxWidth()) {
        Text(text, color = Color(0xFFD8FF3E), fontSize = 12.sp)
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

internal object SupabaseApi {
    private const val TIMEOUT_MS = 15_000

    suspend fun signUp(email: String, password: String): GativxSession? = withContext(Dispatchers.IO) {
        val response = request("POST", "/auth/v1/signup", null,
            JSONObject().put("email", email).put("password", password).toString())
        if (response.first !in 200..299) throw IllegalStateException(parseError(response.second, "Account creation failed."))
        val json = JSONObject(response.second)
        val user = json.optJSONObject("user") ?: json
        val accessToken = json.optString("access_token")
        val refreshToken = json.optString("refresh_token")
        if (accessToken.isNotBlank() && refreshToken.isNotBlank() && user.has("id")) {
            GativxSession(user.getString("id"), accessToken, refreshToken)
        } else {
            null
        }
    }

    suspend fun signIn(email: String, password: String): GativxSession = withContext(Dispatchers.IO) {
        val response = request("POST", "/auth/v1/token?grant_type=password", null,
            JSONObject().put("email", email).put("password", password).toString())
        if (response.first !in 200..299) throw IllegalStateException(parseError(response.second, "Sign-in failed."))
        val json = JSONObject(response.second)
        GativxSession(json.getJSONObject("user").getString("id"), json.getString("access_token"), json.getString("refresh_token"))
    }

    suspend fun signOut(session: GativxSession) = withContext(Dispatchers.IO) {
        val response = request("POST", "/auth/v1/logout?scope=local", session.accessToken, "")
        if (response.first !in 200..299 && response.first != 401) {
            throw IllegalStateException(parseError(response.second, "Could not revoke the server session."))
        }
    }

    suspend fun syncWalkSessionRoute(context: Context, session: GativxSession, walk: WalkOnSession): GativxSession = withContext(Dispatchers.IO) {
        require(walk.ownerUserId == session.userId) { "This GativX™ Activity route belongs to a different account." }
        if (walk.points.isEmpty() || walk.finishedAt == null) return@withContext session
        val cloudPoints = if (walk.points.size > 20_000) {
            (0 until 20_000).map { index -> walk.points[index * (walk.points.size - 1) / 19_999] }
        } else walk.points
        val route = JSONArray()
        cloudPoints.forEach { point ->
            route.put(
                JSONObject()
                    .put("latitude", point.latitude)
                    .put("longitude", point.longitude)
                    .put("timestamp", point.timestampMillis)
                    .put("accuracy", point.accuracyMeters)
                    .put("breakBefore", point.breakBefore)
            )
        }
        val body = JSONObject()
            .put("p_session_id", walk.id)
            .put("p_started_at", walk.startedAt)
            .put("p_finished_at", walk.finishedAt)
            .put("p_duration_seconds", walk.durationSeconds.coerceIn(0, 86_400))
            .put("p_distance_m", walk.distanceMeters.coerceAtLeast(0.0))
            .put("p_steps", walk.sessionSteps.takeIf { it > 0 }?.let { it } ?: JSONObject.NULL)
            .put("p_route_points", route)
        var activeSession = session
        var response = request("POST", "/rest/v1/rpc/sync_walk_session_route", activeSession.accessToken, body.toString())
        if (response.first == 401) {
            activeSession = refresh(activeSession)
            SessionVault.save(context, activeSession)
            response = request("POST", "/rest/v1/rpc/sync_walk_session_route", activeSession.accessToken, body.toString())
        }
        if (response.first !in 200..299) {
            throw IllegalStateException(parseError(response.second, "GativX™ Activity route cloud sync failed."))
        }
        activeSession
    }

    suspend fun syncDaily(context: Context, session: GativxSession, snapshot: DailyHealthSnapshot): GativxSession = withContext(Dispatchers.IO) {
        var activeSession = session
        val lookupPath = "/rest/v1/daily_logs?select=steps,steps_source,steps_updated_at,active_energy_kcal,active_energy_source,active_energy_updated_at&user_id=eq.${session.userId}&log_date=eq.${snapshot.date}"
        var lookup = request("GET", lookupPath, activeSession.accessToken, "")
        if (lookup.first == 401) {
            activeSession = refresh(activeSession)
            SessionVault.save(context, activeSession)
            lookup = request("GET", lookupPath, activeSession.accessToken, "")
        }
        if (lookup.first !in 200..299) throw IllegalStateException(parseError(lookup.second, "Could not compare existing daily measurements."))
        val remote = JSONArray(lookup.second).optJSONObject(0)
        val localMeasuredAt = parseTimestamp(snapshot.measuredAt)
        val remoteStepsSource = remote?.optString("steps_source")?.takeIf { it.isNotBlank() }
        val remoteStepsAt = parseTimestamp(remote?.optString("steps_updated_at"))
        val remoteHasSteps = remote != null && !remote.isNull("steps")
        // Health Connect may refresh only its own previous value or an empty field.
        // Preserve manual, Apple Health, GPS/legacy and unknown-provenance values.
        val preserveRemoteSteps = remoteHasSteps && remoteStepsSource != "health_connect" ||
            (remoteStepsSource == "health_connect" && remoteStepsAt.isAfter(localMeasuredAt))
        val remoteEnergySource = remote?.optString("active_energy_source")?.takeIf { it.isNotBlank() }
        val remoteEnergyAt = parseTimestamp(remote?.optString("active_energy_updated_at"))
        val remoteHasEnergy = remote != null && !remote.isNull("active_energy_kcal")
        // Keep energy from another source (including legacy rows) intact.
        val preserveRemoteEnergy = remoteHasEnergy && remoteEnergySource != "health_connect" ||
            (remoteEnergySource == "health_connect" && remoteEnergyAt.isAfter(localMeasuredAt))

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
            SessionVault.save(context, activeSession)
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
        when (json.optString("error_code")) {
            "over_email_send_rate_limit" -> "Email verification is temporarily rate-limited. Please wait before requesting another email. If you already created an account, try signing in."
            else -> json.optString("msg").ifBlank {
                json.optString("message").ifBlank { json.optString("error_description").ifBlank { fallback } }
            }
        }
    } catch (_: Exception) { fallback }
}
