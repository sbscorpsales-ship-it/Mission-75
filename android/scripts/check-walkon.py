from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text()
service = (ROOT / "android/app/src/main/java/com/paramitsolutions/gativx/WalkOnLocationService.kt").read_text()
store = (ROOT / "android/app/src/main/java/com/paramitsolutions/gativx/WalkOnStore.kt").read_text()
activity = (ROOT / "android/app/src/main/java/com/paramitsolutions/gativx/MainActivity.kt").read_text()

checks = {
    "Android Health Connect preserves existing non-Health-Connect step values": (
        "remoteHasSteps = remote != null && !remote.isNull(\"steps\")" in activity
        and "remoteStepsSource != \"health_connect\"" in activity
        and "remoteStepsAt.isAfter(localMeasuredAt)" in activity
    ),
    "Android Health Connect preserves legacy and other-source active energy": (
        "remoteHasEnergy = remote != null && !remote.isNull(\"active_energy_kcal\")" in activity
        and "remoteEnergySource != \"health_connect\"" in activity
        and "remoteEnergyAt.isAfter(localMeasuredAt)" in activity
    ),
    "location foreground-service permissions": (
        'android.permission.FOREGROUND_SERVICE_LOCATION' in manifest
        and 'android:foregroundServiceType="location"' in manifest
        and 'android.permission.ACCESS_FINE_LOCATION' in manifest
    ),
    "screen-locked foreground tracking lifecycle": (
        "startForeground(" in service
        and "START_STICKY" in service
        and "requestLocationUpdates" in service
        and "ACTION_STOP" in service
    ),
    "dashboard refreshes from scoped service broadcasts": (
        "ACTION_UPDATED" in service
        and "broadcastUpdate()" in service
        and "ContextCompat.registerReceiver" in activity
    ),
    "GPS accuracy and jump filters": (
        "MAX_ACCURACY_METERS = 50f" in service
        and "MAX_JUMP_METERS = 150f" in service
        and "MAX_SPEED_METERS_PER_SECOND = 8.0" in service
        and "MAX_GAP_SECONDS = 30.0" in service
    ),
    "route distance never bridges a broken segment": (
        "if (!breakBefore) distanceMeters += delta.toDouble()" in service
        and "if (points[index].breakBefore) continue" in activity
    ),
    "GPS jump becomes a new segment anchor, not a permanent tracking stop": (
        "Keep this fix as a new segment anchor" in service
        and "segmentBreak = true\n                return" not in service
    ),
    "encrypted local route storage": (
        'Cipher.getInstance("AES/GCM/NoPadding")' in store
        and 'KeyStore.getInstance(KEYSTORE)' in store
    ),
    "completed GPS history is synchronously committed and read back before active draft deletion": (
        "val committed = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()" in store
        and ".commit()" in store
        and "committed && readEncrypted(context, key) == plain" in store
        and "if (!writeEncrypted(context, COMPLETED_KEY, encodedHistory))" in store
        and store.index("if (!writeEncrypted(context, COMPLETED_KEY, encodedHistory))") < store.index("clearActive(context)", store.index("fun finishActive"))
    ),
    "route-save verification failure is not mislabeled as an empty GPS recording": (
        "points.isNotEmpty() -> \"WalkOn could not verify the completed route history write" in service
        and "Your active GPS draft has been retained" in service
    ),
    "route history is isolated by account": (
        "ownerUserId" in store
        and "pendingFor(context, currentSession.userId)" in activity
        and "require(walk.ownerUserId == session.userId)" in activity
        and "assignUnowned(context, userId)" in activity
    ),
    "cloud route sync preserves unknown steps": (
        "/rest/v1/rpc/sync_walk_session_route" in activity
        and '.put("p_steps", walk.sessionSteps.takeIf { it > 0 }?.let { it } ?: JSONObject.NULL)' in activity
    ),
    "route sync keeps retryable local history": (
        "WalkOnStore.markSynced(context, walk.id)" in activity
        and "WalkOnStore.pendingFor" in activity
    ),
    "corrupt or undecryptable route data is never deleted": (
        ".edit().remove(key).apply()" not in store
        and "getExistingKey()" in store
        and "encrypted original was preserved" in store
    ),
    "corrupt route history blocks destructive rewrites and preserves active drafts": (
        "readSessions(context, COMPLETED_KEY) ?: run" in store
        and "Your active route draft is preserved" in store
        and "mapNotNull" not in store.split("private fun readSessions", 1)[1].split("private fun writeEncrypted", 1)[0]
    ),
    "rotated Supabase tokens are saved before retry": activity.count("SessionVault.save(context, activeSession)") >= 3,
}

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    raise SystemExit("WalkOn safeguards missing: " + ", ".join(failed))
