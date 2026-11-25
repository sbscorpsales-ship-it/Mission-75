import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {pathToFileURL} from "node:url";
import {chromium} from "playwright";

const htmlPath=path.resolve("gativx-visual-preview.html");
assert.ok(fs.existsSync(htmlPath),"visual preview HTML must exist");
const html=fs.readFileSync(htmlPath,"utf8");
for(const id of ["home","journey","record","walk","coach","explore","missions","community","member-profile","apps","notifications"]){
  assert.ok(html.includes('id="'+id+'"'),"missing screen panel: "+id);
}
for(const label of ["SCREEN PREVIEW","visual preview only","No real members","No reminders or push notifications are scheduled"]){
  assert.ok(html.toLowerCase().includes(label.toLowerCase()),"missing preview disclosure: "+label);
}
const out=path.resolve("artifacts/gativx-visual-preview");
fs.mkdirSync(out,{recursive:true});
const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
  const errors=[];
  page.on("pageerror",error=>errors.push(error.message));
  await page.route("https://**/*",route=>route.abort());
  await page.goto(pathToFileURL(htmlPath).href,{waitUntil:"domcontentloaded"});
  const capture=async(name)=>{
    const panel=page.locator("#"+name+".panel.active");
    await panel.waitFor({state:"visible"});
    await page.screenshot({path:path.join(out,name+".png"),fullPage:true});
  };
  await capture("home");
  await page.locator('[data-panel="explore"]').click();
  await capture("explore");
  for(const name of ["missions","community","member-profile","apps","notifications"]){
    // Each preview card lives inside Explore; return there before selecting the next screen.
    await page.locator('[data-panel="explore"]').click();
    await page.locator('[data-go="'+name+'"]').click();
    await capture(name);
  }
  await page.locator("#profile").click();
  await capture("profile-header-entry");
  assert.deepEqual(errors,[],"browser runtime errors: "+errors.join("; "));
  console.log("PASS: 8 visual screens rendered and captured at 390x844.");
  console.log("PASS: Explore cards and header profile entry navigate to the expected panels.");
  console.log("PASS: Preview-only screens carry non-production disclosures.");
}finally{
  await browser.close();
}
