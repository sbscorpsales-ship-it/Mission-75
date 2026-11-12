import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";
const browser=await chromium.launch({headless:true});
const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
const errors=[];page.on("pageerror",e=>errors.push(e.message));
const legacyFixtures={"mission75.dailyLogs":"preserve-existing-records-fixture","sb-crarbbsvcczwmtvxyrxo-auth-token":"preserve-auth-session-fixture"};
await page.addInitScript((legacy)=>{for(const [key,value] of Object.entries(legacy))localStorage.setItem(key,value);sessionStorage.setItem("gativx.session.fixture","preserve-session-fixture");localStorage.setItem("gativx.v2.fresh.state",JSON.stringify({version:2,goal:{type:"Build strength",duration:"90 days"},entries:{[new Date().getFullYear()+"-"+String(new Date().getMonth()+1).padStart(2,"0")+"-"+String(new Date().getDate()).padStart(2,"0")]:{steps:1948,water:1500,protein:65,distance:.4}},walks:[]}));},legacyFixtures);
await page.route("https://**/*",r=>r.abort());
await page.goto(pathToFileURL(path.resolve("index.html")).href,{waitUntil:"domcontentloaded"});await page.waitForURL(url=>url.pathname.endsWith("/app-v2.html"),{timeout:10000});await page.waitForTimeout(300);
const assert=(v,m)=>{if(!v)throw new Error(m)};
assert(await page.locator("#steps").textContent().then(x=>x.trim())==="1,948","Fresh-store step value did not render");
assert(await page.locator("a").filter({hasText:"Sync Apple Health now"}).evaluateAll(links=>links.some(link=>link.getAttribute("href")==="shortcuts://run-shortcut?name=try%202")),"One-tap Apple Health Shortcut launcher is missing or has the wrong shortcut name");
assert((await page.locator("#missionTitle").textContent()).includes("Build strength"),"Fresh-store mission did not render");
assert((await page.locator("#missionPct").textContent()).includes("MISSION ACTIVE"),"Mission status missing");
assert((await page.locator("#missionPct").textContent()).includes("1/90 CHECK-IN DAYS"),"Mission progress must count real saved check-in days, not a decorative percentage");
await page.locator('[data-panel="journey"]').click();
await page.locator("#goalType").selectOption({label:"Weight loss"});
await page.locator("#goalDuration").selectOption({label:"90 days"});
await page.locator("#goalPurpose").fill("I want to feel energetic and stay active with my family.");
await page.locator("#goalFeeling").fill("energetic and confident");
await page.locator("#saveGoal").click();
await page.waitForFunction(()=>document.querySelector("#coach")?.classList.contains("active"));
assert((await page.locator("#guruGoal").textContent()).includes("Weight loss"),"GURU did not receive the saved goal");
assert((await page.locator("#guruPurpose").textContent()).includes("stay active with my family"),"GURU did not reconnect the user's stated purpose");
assert((await page.locator("#guruNextAction").textContent()).toLowerCase().includes("small step"),"GURU did not provide a manageable next action based on the member's recorded activity");
await page.locator("#reconnectGuru").click();
assert((await page.locator("#guruNextAction").textContent()).includes("Remember why you started"),"GURU reconnect action did not repeat the user's purpose");
assert((await page.locator("#distance").textContent()).includes("0.40 km"),"Fresh-store distance did not render");
assert(await page.locator(".summaryHero").count()===1,"Fitness summary hero missing");
assert(await page.locator(".summaryTile").count()===4,"Expected four summary metric tiles");
assert(await page.locator('.tileSteps a[href="shortcuts://run-shortcut?name=try%202"]').filter({hasText:"Sync Apple Health now"}).count()===1,"Step tile must launch the configured Apple Health Shortcut directly");
assert(await page.locator('.tileSteps a[href="./apple-health-shortcut.html"]').filter({hasText:"Shortcut setup guide"}).count()===1,"Step tile must retain access to the Shortcut setup guide");
await page.locator('[data-panel="home"]').click();
await page.locator('.quick [data-go="walk"]').click();
assert(await page.locator("#walk").evaluate(el=>el.classList.contains("active")),"Today's Walk action did not open the GPS recorder");
assert(await page.locator("#home .guruCard").count()===1,"GURU mode home card missing");
assert(await page.locator("#vActiveEnergy").textContent().then(x=>x.trim())==="—","Active calories must not be fabricated before HealthKit data");
assert((await page.locator('[data-panel="coach"]').textContent()).includes("GURU"),"GURU navigation label missing");
assert(await page.locator(".bottom button").count()===5,"Expected five navigation destinations");
assert(await page.locator('a[href="./legacy-runtime.html"]').count()===1,"Existing account and saved-record access link missing");
assert(await page.locator("#cloudAccount").count()===1,"New GATIVX account and cloud backup panel missing");
for(const tab of ["home","journey","record","walk","coach"]){await page.locator('[data-panel="'+tab+'"]').click();assert(await page.locator("#"+tab+".panel.active").count()===1,"Navigation failed: "+tab)}
await page.locator('[data-panel="home"]').click();assert(await page.locator("#missionTitle").textContent().then(x=>x.includes("Weight loss")),"Saved mission changed after navigation");
assert(errors.length===0,"Browser errors: "+errors.join("; "));

