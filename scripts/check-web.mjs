import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const html = fs.readFileSync("index.html", "utf8");
const fail = (message) => { console.error(`FAIL: ${message}`); process.exitCode = 1; };
const pass = (message) => console.log(`PASS: ${message}`);

const scripts = [...html.matchAll(/<script\\b([^>]*)>([\\s\\S]*?)<\\/script>/gi)]
  .filter(([, attrs]) => !/\\bsrc\\s*=/.test(attrs))
  .map(([, , body]) => body)
  .filter(body => body.trim());

if (!scripts.length) fail("No inline application scripts found");
for (const [index, source] of scripts.entries()) {
  const file = path.join(os.tmpdir(), `gativx-inline-${index}.js`);
  fs.writeFileSync(file, source);
  const result = spawnSync("node", ["--check", file], { encoding: "utf8" });
  if (result.status !== 0) fail(`Inline script ${index + 1} has a JavaScript syntax error: ${result.stderr}`);
}
if (process.exitCode !== 1) pass(`${scripts.length} inline JavaScript blocks parse successfully`);

const tabs = [...html.matchAll(/data-tab=["']([^"']+)["']/g)].map(match => match[1]);
const uniqueTabs = [...new Set(tabs)];
if (uniqueTabs.length !== 6) fail(`Expected 6 unique navigation tabs, found ${uniqueTabs.length}`);
for (const tab of uniqueTabs) {
  if (!html.includes(`id="pane-${tab}"`)) fail(`Navigation tab '${tab}' has no matching pane`);
}
if (uniqueTabs.length === 6 && uniqueTabs.every(tab => html.includes(`id="pane-${tab}"`))) pass("All six navigation tabs map to existing content panes");

for (const key of ["mission75.logs.v1", "mission75.gps.sessions.v1", "mission75.settings.v1", "mission75.habits.v1"]) {
  if (!html.includes(key)) fail(`Existing user-data key missing: ${key}`);
}
if (["mission75.logs.v1", "mission75.gps.sessions.v1", "mission75.settings.v1", "mission75.habits.v1"].every(key => html.includes(key))) pass("Existing local data keys remain present");

if (!html.includes('gativx.brandIntro.seen.v1')) fail("First-visit intro flag missing");
else pass("First-visit intro persistence flag is present");

const introScript = scripts.find(source => source.includes("gativx.brandIntro.seen.v1"));
if (!introScript) fail("Could not locate the intro controller");
else {
  if (/\\bplayFanfare\\s*\\(\\s*\\)\\s*;/.test(introScript)) fail("Intro contains an automatic sound invocation");
  else pass("Intro does not invoke sound automatically");
}
if (process.exitCode) process.exit(1);
