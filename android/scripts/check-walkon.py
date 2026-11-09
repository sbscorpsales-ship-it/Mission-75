from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text()
service = (ROOT / "android/app/src/main/java/com/paramitsolutions/gativx/WalkOnLocationService.kt").read_text()
store = (ROOT / "android/app/src/main/java/com/paramitsolutions/gativx/WalkOnStore.kt").read_text()
activity = (ROOT / "android/app/src/main/java/com/paramitsolutions/gativx/MainActivity.kt").read_text()

checks = {
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
    "encrypted local route storage": (
        'Cipher.getInstance("AES/GCM/NoPadding")' in store
        and 'KeyStore.getInstance(KEYSTORE)' in store
    ),
    "route history is isolated by account": (
        "ownerUserId" in store
        and "pendingFor(context, currentSession.userId)" in activity
        and "assignUnowned(context, userId)" in activity
    ),
    "cloud route sync preserves unknown steps": (
        "/rest/v1/rpc/sync_walk_session_route" in activity
        and '.put("p_steps", JSONObject.NULL)' in activity
    ),
    "route sync keeps retryable local history": (
        "WalkOnStore.markSynced(context, walk.id)" in activity
        and "WalkOnStore.pendingFor" in activity
    ),
}

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    raise SystemExit("WalkOn safeguards missing: " + ", ".join(failed))
