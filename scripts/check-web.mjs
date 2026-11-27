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
  ["No privileged Supabase secret is embedded in the browser app", !/service_role|service-role|sb_secret_/.test(app)],
  ["No-session sign-up guidance does not disclose account existence", app.includes("If this is a new registration, check your inbox and spam") && !app.includes("This email is already registered")],
  ["Password recovery requests and updates use Supabase Auth", app.includes("resetPasswordForEmail(email,{redirectTo:window.location.origin+window.location.pathname})") && app.includes("updateUser({password:next})")]
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

if (failed) process.exit(1);
console.log("GATIVX v2 syntax and structural release gate passed.");
