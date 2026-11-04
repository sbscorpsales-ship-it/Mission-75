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

const ids = ["vSteps", "vHeartPoints", "vActiveMinutes", "vDistance", "vWater", "vProtein"];
for (const id of ids) if (!html.includes('id="' + id + '"')) fail("Dashboard metric missing: " + id);
if (ids.every(id => html.includes('id="' + id + '"'))) pass("Six activity dashboard metric elements are present");

if (!html.includes("x.steps==null?'—':fmt(x.steps)") || !html.includes("x.distance==null?'—':Number(x.distance).toFixed(2)+' km'")) fail("Missing activity data must not display as zero");
else pass("Missing step and distance values remain unknown, not zero");

if (!html.includes("gativx.brandIntro.seen.v1")) fail("First-visit intro flag missing");
else pass("First-visit intro persistence flag is present");

const introScript = scripts.find(source => source.includes("gativx.brandIntro.seen.v1"));
if (!introScript) fail("Could not locate the intro controller");
else if (/\bplayFanfare\s*\(\s*\)\s*;/.test(introScript)) fail("Intro contains an automatic sound invocation");
else pass("Intro does not invoke sound automatically");

if (failed) process.exit(1);