const healthImport=await browser.newPage({viewport:{width:390,height:844}});
const healthErrors=[];healthImport.on("pageerror",e=>healthErrors.push(e.message));
await healthImport.route("https://**/*",r=>r.abort());
const now=new Date(),localDay=now.getFullYear()+"-"+String(now.getMonth()+1).padStart(2,"0")+"-"+String(now.getDate()).padStart(2,"0");
await healthImport.goto(pathToFileURL(path.resolve("app-v2.html")).href+"?gativx_steps=1240&gativx_active_energy=345&gativx_date="+localDay,{waitUntil:"domcontentloaded"});
await healthImport.waitForTimeout(500);
const healthImportDebug=await healthImport.evaluate(()=>({url:location.href,steps:document.querySelector("#steps")?.textContent.trim(),note:document.querySelector("#stepNote")?.textContent,local:localStorage.getItem("gativx.v2.fresh.state"),device:localStorage.getItem("gativx.v2.fresh.state.device"),pending:sessionStorage.getItem("gativx.pending-health-shortcut.v1")}));
assert(healthImportDebug.steps==="1,240","Apple Health Shortcut steps did not reach the new GATIVX home: "+JSON.stringify(healthImportDebug));
assert((await healthImport.locator("#vActiveEnergy").textContent()).trim()==="345 kcal","Measured active energy did not reach the new GATIVX home");
assert((await healthImport.locator("#stepNote").textContent()).includes("Apple Health via Shortcuts"),"Shortcut step source was not labelled");
assert(await healthImport.evaluate(()=>!location.search.includes("gativx_active_energy")&&!location.search.includes("gativx_steps")),"Health readings remained in the page URL");
assert(healthErrors.length===0,"Apple Health import browser errors: "+healthErrors.join("; "));
await healthImport.close();

// A previously imported Shortcut count must not masquerade as a fresh reading.
const staleShortcut=await browser.newPage({viewport:{width:390,height:844}});
await staleShortcut.addInitScript(()=>{
 const d=new Date(),day=d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0");
 const old=new Date(Date.now()-2*60*60*1000).toISOString();
 localStorage.setItem("gativx.v2.fresh.state",JSON.stringify({version:2,goal:null,entries:{[day]:{steps:1855,stepsSource:"apple_health_shortcuts",stepsUpdatedAt:old}},walks:[]}));
});
await staleShortcut.route("https://**/*",r=>r.abort());
await staleShortcut.goto(pathToFileURL(path.resolve("app-v2.html")).href,{waitUntil:"domcontentloaded"});
assert((await staleShortcut.locator("#steps").textContent()).trim()==="—","Stale 1,855 Shortcut sample was displayed as a current reading");
assert((await staleShortcut.locator("#stepNote").textContent()).includes("No iPhone sensor reading"),"Stale Shortcut source label was not cleared");
await staleShortcut.close();

// The real iPhone Shortcut opens the GitHub Pages root, not app-v2.html.
// The landing redirect must preserve the Apple Health query until import runs.
const shortcutLanding=await browser.newPage({viewport:{width:390,height:844}});
const shortcutLandingErrors=[];shortcutLanding.on("pageerror",e=>shortcutLandingErrors.push(e.message));
await shortcutLanding.route("https://**/*",r=>r.abort());
await shortcutLanding.goto(pathToFileURL(path.resolve("index.html")).href+"?gativx_steps=1855&gativx_date="+localDay,{waitUntil:"domcontentloaded"});
await shortcutLanding.waitForURL(url=>url.pathname.endsWith("/app-v2.html"),{timeout:5000});
await shortcutLanding.waitForFunction(()=>document.querySelector("#steps")?.textContent.trim()==="1,855");
assert((await shortcutLanding.locator("#stepNote").textContent()).includes("Apple Health via Shortcuts"),"Root shortcut link did not preserve the Apple Health source");
assert(await shortcutLanding.evaluate(()=>!location.search.includes("gativx_steps")&&!location.search.includes("gativx_date")),"Imported shortcut parameters were not cleaned after successful import");
assert(shortcutLandingErrors.length===0,"Shortcut landing errors: "+shortcutLandingErrors.join("; "));
await shortcutLanding.close();

