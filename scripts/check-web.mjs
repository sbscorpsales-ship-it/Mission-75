// GATIVX v2 release gate: isolated new data store, preserved browser storage, explicit legacy account access.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
const shell=fs.readFileSync("app-v2.html","utf8"),entry=fs.readFileSync("index.html","utf8");
let failed=false;const fail=m=>{failed=true;console.error("FAIL: "+m)},pass=m=>console.log("PASS: "+m);
const manifest=JSON.parse(fs.readFileSync("manifest.webmanifest","utf8"));
if(manifest.short_name!=="GATIVX"||manifest.display!=="standalone")fail("Standalone manifest invalid");else pass("Standalone manifest valid");
for(const icon of manifest.icons||[]){const p=icon.src.split(/[?#]/,1)[0].replace(/^\.\//,"");if(!fs.existsSync(p))fail("Manifest icon missing: "+icon.src)}
if(!fs.existsSync("apple-touch-icon.png")||!shell.includes('rel="apple-touch-icon"'))fail("iPhone icon missing");else pass("iPhone Home Screen icon linked");
if(!entry.includes('id="brandIntro"')||!entry.includes('id="skipBrandIntro"')||!entry.includes("From Goals to Xcellence")||!entry.includes('window.location.replace("./app-v2.html")'))fail("Original approved GATIVX intro or new summary-home route missing");else pass("Original GATIVX intro routes into the new summary home");
if(!fs.existsSync("app-v2.html")||!shell.includes('id="gpsStart"'))fail("GATIVX v2 GPS beta route missing");else pass("GATIVX v2 GPS beta remains available as a separate page");
if(!entry.includes('id="vActiveEnergy"')||!entry.includes("active_energy_kcal"))fail("Apple Health active-energy dashboard sync missing");else pass("Measured Apple Health active-energy tile and cloud mapping present");
if(shell.includes("mission75.")||shell.includes("gativx.goal.v1")||shell.includes("gativx.motionDaily.v1"))fail("New app reads or writes legacy data keys");else pass("No legacy data keys are read or written by the new app");
if(!shell.includes('href="./legacy-runtime.html"'))fail("Existing account and saved-record access link missing");else pass("Existing account and saved-record access link present");
if(!shell.includes("gativx.v2.fresh.state"))fail("Fresh v2 data namespace missing");else pass("Isolated fresh v2 data store present");
for(const id of ["summaryHero","activityRing","vActiveEnergy","guruCard"])if(!shell.includes('class="'+id+'"')&&!shell.includes('id="'+id+'"'))fail("Fitness summary home component missing: "+id);else pass("Fitness summary component present: "+id);
if(!shell.includes("GURU Mode")||!shell.includes(">GURU</button>"))fail("GURU mode entry missing");else pass("GURU mode entry present");
if(/localStorage\.(?:clear|removeItem)|sessionStorage\.clear/.test(shell))fail("New app must not delete existing browser records or auth sessions");else pass("Existing browser storage is preserved");
const scripts=[...shell.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)].filter(([,a])=>! /\bsrc\s*=/.test(a)).map(([, ,b])=>b).filter(x=>x.trim());
for(const [i,src] of scripts.entries()){const p=path.join(os.tmpdir(),"gativx-v2-"+i+".js");fs.writeFileSync(p,src);const r=spawnSync("node",["--check",p],{encoding:"utf8"});if(r.status!==0)fail("V2 JavaScript invalid: "+r.stderr)}
if(scripts.length&&!failed)pass("V2 JavaScript syntax valid");
for(const id of ["home","journey","record","walk","coach"])if(!shell.includes('id="'+id+'"'))fail("Missing panel "+id);
if((shell.match(/data-panel=/g)||[]).length<5)fail("Five navigation tabs missing");else pass("Five navigation tabs present");
for(const id of ["gpsStart","gpsPause","gpsFinish","saveEntry","saveGoal"])if(!shell.includes('id="'+id+'"'))fail("New standalone action missing: "+id);else pass("Standalone action present: "+id);
if(!fs.readFileSync("sw.js","utf8").includes("./apple-touch-icon.png"))fail("Service worker icon cache missing");else pass("Service worker icon cache valid");
if(failed)process.exit(1);