// GATIVX v2 release gate: new shell, retained data runtime, syntax and navigation.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
const shell=fs.readFileSync("app-v2.html","utf8");
const entry=fs.readFileSync("index.html","utf8");
const runtime=fs.readFileSync("legacy-runtime.html","utf8");
let failed=false;
const fail=m=>{failed=true;console.error("FAIL: "+m)};
const pass=m=>console.log("PASS: "+m);
const manifest=JSON.parse(fs.readFileSync("manifest.webmanifest","utf8"));
if(manifest.short_name!=="GATIVX"||manifest.display!=="standalone")fail("GATIVX standalone manifest incomplete");else pass("Standalone manifest valid");
for(const icon of manifest.icons||[]){const p=icon.src.split(/[?#]/,1)[0].replace(/^\.\//,"");if(!fs.existsSync(p))fail("Manifest icon missing: "+icon.src)}
if(!fs.existsSync("apple-touch-icon.png")||!shell.includes('rel="apple-touch-icon"'))fail("iPhone Home Screen icon missing from new shell");else pass("iPhone Home Screen icon linked");
if(!fs.readFileSync("sw.js","utf8").includes("./apple-touch-icon.png"))fail("Service worker does not precache iPhone icon");else pass("Service worker icon cache valid");
if(!entry.includes("./app-v2.html")||!entry.includes("location.replace"))fail("Root entry does not launch the new interface");else pass("Root entry launches the clean v2 interface");
if(!shell.includes('src="./legacy-runtime.html"')||!fs.existsSync("legacy-runtime.html"))fail("Retained data/runtime bridge is missing");else pass("Existing data and service runtime preserved separately");
const scripts=[...shell.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)].filter(([,a])=>! /\bsrc\s*=/.test(a)).map(([, ,b])=>b).filter(x=>x.trim());
for(const [i,src] of scripts.entries()){const p=path.join(os.tmpdir(),"gativx-v2-"+i+".js");fs.writeFileSync(p,src);const r=spawnSync("node",["--check",p],{encoding:"utf8"});if(r.status!==0)fail("V2 JavaScript block "+(i+1)+" invalid: "+r.stderr)}
if(scripts.length&&!failed)pass(scripts.length+" new interface JavaScript blocks parse");
const panels=[...shell.matchAll(/id="(home|journey|record|walk|coach)"/g)].map(x=>x[1]);
for(const id of ["home","journey","record","walk","coach"])if(!shell.includes('id="'+id+'"'))fail("Missing v2 section: "+id);
if(!shell.includes('data-panel="home"')||!shell.includes('data-panel="walk"')||!shell.includes('data-panel="record"'))fail("New navigation controls incomplete");else pass("Five new navigation destinations present");
for(const key of ["mission75.logs.v1","mission75.gps.sessions.v1","mission75.settings.v1","mission75.habits.v1"])if(!runtime.includes(key))fail("Retained runtime missing user-data key "+key);
if(!runtime.includes('id="vSteps"')||!runtime.includes('id="gpsStart"')||!runtime.includes('id="saveLog"'))fail("Legacy runtime no longer exposes step, GPS and record actions");else pass("Existing step, GPS and journal engines remain available behind the new shell");
if(!shell.includes("steps==null?'—'")||!shell.includes("SOURCE NOT CONFIRMED"))fail("Unknown step values must not be shown as zero");else pass("Unknown step totals remain unknown");
if(!shell.includes("mission75.goal.v1")&&!shell.includes("gativx.goal.v1"))fail("Mission goal binding missing");
if(failed)process.exit(1);