// A returning signed-in member must receive the Shortcut sample only after
// the correct account store has been activated (no device-store race).
const signedShortcut=await browser.newPage({viewport:{width:390,height:844}});
const signedShortcutErrors=[];signedShortcut.on("pageerror",e=>signedShortcutErrors.push(e.message));
await signedShortcut.addInitScript((day)=>{
 window.__shortcutCloud={uploads:[]};
 window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:{user:{id:"shortcut-member"}}},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},from(table){return {select(){return {eq:async()=>({data:table==="daily_logs"?[{log_date:day,steps:0,steps_source:"manual",steps_updated_at:null,active_energy_kcal:null,active_energy_source:null,active_energy_updated_at:null,walking_km:null,water_ml:null,protein_g:null,weight_kg:null}]:[],error:null})}},upsert:async(rows)=>{if(table==="daily_logs")window.__shortcutCloud.uploads.push(...rows);return {error:null}},insert:async()=>({error:null})}}})};
},localDay);
await signedShortcut.route("https://**/*",r=>r.abort());
await signedShortcut.goto(pathToFileURL(path.resolve("app-v2.html")).href+"?gativx_steps=1855&gativx_date="+localDay,{waitUntil:"domcontentloaded"});
await signedShortcut.waitForFunction(()=>document.querySelector("#steps")?.textContent.trim()==="1,855",{timeout:3000});
await signedShortcut.waitForTimeout(500);
const signedShortcutDebug=await signedShortcut.evaluate(()=>({cloudState:document.querySelector("#cloudState")?.textContent,cloudStatus:document.querySelector("#cloudStatus")?.textContent,steps:document.querySelector("#steps")?.textContent,stepNote:document.querySelector("#stepNote")?.textContent,uploads:window.__shortcutCloud.uploads,account:localStorage.getItem("gativx.v2.fresh.state.user.shortcut-member"),device:localStorage.getItem("gativx.v2.fresh.state.device")}));
assert(signedShortcutDebug.cloudState==="BACKUP CURRENT","Shortcut did not finish cloud sync for restored member: "+JSON.stringify(signedShortcutDebug));
assert((await signedShortcut.locator("#stepNote").textContent()).includes("Apple Health via Shortcuts"),"Signed-in Shortcut sample lost its Health source");
const signedShortcutData=await signedShortcut.evaluate(()=>({uploads:window.__shortcutCloud.uploads,account:JSON.parse(localStorage.getItem("gativx.v2.fresh.state.user.shortcut-member")||"null"),device:JSON.parse(localStorage.getItem("gativx.v2.fresh.state.device")||"null")}));
assert(signedShortcutData.uploads.some(row=>row.steps===1855&&row.steps_source==="apple_health_shortcuts"),"Fresh Shortcut sample did not override the stale manual zero in cloud");
assert(signedShortcutData.account?.entries?.[localDay]?.steps===1855,"Fresh Shortcut sample was not saved in the correct member's local record");
assert(!signedShortcutData.device?.entries?.[localDay],"Shortcut sample leaked into the shared device-only store");
assert(signedShortcutErrors.length===0,"Signed-in Shortcut import errors: "+signedShortcutErrors.join("; "));
await signedShortcut.close();

