import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
await page.addInitScript(() => {
  let success;
  let nextId = 1;
  const watches = new Map();
  Object.defineProperty(navigator, "geolocation", {
    configurable: true,
    value: {
      watchPosition(callback) { const id = nextId++; success = callback; watches.set(id, callback); return id; },
      clearWatch(id) { watches.delete(id); },
      getCurrentPosition(callback) { success = callback; }
    }
  });
  window.__gativxEmitGPS = position => { if (success) success(position); };
});
const errors = [];
page.on("pageerror", error => errors.push(error.message));
await page.route("https://**/*", route => route.abort());
const fileUrl = pathToFileURL(path.resolve("index.html")).href;
await page.goto(fileUrl, { waitUntil: "domcontentloaded" });
await page.waitForTimeout(6500);

const assert = (condition, message) => { if (!condition) throw new Error(message); };
assert(await page.locator("#connectionHeading").isVisible(), "Connected-data hub is not visible");
assert(await page.locator(".activity-grid .tile").count() === 6, "Expected six dashboard metrics");
assert(await page.locator("[data-tab]").count() === 6, "Expected six navigation destinations");
assert(await page.locator("#accountQuick").isVisible(), "Quick account control is missing");

for (const tab of ["today", "trends", "log", "coach", "walk", "data"]) {
  await page.locator('[data-tab="' + tab + '"]').click();
  assert(await page.locator("#pane-" + tab).isVisible(), "Navigation failed for " + tab);
}
await page.locator("#accountQuick").click();
assert(await page.locator("#pane-data").isVisible(), "Quick account control did not open account settings");
assert(await page.locator("#cloudEmail").count() === 1, "Email sign-in field is missing");
assert(await page.locator("#cloudPassword").count() === 1, "Password sign-in field is missing");
assert(await page.locator("#cloudSignIn").count() === 1, "Sign-in action is missing");
assert(await page.locator("#cloudSignUp").count() === 1, "Sign-up action is missing");
assert(await page.locator("#cloudSyncNow").count() === 1, "Manual sync action is missing");
await page.locator('[data-tab="walk"]').click();
const walkStartedAt = Date.now();
await page.locator("#gpsStart").click();
const gpsPoint = (latitude, timestamp) => ({
  coords: { latitude, longitude: 74.5, accuracy: 5 },
  timestamp
});
await page.evaluate(({ point }) => window.__gativxEmitGPS(point), { point: gpsPoint(15.8500, Date.now()) });
await page.evaluate(({ point }) => window.__gativxEmitGPS(point), { point: gpsPoint(15.8501, Date.now() + 10000) });
assert((await page.locator("#gpsDistance").textContent()).includes("0.01"), "GPS mock did not produce a measurable route distance");
await page.locator("#gpsPause").click();
assert((await page.locator("#gpsTitle").textContent()).includes("paused"), "GPS pause state did not activate");
await page.locator("#gpsPause").click();
assert((await page.locator("#gpsTitle").textContent()).includes("progress"), "GPS resume state did not activate");
await page.evaluate(({ point }) => window.__gativxEmitGPS(point), { point: gpsPoint(15.8502, Date.now() + 20000) });
page.once("dialog", dialog => dialog.accept());
await page.locator("#gpsFinish").click();
const savedWalk = await page.evaluate(() => JSON.parse(localStorage.getItem("mission75.gps.sessions.v1") || "[]").slice(-1)[0] || null);
assert(savedWalk && savedWalk.distanceMeters > 0, "Finished GPS walk was not saved with distance");
assert(Math.abs(new Date(savedWalk.startedAt).getTime() - walkStartedAt) < 5000, "GPS walk start time was not preserved from the Start action");
assert(savedWalk.points.length >= 2, "GPS route points were not persisted");
assert((await page.locator("#vActivityType").textContent()).trim() === "Walk", "Saved GPS walk did not update dashboard activity type");
assert((await page.locator("#vDistance").textContent()).includes("km"), "Saved GPS walk did not update dashboard distance");
await page.reload({ waitUntil: "domcontentloaded" });
await page.waitForTimeout(800);
const persistedWalks = await page.evaluate(() => JSON.parse(localStorage.getItem("mission75.gps.sessions.v1") || "[]"));
assert(persistedWalks.length === 1, "Saved GPS walk did not survive page reload");
assert((await page.locator("#vActivityType").textContent()).trim() === "Walk", "Dashboard did not restore saved GPS activity after reload");
console.log("PASS: mocked GPS walk records route, distance, pause/resume and original start time");
console.log("PASS: saved GPS walk persists after reload and updates the dashboard");
assert(errors.length === 0, "Browser runtime errors: " + errors.join("; "));

console.log("PASS: mobile dashboard renders six activity metrics and connected-data hub");
console.log("PASS: all six navigation destinations and quick account access work");
console.log("PASS: sign-in, sign-up and manual cloud-sync controls are present");
console.log("PASS: no uncaught browser runtime errors");
await browser.close();
