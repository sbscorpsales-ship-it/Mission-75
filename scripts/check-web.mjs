// GATIVX web release gate: syntax, navigation, data preservation and intro safety.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const html = fs.readFileSync("index.html", "utf8");
let failed = false;
const fail = (message) => { failed = true; console.error("FAIL: " + message); };
const pass = (message) => console.log("PASS: " + message);

const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
  .filter(([, attrs]) => !/\bsrc\s*=/.test(attrs))
  .map(([, , body]) => body)
  .filter(body => body.trim());

if (!scripts.length) fail("No inline application scripts found");
for (const [index, source] of scripts.entries()) {
  const file = path.join(os.tmpdir(), "gativx-inline-" + index + ".js");
  fs.writeFileSync(file, source);
  const result = spawnSync("node", ["--check", file], { encoding: "utf8" });
  if (result.status !== 0) fail("Inline script " + (index + 1) + " has a JavaScript syntax error: " + result.stderr);
}
if (scripts.length && !failed) pass(scripts.length + " inline JavaScript blocks parse successfully");

const tabs = [...html.matchAll(/data-tab=["']([^"']+)["']/g)].map(match => match[1]);
const uniqueTabs = [...new Set(tabs)];
if (uniqueTabs.length !== 6) fail("Expected 6 unique navigation tabs, found " + uniqueTabs.length);
for (const tab of uniqueTabs) if (!html.includes('id="pane-' + tab + '"')) fail("Navigation tab '" + tab + "' has no matching pane");
if (uniqueTabs.length === 6 && uniqueTabs.every(tab => html.includes('id="pane-' + tab + '"'))) pass("All six navigation tabs map to existing content panes");

const keys = ["mission75.logs.v1", "mission75.gps.sessions.v1", "mission75.settings.v1", "mission75.habits.v1"];
for (const key of keys) if (!html.includes(key)) fail("Existing user-data key missing: " + key);
if (keys.every(key => html.includes(key))) pass("Existing local data keys remain present");

const ids = ["vSteps", "vActivityType", "vActiveMinutes", "vDistance", "vWater", "vProtein"];
for (const id of ids) if (!html.includes('id="' + id + '"')) fail("Dashboard metric missing: " + id);
if (ids.every(id => html.includes('id="' + id + '"'))) pass("Six activity dashboard metric elements are present");
if (!html.includes('id="vActiveMinutes"') || !html.includes('id="vActivitySource"') || !html.includes("function sessionsForDate(date)")) fail("GPS activity totals must feed the daily activity dashboard");
else pass("Saved GPS walks feed daily activity type, active minutes and distance");
if (html.includes('id="vHeartPoints"')) fail("Do not display uncomputed heart points");
else pass("No uncomputed heart-points metric is shown");

if (!html.includes("x.steps==null?'—':fmt(x.steps)") || !html.includes("x.distance==null?'—':Number(x.distance).toFixed(2)+' km'")) fail("Missing activity data must not display as zero");
else pass("Missing step and distance values remain unknown, not zero");

if (!html.includes("gativx.brandIntro.seen.v1")) fail("First-visit intro flag missing");
else pass("First-visit intro persistence flag is present");

const introScript = scripts.find(source => source.includes("gativx.brandIntro.seen.v1"));
if (!introScript) fail("Could not locate the intro controller");
else if (/\bplayFanfare\s*\(\s*\)\s*;/.test(introScript)) fail("Intro contains an automatic sound invocation");
else pass("Intro does not invoke sound automatically");

if (!html.includes("gativx.profile.v1") || !html.includes('id="profilePhotoInput"') || !html.includes('id="removeProfilePhoto"')) fail("On-device profile photo controls or storage key missing");
else if (!html.includes("canvas.toDataURL('image/jpeg',.76)") || !html.includes("this device")) fail("Profile photo must be resized and clearly device-local");
else if (!html.includes('id="profilePhotoInput" type="file" accept="image/*"') || !html.includes("canvas.width=Math.max(1,Math.round(img.width*scale))")) fail("Profile photo picker or bounded image resize missing");
else pass("Profile photo is optional, resized and stored locally only");

if (!html.includes('id="connectionHeading"') || !html.includes('id="accountConnectionState"')) fail("Dashboard connected-data hub or account state is missing");
else pass("Dashboard shows account and external data-source connection states");

if (!html.includes('id="accountQuick"') || !html.includes('id="cloudSyncNow"')) fail("Quick account access or manual cloud refresh control is missing");
else pass("Account access and user-triggered cloud refresh controls are present");

if (!html.includes("Safari cannot read HealthKit") || !html.includes("secure Strava OAuth connection") || !html.includes("Health Connect")) fail("External health-source limitations and permission requirements must be explicit");
else pass("External integrations are not misrepresented as connected; platform and consent requirements are explicit");

if (failed) process.exit(1);

// Re-run release gate after workflow activation on main.