// Account login and cloud sync are exercised with an isolated Supabase client double.
const cloudPage=await browser.newPage({viewport:{width:390,height:844}});
const cloudErrors=[];cloudPage.on("pageerror",e=>cloudErrors.push(e.message));
await cloudPage.addInitScript(()=>{
 const d=new Date(),day=d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0");
 const localStamp=new Date(Date.now()-120000).toISOString(),remoteStamp=new Date(Date.now()-60000).toISOString();
 localStorage.setItem("gativx.v2.fresh.state",JSON.stringify({version:2,goal:null,entries:{[day]:{steps:1240,stepsSource:"apple_health_shortcuts",stepsUpdatedAt:localStamp,activeEnergyKcal:345,activeEnergySource:"apple_health_shortcuts",activeEnergyUpdatedAt:localStamp,weight:84,water:1700,protein:72,distance:.6}},walks:[{date:day,distance:.03,points:[{lat:12.97,lon:77.59,accuracy:5,time:Date.now()-10000},{lat:12.97018,lon:77.59,accuracy:5,time:Date.now()}],createdAt:new Date().toISOString()}]}));
 window.__cloudMock={uploaded:[],inserts:[],currentUser:null,dailyRows:[]};
 window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signInWithPassword:async({email})=>{window.__cloudMock.currentUser=email.startsWith("second")?"test-user-456":"test-user-123";return {data:{user:{id:window.__cloudMock.currentUser,user_metadata:{display_name:"GATIVX Tester"}}},error:null}},signUp:async()=>({data:{user:null,session:null},error:null}),signOut:async()=>{window.__cloudMock.currentUser=null;return {error:null}}},from(table){return {select(){return {eq:async()=>({data:table==="daily_logs"&&window.__cloudMock.currentUser==="test-user-123"?window.__cloudMock.dailyRows:[],error:null})}},upsert:async(rows)=>{window.__cloudMock.uploaded.push({user:window.__cloudMock.currentUser,rows});return {error:null}},insert:async(row)=>{window.__cloudMock.inserts.push({user:window.__cloudMock.currentUser,row});return {error:null}}}}})};
});
await cloudPage.addInitScript(()=>{const d=new Date(),day=d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0"),stamp=new Date(Date.now()-60000).toISOString();window.__cloudMock.dailyRows=[{log_date:day,steps:2100,steps_source:"apple_health",steps_updated_at:stamp,active_energy_kcal:410,active_energy_source:"apple_health",active_energy_updated_at:stamp}]});
await cloudPage.route("https://**/*",r=>r.abort());
await cloudPage.goto(pathToFileURL(path.resolve("app-v2.html")).href,{waitUntil:"domcontentloaded"});
await cloudPage.locator("#cloudEmail").fill("tester@example.com");
await cloudPage.locator("#cloudPassword").fill("not-a-real-password");
await cloudPage.locator("#cloudSignIn").click();
await cloudPage.waitForFunction(()=>document.querySelector("#cloudState")?.textContent==="BACKUP CURRENT");
assert((await cloudPage.locator("#steps").textContent()).trim()==="2,100","New cloud sync did not prefer newer native Apple Health steps");
assert((await cloudPage.locator("#vActiveEnergy").textContent()).trim()==="410 kcal","New cloud sync did not prefer newer native active energy");
assert((await cloudPage.locator("#activityTrend").textContent()).includes("2,100"),"Seven-day chart did not use actual HealthKit steps from cloud");
await cloudPage.evaluate(()=>{const d=new Date(),day=d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0"),stamp=new Date(Date.now()+1000).toISOString();window.__cloudMock.dailyRows=[{log_date:day,steps:2345,steps_source:"apple_health",steps_updated_at:stamp,active_energy_kcal:456,active_energy_source:"apple_health",active_energy_updated_at:stamp}];document.dispatchEvent(new Event("visibilitychange"))});
await cloudPage.waitForFunction(()=>document.querySelector("#steps")?.textContent.trim()==="2,345"&&document.querySelector("#vActiveEnergy")?.textContent.trim()==="456 kcal",{timeout:5000});
assert((await cloudPage.locator("#stepNote").textContent()).includes("Apple Health"),"Live dashboard refresh lost native HealthKit source label");
assert((await cloudPage.locator("#activityTrend").textContent()).includes("2,345"),"Seven-day chart did not refresh with newly synced HealthKit readings");
const cloudRows=await cloudPage.evaluate(()=>window.__cloudMock.uploaded);
const cloudWalks=await cloudPage.evaluate(()=>window.__cloudMock.inserts);
const memberDailyUploads=cloudRows.filter(batch=>batch.user==="test-user-123").flatMap(batch=>batch.rows||[]);
assert(memberDailyUploads.length>=1&&memberDailyUploads.every(row=>row.user_id==="test-user-123"),"New GATIVX daily record was not uploaded to the signed-in member");
const uploadedDaily=memberDailyUploads[0];
assert(uploadedDaily.steps===2100&&uploadedDaily.active_energy_kcal===410,"Cloud upload did not preserve authoritative HealthKit readings");
assert(uploadedDaily.weight_kg===84&&uploadedDaily.water_ml===1700&&uploadedDaily.protein_g===72&&uploadedDaily.walking_km===.6,"Cloud upload lost locally recorded wellness values");
assert(cloudWalks.length===1&&cloudWalks[0].user==="test-user-123"&&cloudWalks[0].row.distance_m===30&&cloudWalks[0].row.route_points.length===2,"Saved GPS route was not backed up to the member cloud account");
assert(cloudWalks[0].row.steps===null,"Unknown GPS-only walk steps were incorrectly stored as zero");
assert(cloudErrors.length===0,"Cloud account browser errors: "+cloudErrors.join("; "));
await cloudPage.locator("#cloudSignOut").click();
await cloudPage.waitForFunction(()=>document.querySelector("#cloudSignOut")?.style.display==="none");
assert((await cloudPage.locator("#steps").textContent()).trim()==="—","Signing out did not immediately clear the previous member's dashboard");
const afterImmediateSignOut=await cloudPage.evaluate(()=>({device:JSON.parse(localStorage.getItem("gativx.v2.fresh.state.device")||"null"),first:JSON.parse(localStorage.getItem("gativx.v2.fresh.state.user.test-user-123")||"null")}));
assert(afterImmediateSignOut.device&&Object.keys(afterImmediateSignOut.device.entries||{}).length===0,"Signed-out device store inherited the previous member's entries");
assert(afterImmediateSignOut.first&&afterImmediateSignOut.first.entries[Object.keys(afterImmediateSignOut.first.entries)[0]].weight===84,"Signing out deleted the previous member's private local backup");
await cloudPage.locator("#cloudEmail").fill("second@example.com");
await cloudPage.locator("#cloudPassword").fill("not-a-real-password");
await cloudPage.locator("#cloudSignIn").click();
await cloudPage.waitForFunction(()=>document.querySelector("#cloudState")?.textContent==="BACKUP CURRENT");
const accountIsolation=await cloudPage.evaluate(()=>({entries:JSON.parse(localStorage.getItem("gativx.v2.fresh.state.user.test-user-456")).entries,first:JSON.parse(localStorage.getItem("gativx.v2.fresh.state.user.test-user-123")),uploads:window.__cloudMock.uploaded,walks:window.__cloudMock.inserts}));
assert(Object.keys(accountIsolation.entries).length===0,"A second account inherited the previous member's private daily records");
assert(accountIsolation.first.entries[Object.keys(accountIsolation.first.entries)[0]].weight===84,"First account's local data was not preserved after switching accounts");
assert(accountIsolation.uploads.length>=1&&accountIsolation.uploads.every(batch=>batch.user==="test-user-123"),"First account's private daily data was uploaded to a different member");
assert(accountIsolation.walks.length>=1&&accountIsolation.walks.every(batch=>batch.user==="test-user-123"),"First account's GPS route was uploaded to a different member");
await cloudPage.locator("#cloudSignOut").click();
await cloudPage.waitForFunction(()=>document.querySelector("#cloudSignOut")?.style.display==="none"&&(()=>{try{const d=JSON.parse(localStorage.getItem("gativx.v2.fresh.state.device")||"null");return !!d&&Object.keys(d.entries||{}).length===0}catch{return false}})());
await cloudPage.reload({waitUntil:"domcontentloaded"});
await cloudPage.locator("#steps").waitFor();
await cloudPage.waitForTimeout(250);
const reloadedDeviceState=await cloudPage.evaluate(()=>({
 steps:document.querySelector("#steps")?.textContent.trim()||"",
 cloudState:document.querySelector("#cloudState")?.textContent.trim()||"",
 migrated:localStorage.getItem("gativx.v2.account-local-migrated"),
 device:localStorage.getItem("gativx.v2.fresh.state.device")
}));
assert(reloadedDeviceState.steps==="—","Signed-out device exposed cached records after reload: "+JSON.stringify(reloadedDeviceState));
await cloudPage.close();

// Goal and personal purpose must survive a sign-in on another device through the shared profile row.
const goalCloudPage=await browser.newPage({viewport:{width:390,height:844}});
const goalCloudErrors=[];goalCloudPage.on("pageerror",e=>goalCloudErrors.push(e.message));
await goalCloudPage.addInitScript(()=>{
 localStorage.setItem("gativx.v2.fresh.state",JSON.stringify({version:2,goal:{type:"Weight loss",duration:"90 days",purpose:"I want to stay active with my family.",feeling:"energetic",createdAt:new Date().toISOString(),updatedAt:new Date().toISOString()},entries:{},walks:[]}));
 window.__goalCloud={profile:null,writes:[],currentUser:null};
 window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signInWithPassword:async()=>{window.__goalCloud.currentUser="goal-user";return {data:{user:{id:"goal-user"}},error:null}},signUp:async()=>({data:{user:null,session:null},error:null}),signOut:async()=>{window.__goalCloud.currentUser=null;return {error:null}}},from(table){return {select(){return {eq:async()=>({data:table==="profiles"?(window.__goalCloud.profile?[window.__goalCloud.profile]:[]):[],error:null})}},upsert:async(row)=>{if(table==="profiles")window.__goalCloud.profile=row;window.__goalCloud.writes.push({table,row});return {error:null}},insert:async()=>({error:null})}}})};
});
await goalCloudPage.route("https://**/*",r=>r.abort());
await goalCloudPage.goto(pathToFileURL(path.resolve("app-v2.html")).href,{waitUntil:"domcontentloaded"});
await goalCloudPage.locator("#cloudEmail").fill("goal@example.com");
await goalCloudPage.locator("#cloudPassword").fill("not-a-real-password");
await goalCloudPage.locator("#cloudSignIn").click();
await goalCloudPage.waitForFunction(()=>document.querySelector("#cloudState")?.textContent==="BACKUP CURRENT");
const savedGoal=await goalCloudPage.evaluate(()=>window.__goalCloud.profile);
assert(savedGoal?.goal_type==="Weight loss"&&savedGoal.goal_purpose==="I want to stay active with my family."&&savedGoal.goal_feeling==="energetic","Goal and personal purpose were not saved to the member's Supabase profile");
await goalCloudPage.close();

