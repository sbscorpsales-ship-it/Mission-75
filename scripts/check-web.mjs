// GATIVX v2 release gate: validate the actual published entry and dashboard scripts.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";

const read = file => fs.readFileSync(file, "utf8");
const entry = read("index.html");
const app = read("app-v2.html");
const sw = read("sw.js");
let failed = false;
const fail = message => { failed = true; console.error("FAIL: " + message); };
const pass = message => console.log("PASS: " + message);

if (entry.includes("./app-v2.html") && entry.includes("window.location.search") &&
    !entry.includes('window.location.replace("./legacy-runtime.html")')) {
  pass("Published root entry opens GATIVX v2 and preserves incoming shortcut parameters");
} else fail("Root entry must open app-v2.html and preserve query/hash parameters");

for (const [label, ok] of [
  ["Mobile web-app metadata and install icon are present", entry.includes('name="apple-mobile-web-app-capable"') && entry.includes('rel="apple-touch-icon"')],
  ["Three daily progress rings are present", ["stepsRing","caloriesRing","heartRing"].every(id => app.includes('id="'+id+'"'))],
  ["Primary mission ring is tied to saved journey progress", app.includes('id="missionRingValue"') && app.includes("mission.percent*3.6")],
  ["Third ring is honestly labelled as completed walk minutes", app.includes("<small>WALK MIN</small>") && app.includes("completedWalkMinutesForDay")],
  ["Dashboard exposes health, walk and cloud status", ["healthConnectionStatus","walkSaveStatus","cloudBackupStatus"].every(id => app.includes('id="'+id+'"'))],
  ["Unknown measurements remain visibly unavailable", app.includes("shownSteps==null?'—'") && app.includes("x.activeEnergyKcal==null?'—'")],
  ["Walk completion writes a recovery journal before primary save", app.indexOf("writeWalkRecovery(pending)") >= 0 && app.includes("WALK_RECOVERY_KEY")],
  ["Recovery journal verifies its own persisted write", app.includes("Walk recovery journal read-back failed")],
  ["Signing out switches to an isolated device store", app.includes("localStorage.setItem(ACCOUNT_MIGRATED_KEY,'1')") && app.includes("stateStorageKey=KEY+'.device'")],
  ["Cloud backup retry is enabled when the device is online", app.includes("navigator.onLine&&cloudUser&&state.walks.some")],
  ["GPS walk controls and route history are present", ["gpsStart","gpsPause","gpsFinish","gpsHistory"].every(id => app.includes('id="'+id+'"'))],
  ["GURU purpose and next-action controls are present", ["guruPurpose","guruNextAction","reconnectGuru"].every(id => app.includes('id="'+id+'"'))],
  ["No privileged Supabase secret is embedded in the browser app", !/service_role|service-role|sb_secret_/.test(app)]
]) ok ? pass(label) : fail(label);

const scripts = [...app.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
  .filter(([, attrs]) => !/\bsrc\s*=/.test(attrs))
  .map(([, , source]) => source)
  .filter(source => source.trim());

if (!scripts.length) fail("No inline application JavaScript found");
for (const [index, source] of scripts.entries()) {
  const file = path.join(os.tmpdir(), "gativx-v2-" + index + ".js");
  fs.writeFileSync(file, source);
  const result = spawnSync(process.execPath, ["--check", file], {encoding: "utf8"});
  if (result.status !== 0) fail("Inline JavaScript syntax error in block " + index + ": " + result.stderr);
}
if (scripts.length && !failed) pass("All inline GATIVX v2 JavaScript blocks pass Node syntax validation");


/*
 * Cross-platform auth contract: web and native clients must use the same
 * Supabase project URL and publishable key. This is a source-level guard;
 * live sign-in and account/data sync still require device/account acceptance.
 */
const nativeClient = read("ios/GATIVX/Cloud/SupabaseRESTClient.swift");
const webProject = app.match(/const SUPABASE_URL='([^']+)'/)?.[1];
const nativeProject = nativeClient.match(/private let baseURL = URL\\(string: "([^"]+)"\\)!/)?.[1];
const webPublishableKey = app.match(/const SUPABASE_PUBLISHABLE_KEY='([^']+)'/)?.[1];
const nativePublishableKey = nativeClient.match(/private let publishableKey = "([^"]+)"/)?.[1];
if (!webProject || !nativeProject || webProject !== nativeProject) {
  fail("Web and iOS clients must target the same Supabase project URL");
} else pass("Web and iOS clients target the same Supabase project");
if (!webPublishableKey || !nativePublishableKey || webPublishableKey !== nativePublishableKey) {
  fail("Web and iOS clients must use the same Supabase publishable key");
} else pass("Web and iOS clients use the same Supabase publishable key");

for (const table of ["profiles", "daily_logs", "motion_daily_steps", "walk_sessions"]) {
  if (app.includes("from('" + table + "')")) pass("Web cloud sync references " + table);
  else fail("Web cloud sync is missing its " + table + " table path");
}
const migrationDirectory = path.resolve("supabase/migrations");
const migrationText = fs.readdirSync(migrationDirectory)
  .filter(name => name.endsWith(".sql"))
  .map(name => read(path.join(migrationDirectory, name)))
  .join("\\n");
for (const rpc of [
  "sync_healthkit_daily_steps",
  "sync_healthkit_daily_energy",
  "sync_motion_daily_steps",
  "sync_activity_session_steps",
  "sync_walk_session_route"
]) {
  if (nativeClient.includes("/rpc/" + rpc) && migrationText.includes(rpc)) {
    pass("Native RPC has a checked-in migration: " + rpc);
  } else fail("Native RPC/migration contract is incomplete: " + rpc);
}

if (failed) process.exit(1);
console.log("GATIVX v2 syntax and structural release gate passed.");
