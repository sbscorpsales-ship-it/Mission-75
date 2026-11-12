import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
const html=fs.readFileSync("legacy-runtime.html","utf8");
const required=[
 'id="gxJourneyPanel"','id="gxJourneyGoal"','id="gxJourneyPurpose"',
 'id="gxJourneySteps"','id="gxJourneyDistance"','id="gxJourneyRouteText"',
 'id="gxJourneyRoutes"','id="gxPurpose"','purpose:$("gxPurpose").value.trim()',
 'mission75.gps.sessions.v1','gativx.motionDaily.v1','gativx.goal.v1'
];
let failed=false;
for(const token of required){if(!html.includes(token)){console.error("FAIL missing "+token);failed=true}else console.log("PASS "+token)}
if(!html.includes('window.addEventListener("gativx:goal-updated",render)')){console.error("FAIL goal changes refresh journey panel");failed=true}else console.log("PASS goal change refresh");
if(!html.includes('window.showTab("walk")')){console.error("FAIL route history navigation");failed=true}else console.log("PASS route history navigation");
const journeyStart=html.lastIndexOf('<script>\n(function(){\n const $=id=>document.getElementById(id),read=');
const journeyEnd=journeyStart>=0?html.indexOf("</script>",journeyStart):-1;
const journeyScript=journeyStart>=0&&journeyEnd>journeyStart?html.slice(journeyStart,journeyEnd):"";
if(!journeyScript||/localStorage\.(?:clear|removeItem)|sessionStorage\.clear/.test(journeyScript)){console.error("FAIL destructive storage operation in journey panel");failed=true}else console.log("PASS journey panel does not delete browser data");
if(/service_role|service-role|sb_secret_/.test(html)){console.error("FAIL privileged Supabase key in browser");failed=true}else console.log("PASS no privileged key");
const scripts=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)].filter(([,attrs])=>! /\bsrc\s*=/.test(attrs)).map(([, ,body])=>body).filter(x=>x.trim());
for(const [i,src] of scripts.entries()){const p=path.join(os.tmpdir(),"gativx-journey-"+i+".js");fs.writeFileSync(p,src);const r=spawnSync("node",["--check",p],{encoding:"utf8"});if(r.status!==0){console.error("FAIL inline script "+i+": "+r.stderr);failed=true}}
if(!failed)console.log("PASS "+scripts.length+" inline scripts parse");
if(failed)process.exit(1);