const secondDevicePage=await browser.newPage({viewport:{width:390,height:844}});
const secondDeviceErrors=[];secondDevicePage.on("pageerror",e=>secondDeviceErrors.push(e.message));
await secondDevicePage.addInitScript(()=>{
 window.__goalCloud={profile:{id:"goal-user",goal_type:"Weight loss",goal_duration:"90 days",goal_purpose:"I want to stay active with my family.",goal_feeling:"energetic",goal_started_at:new Date().toISOString(),goal_updated_at:new Date().toISOString()},currentUser:null,writes:[]};
 window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signInWithPassword:async()=>{window.__goalCloud.currentUser="goal-user";return {data:{user:{id:"goal-user"}},error:null}},signUp:async()=>({data:{user:null,session:null},error:null}),signOut:async()=>({error:null})},from(table){return {select(){return {eq:async()=>({data:table==="profiles"?(window.__goalCloud.profile?[window.__goalCloud.profile]:[]):[],error:null})}},upsert:async(row)=>{window.__goalCloud.writes.push({table,row});return {error:null}},insert:async()=>({error:null})}}})};
});
await secondDevicePage.route("https://**/*",r=>r.abort());
await secondDevicePage.goto(pathToFileURL(path.resolve("app-v2.html")).href,{waitUntil:"domcontentloaded"});
await secondDevicePage.locator("#cloudEmail").fill("goal@example.com");
await secondDevicePage.locator("#cloudPassword").fill("not-a-real-password");
await secondDevicePage.locator("#cloudSignIn").click();
await secondDevicePage.waitForFunction(()=>document.querySelector("#cloudState")?.textContent==="BACKUP CURRENT");
assert((await secondDevicePage.locator("#missionTitle").textContent()).includes("Weight loss"),"Second device did not restore the member's cloud goal");
assert((await secondDevicePage.locator("#guruPurpose").textContent()).includes("stay active with my family"),"Second device did not restore the member's personal purpose");
assert(secondDeviceErrors.length===0,"Goal cloud sync browser errors: "+secondDeviceErrors.join("; "));
await secondDevicePage.close();

