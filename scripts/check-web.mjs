// GATIVX web release gate: verify the actual Safari/desktop entry point and full member dashboard.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";

const read = file => fs.readFileSync(file, "utf8");
const entry = read("index.html");
const app = read("legacy-runtime.html");
const sw = read("sw.js");
let failed = false;
const fail = message => { failed = true; console.error("FAIL: " + message); };
const pass = message => console.log("PASS: " + message);

if (entry.includes('window.location.replace("./legacy-runtime.html")') &&
    entry.includes('href="./legacy-runtime.html"') &&
    !entry.includes('window.location.replace("./app-v2.html")')) {
  pass("Root URL opens the full member dashboard");
} else fail("Root URL must open legacy-runtime.html, not the reduced v2 app");

for (const [label, ok] of [
  ["Safari Home Screen metadata is present", entry.includes('name="apple-mobile-web-app-capable"') && entry.includes('rel="apple-touch-icon"')],
  ["Full dashboard is retained as the offline fallback", sw.includes('"./legacy-runtime.html"') && sw.includes('caches.match("./legacy-runtime.html")')],
  ["Service worker cache is versioned", /const CACHE="gativx-v\d+"/.test(sw)],
  ["Daily journal and save action are present", app.includes('id="pane-log"') && app.includes('id="saveLog"')],
  ["Goal-setting journey is present", app.includes('id="gxModal"') && app.includes('id="gxSave"') && app.includes('id="gxTarget"')],
  ["Habit and trends views are present", app.includes('id="habitList"') && app.includes('id="pane-trends"')],
  ["GPS walk controls and route history are present", app.includes('id="gpsStart"') && app.includes('id="gpsPause"') && app.includes('id="gpsFinish"') && app.includes('id="gpsHistory"')],
  ["Coaching view is present", app.includes('id="pane-coach"') && app.includes('id="coachTitle"') && app.includes('id="coachText"')],
  ["Account sign-in and cloud sync controls are present", app.includes('id="cloudSignIn"') && app.includes('id="cloudSyncNow"') && app.includes('auth.signInWithPassword')],
  ["Cloud sync reads motion steps and walk history", app.includes("motion_daily_steps") && app.includes("walk_sessions") && app.includes("daily_logs")],
  ["Native iPhone motion readings are refreshed in Safari", app.includes("refreshNativeMotionFromCloud") && app.includes("startNativeMotionPolling")],
  ["Existing local journal, GPS, settings and habit stores are retained", ["mission75.logs.v1","mission75.gps.sessions.v1","mission75.settings.v1","mission75.habits.v1"].every(key => app.includes(key))],
  ["No privileged Supabase secret is embedded in the browser app", !/service_role|service-role|sb_secret_/.test(app)]
]) ok ? pass(label) : fail(label);

const scripts = [...app.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
  .filter(([, attrs]) => !/\bsrc\s*=/.test(attrs))
  .map(([, , source]) => source)
  .filter(source => source.trim());

if (!scripts.length) fail("No inline application JavaScript found");
for (const [index, source] of scripts.entries()) {
  const file = path.join(os.tmpdir(), "gativx-web-" + index + ".js");
  fs.writeFileSync(file, source);
  const result = spawnSync(process.execPath, ["--check", file], {encoding: "utf8"});
  if (result.status !== 0) fail("Inline JavaScript syntax error: " + result.stderr);
}
if (scripts.length && !failed) pass("All inline dashboard JavaScript parses successfully");

if (failed) process.exit(1);
console.log("GATIVX actual web-entry release gate passed.");
