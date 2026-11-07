import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
const errors = [];
page.on("pageerror", error => errors.push(error.message));
await page.addInitScript(() => {
  const today = new Date();
  const key = today.getFullYear() + "-" + String(today.getMonth()+1).padStart(2,"0") + "-" + String(today.getDate()).padStart(2,"0");
  localStorage.setItem("gativx.goal.v1", JSON.stringify({ target: "75 kg", timeframe: "6 months", category: "Weight" }));
  localStorage.setItem("gativx.motionDaily.v1", JSON.stringify({ [key]: { steps: 1948, measuredAt: new Date().toISOString() } }));
  localStorage.setItem("mission75.settings.v1", JSON.stringify({ stepGoal: 10000 }));
  localStorage.setItem("mission75.logs.v1", JSON.stringify({ [key]: { water: 1500, protein: 65, distance: 0.4 } }));
});
await page.route("https://**/*", route => route.abort());
const fileUrl = pathToFileURL(path.resolve("index.html")).href;
await page.goto(fileUrl, { waitUntil: "domcontentloaded" });
await page.waitForTimeout(2500);

const assert = (condition, message) => { if (!condition) throw new Error(message); };
assert(await page.locator("#steps").textContent().then(x => x.trim()) === "1,948", "Today's confirmed motion step total did not render");
assert((await page.locator("#missionTitle").textContent()).includes("75 kg"), "Saved active mission did not render");
assert((await page.locator("#missionPct").textContent()).includes("19%"), "Step-goal progress did not calculate correctly");
assert((await page.locator("#distance").textContent()).includes("0.4 km"), "Saved manual distance did not render");
assert(await page.locator(".bottom button").count() === 5, "Expected five primary navigation destinations");
for (const tab of ["home", "journey", "record", "walk", "coach"]) {
  await page.locator('[data-panel="' + tab + '"]').click();
  assert(await page.locator("#" + tab + ".panel.active").count() === 1, "Navigation failed for " + tab);
}
await page.locator('[data-panel="home"]').click();
assert(await page.locator("#missionTitle").textContent().then(x => x.includes("75 kg")), "Mission changed after navigation");
assert(errors.length === 0, "Browser runtime errors: " + errors.join("; "));
console.log("PASS: new mobile GATIVX home renders confirmed steps, active mission and daily metrics");
console.log("PASS: five navigation destinations work and preserve displayed mission");
console.log("PASS: no uncaught browser runtime errors");
await browser.close();