// A member switch during an in-flight request must cancel the old member's
// merge/upload work before the new member's sync is allowed to proceed.
const racePage=await browser.newPage({viewport:{width:390,height:844}});
const raceErrors=[];racePage.on("pageerror",e=>raceErrors.push(e.message));
await racePage.addInitScript(()=>{
 const d=new Date(),day=d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0");
 localStorage.setItem("gativx.v2.fresh.state",JSON.stringify({version:2,goal:null,entries:{[day]:{weight:82,water:1200}},walks:[{date:day,distance:.02,createdAt:new Date().toISOString(),points:[{lat:12.97,lon:77.59,time:Date.now()-5000},{lat:12.9701,lon:77.59,time:Date.now()}]}]}));
 window.__race={uploads:[],inserts:[],currentUser:null,holdFirst:true,releaseFirst:null};
 window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signInWithPassword:async({email})=>{window.__race.currentUser=email.startsWith("first")?"race-user-A":"race-user-B";return {data:{user:{id:window.__race.currentUser},error:null}}},signUp:async()=>({data:{user:null,session:null},error:null}),signOut:async()=>{window.__race.currentUser=null;return {error:null}}},from(table){return {select(){return {eq:async()=>{const id=window.__race.currentUser;if(id==="race-user-A"&&window.__race.holdFirst){window.__race.holdFirst=false;await new Promise(resolve=>{window.__race.releaseFirst=resolve})}return {data:[],error:null}}}},upsert:async(rows)=>{window.__race.uploads.push({user:window.__race.currentUser,rows});return {error:null}},insert:async(row)=>{window.__race.inserts.push({user:window.__race.currentUser,row});return {error:null}}}}})};
});
await racePage.route("https://**/*",r=>r.abort());
await racePage.goto(pathToFileURL(path.resolve("app-v2.html")).href,{waitUntil:"domcontentloaded"});
await racePage.locator("#cloudEmail").fill("first@example.com");
await racePage.locator("#cloudPassword").fill("not-a-real-password");
await racePage.locator("#cloudSignIn").click();
await racePage.waitForFunction(()=>typeof window.__race.releaseFirst==="function");
await racePage.locator("#cloudSignOut").click();
await racePage.locator("#cloudEmail").fill("second@example.com");
await racePage.locator("#cloudPassword").fill("not-a-real-password");
await racePage.locator("#cloudSignIn").click();
await racePage.evaluate(()=>window.__race.releaseFirst());
await racePage.waitForFunction(()=>document.querySelector("#cloudState")?.textContent==="BACKUP CURRENT");
const raceResult=await racePage.evaluate(()=>({uploads:window.__race.uploads,inserts:window.__race.inserts,first:JSON.parse(localStorage.getItem("gativx.v2.fresh.state.user.race-user-A")),second:JSON.parse(localStorage.getItem("gativx.v2.fresh.state.user.race-user-B"))}));
assert(raceResult.uploads.length===0&&raceResult.inserts.length===0,"An in-flight first-account sync wrote data after switching accounts");
assert(raceResult.first.entries[Object.keys(raceResult.first.entries)[0]].weight===82&&Object.keys(raceResult.second.entries).length===0,"In-flight account switch mixed local member records");
assert(raceErrors.length===0,"Account-switch race browser errors: "+raceErrors.join("; "));
await racePage.close();

