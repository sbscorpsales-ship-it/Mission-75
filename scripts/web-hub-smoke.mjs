import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";
const browser = await chromium.launch({headless:true});
const page = await browser.newPage({viewport:{width:1440,height:1000}});
const errors = [];
page.on("pageerror", e => errors.push(e.message));
await page.goto(pathToFileURL(path.resolve("web-hub.html")).href,{waitUntil:"domcontentloaded"});
const assert=(condition,message)=>{if(!condition)throw new Error(message)};
assert(await page.locator(".sidebar").isVisible(),"Desktop sidebar is missing");
assert(await page.locator(".hero").isVisible(),"Branded hero is missing");
assert(await page.locator(".goal-strip .goal-box").count()===4,"Expected four goal summary cards");
assert(await page.locator(".grid-main .card").count()===3,"Expected progress, route and weight trend cards");
assert(await page.locator(".health-grid .health-card").count()===5,"Expected five health summary cards");
assert(await page.locator(".plan").isVisible(),"Daily plan is missing");
const destinations=["goals","activity","health","nutrition","sleep","hydration","reports","community","challenges","guru","settings"];
for(const name of destinations){
 await page.locator('[data-view="'+name+'"]').click();
 assert(await page.locator("#view-other").isVisible(),"Section did not open: "+name);
 assert((await page.locator("#page-title").textContent()).trim().length>0,"Section title missing: "+name);
}
await page.locator('[data-view="dashboard"]').click();
await page.locator("#search").fill("guru");
await page.locator("#search").press("Enter");
assert((await page.locator("#page-title").textContent()).includes("Guru"),"Search did not navigate to Guru");
// Restore the dashboard before asserting its responsive hero. The search assertion
// intentionally leaves Guru selected, where the dashboard hero is correctly hidden.
await page.locator('[data-view="dashboard"]').click();
assert(await page.locator(".hero").isVisible(),"Dashboard hero must be visible before responsive resize");
await page.setViewportSize({width:390,height:844});
assert(await page.locator(".nav").isVisible(),"Responsive navigation is missing");
assert(await page.locator(".hero").isVisible(),"Responsive hero is missing");
assert(errors.length===0,"Browser errors: "+errors.join("; "));
await browser.close();
console.log("GATIVX desktop Web Hub browser smoke passed at 1440px and 390px; all 11 sections and search navigation verified.");