// Android Health Connect source labels and cloud reconciliation.
const androidHealthPage=await browser.newPage({viewport:{width:390,height:844}});
const androidHealthErrors=[];androidHealthPage.on("pageerror",e=>androidHealthErrors.push(e.message));
await androidHealthPage.addInitScript(()=>{
 const d=new Date(),today=d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0");
 const y=new Date(d.getTime()-86400000),yesterday=y.getFullYear()+"-"+String(y.getMonth()+1).padStart(2,"0")+"-"+String(y.getDate()).padStart(2,"0");
 const localStamp=new Date(Date.now()-120000).toISOString(),remoteStamp=new Date(Date.now()-60000).toISOString();
 localStorage.setItem("gativx.v2.fresh.state",JSON.stringify({version:2,goal:null,entries:{
  [today]:{steps:1000,stepsSource:"apple_health_shortcuts",stepsUpdatedAt:localStamp,activeEnergyKcal:100,activeEnergySource:"apple_health_shortcuts",activeEnergyUpdatedAt:localStamp},
  [yesterday]:{steps:5000,stepsSource:"health_connect",stepsUpdatedAt:localStamp}
 },walks:[]}));
 window.__hcMock={uploaded:[],currentUser:null};
 window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signInWithPassword:async()=>{window.__hcMock.currentUser="android-health-user";return {data:{user:{id:"android-health-user"}},error:null}},signUp:async()=>({data:{user:null,session:null},error:null}),signOut:async()=>({error:null})},from(table){return {select(){return {eq:async()=>({data:table==="daily_logs"?[
  {log_date:today,steps:3200,steps_source:"health_connect",steps_updated_at:remoteStamp,active_energy_kcal:250,active_energy_source:"health_connect",active_energy_updated_at:remoteStamp},
  {log_date:yesterday,steps:1200,steps_source:"manual",steps_updated_at:localStamp,active_energy_kcal:null,active_energy_source:null,active_energy_updated_at:null}
 ]:[],error:null})}},upsert:async(rows)=>{window.__hcMock.uploaded.push(...rows);return {error:null}},insert:async()=>({error:null})}}})};
});
await androidHealthPage.route("https://**/*",r=>r.abort());
await androidHealthPage.goto(pathToFileURL(path.resolve("app-v2.html")).href,{waitUntil:"domcontentloaded"});
await androidHealthPage.locator("#cloudEmail").fill("android@example.com");
await androidHealthPage.locator("#cloudPassword").fill("not-a-real-password");
await androidHealthPage.locator("#cloudSignIn").click();
await androidHealthPage.waitForFunction(()=>document.querySelector("#cloudState")?.textContent==="BACKUP CURRENT");
assert((await androidHealthPage.locator("#steps").textContent()).trim()==="3,200","Newer Android Health Connect steps did not replace an older Shortcut import");
assert((await androidHealthPage.locator("#stepNote").textContent()).trim()==="Android Health Connect","Android Health Connect source label was not displayed");
assert((await androidHealthPage.locator("#source").textContent()).trim()==="ANDROID HEALTH CONNECT","Android Health Connect summary source was not displayed");
assert((await androidHealthPage.locator("#vActiveEnergy").textContent()).trim()==="250 kcal","Newer Android active energy was not reconciled");
assert((await androidHealthPage.locator("#activeEnergySourceLabel").textContent()).trim()==="Health Connect · active energy","Android active-energy source label was not displayed");
const androidRows=await androidHealthPage.evaluate(()=>window.__hcMock.uploaded);
assert(androidRows.find(r=>r.steps_source==="health_connect"&&r.steps===3200),"Android Health Connect values were not preserved in the cloud upsert");
assert(androidRows.find(r=>r.steps_source==="manual"&&r.steps===1200),"A manual entry was overwritten by an older Android reading");
assert(androidHealthErrors.length===0,"Android Health Connect browser integration errors: "+androidHealthErrors.join("; "));
await androidHealthPage.close();

const storage=await page.evaluate(()=>({keys:Object.keys(localStorage),dailyLogs:localStorage.getItem("mission75.dailyLogs"),auth:localStorage.getItem("sb-crarbbsvcczwmtvxyrxo-auth-token"),session:sessionStorage.getItem("gativx.session.fixture")}));
assert(storage.keys.includes("gativx.v2.fresh.state"),"Fresh GATIVX store was not used");
assert(storage.dailyLogs==="preserve-existing-records-fixture","Existing Mission-75 browser records were changed or removed");
assert(storage.auth==="preserve-auth-session-fixture","Existing browser auth session was changed or removed");
assert(storage.session==="preserve-session-fixture","Existing sessionStorage was cleared");
// Exercise GATIVX v2 GPS filtering with deterministic browser location fixes.
const v2=await browser.newPage({viewport:{width:390,height:844}});
const v2Errors=[];v2.on("pageerror",e=>v2Errors.push(e.message));
await v2.addInitScript(()=>{let emit;const geo=navigator.geolocation;if(!geo)throw new Error("Browser geolocation API is unavailable in the smoke-test context");Object.defineProperty(geo,"watchPosition",{configurable:true,value(callback){emit=callback;window.__emitGPS=(lat,lon,accuracy=5,time=Date.now())=>emit({coords:{latitude:lat,longitude:lon,accuracy},timestamp:time});return 7;}});Object.defineProperty(geo,"clearWatch",{configurable:true,value(){}});});
await v2.route("https://**/*",r=>r.abort());
await v2.goto(pathToFileURL(path.resolve("app-v2.html")).href,{waitUntil:"domcontentloaded"});
await v2.locator('[data-panel="walk"]').click();
await v2.locator("#gpsStart").click();
const baseTime=Date.now();
await v2.evaluate(t=>window.__emitGPS(12.97000,77.59000,5,t),baseTime+1000);
await v2.evaluate(t=>window.__emitGPS(12.97018,77.59000,5,t),baseTime+5000);
assert((await v2.locator("#gpsDistance").textContent()).trim()==="0.02 km","Valid GPS segment was not measured; got "+await v2.locator("#gpsDistance").textContent()+"; status="+await v2.locator("#walkStatus").textContent()+"; errors="+v2Errors.join("; "));
await v2.locator("#gpsPause").click();
await v2.evaluate(t=>window.__emitGPS(12.98000,77.59000,5,t),baseTime+6000);
await v2.locator("#gpsPause").click();
await v2.evaluate(t=>window.__emitGPS(12.98000,77.59000,5,t),baseTime+8000);
await v2.evaluate(t=>window.__emitGPS(12.98009,77.59000,5,t),baseTime+10000);
assert((await v2.locator("#gpsDistance").textContent()).trim()==="0.03 km","GPS pause/resume incorrectly bridged the paused distance");
await v2.evaluate(t=>window.__emitGPS(12.98010,77.59000,100,t),baseTime+11000);
await v2.evaluate(t=>window.__emitGPS(12.99000,77.59000,5,t),baseTime+13000);
assert((await v2.locator("#gpsDistance").textContent()).trim()==="0.03 km","Inaccurate or implausible GPS fixes changed measured distance");
await v2.locator("#gpsFinish").click();
assert((await v2.locator("#walkStatus").textContent()).includes("0.03 km"),"Saved GPS walk distance did not match filtered route distance");
assert(v2Errors.length===0,"GATIVX v2 browser errors: "+v2Errors.join("; "));
await v2.close();
console.log("PASS: Published GATIVX root entry opens the tested v2 fitness application");
console.log("PASS: Apple Health Shortcut imports measured steps and active energy into the new GATIVX home");
console.log("PASS: GATIVX v2 account sign-in, private cloud backup and HealthKit source reconciliation");
console.log("PASS: GATIVX v2 uses its own namespaced data store");
console.log("PASS: existing Mission-75 records and auth/session storage are preserved");
console.log("PASS: mission, metrics and all five navigation tabs render without browser errors");
await browser.close();