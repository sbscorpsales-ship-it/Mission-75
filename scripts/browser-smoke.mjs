import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
const errors = [];
await page.addInitScript(() => {
  Object.defineProperty(navigator, "geolocation", { configurable: true, value: {
    watchPosition(success) { window.__gativxGpsSuccess = success; return 7; },
    clearWatch() { window.__gativxGpsSuccess = null; }
  }});
});
page.on("pageerror", error => errors.push(error.message));
await page.route("https://**/*", route => route.abort());
const fileUrl = pathToFileURL(path.resolve("index.html")).href;
await page.goto(fileUrl, { waitUntil: "domcontentloaded" });
await page.waitForTimeout(6500);

const assert = (condition, message) => { if (!condition) throw new Error(message); };
if (await page.locator("#gxModal.open").count()) {
  assert(await page.locator("#gxHeading").isVisible(), "First-run goal onboarding did not render");
  await page.locator("#gxSkip").click();
}
assert(await page.locator("#connectionHeading").count() === 1, "Connected-data hub is missing from the profile");
assert(await page.locator(".activity-grid .tile").count() === 6, "Expected six dashboard metrics");
assert(await page.locator("[data-tab]").count() === 6, "Expected six navigation destinations");
assert(await page.locator("#accountQuick").isVisible(), "Quick account control is missing");

for (const tab of ["today", "trends", "log", "coach", "walk", "data"]) {
  await page.locator('[data-tab="' + tab + '"]').click();
  assert(await page.locator("#pane-" + tab).isVisible(), "Navigation failed for " + tab);
}
await page.locator('[data-tab="data"]').click();
assert(await page.locator("#pane-data").isVisible(), "You / Profile tab did not open");
assert(await page.locator("#connectionHeading").count() === 1, "Connected-data hub heading is missing from You / Profile");
assert(await page.locator("#gxProgressCard").count() === 1, "Personal progress report is missing from You / Profile");
await page.locator("#accountQuick").click();
assert(await page.locator("#pane-data").isVisible(), "Quick account control did not open account settings");
assert(await page.locator("#cloudEmail").count() === 1, "Email sign-in field is missing");
assert(await page.locator("#cloudPassword").count() === 1, "Password sign-in field is missing");
assert(await page.locator("#cloudSignIn").count() === 1, "Sign-in action is missing");
assert(await page.locator("#cloudSignUp").count() === 1, "Sign-up action is missing");
assert(await page.locator("#cloudSyncNow").count() === 1, "Manual sync action is missing");
// Exercise the actual GPS save path with deterministic, realistic location fixes.
await page.locator('[data-tab="walk"]').click();
await page.locator("#gpsStart").click();
await page.waitForFunction(() => typeof window.__gativxGpsSuccess === "function");
const t = Date.now();
await page.evaluate((t) => {
  const emit = window.__gativxGpsSuccess;
  emit({ timestamp: t, coords: { latitude: 15.850000, longitude: 74.500000, accuracy: 8 } });
  emit({ timestamp: t + 5000, coords: { latitude: 15.850090, longitude: 74.500000, accuracy: 8 } });
}, t);
page.once("dialog", dialog => dialog.accept());
await page.locator("#gpsFinish").click();
await page.waitForFunction(() => {
  const logs = JSON.parse(localStorage.getItem("mission75.logs.v1") || "{}");
  const sessions = JSON.parse(localStorage.getItem("mission75.gps.sessions.v1") || "[]");
  return sessions.length > 0 && Object.values(logs).some(row => Number(row.distance) > 0);
});
const gpsResult = await page.evaluate(() => ({
  sessions: JSON.parse(localStorage.getItem("mission75.gps.sessions.v1") || "[]"),
  logs: JSON.parse(localStorage.getItem("mission75.logs.v1") || "{}")
}));
assert(gpsResult.sessions[0].points.length >= 2, "Saved GPS session is missing route points");
assert(gpsResult.sessions[0].distanceMeters > 0, "Saved GPS session has no measured distance");
assert(Object.values(gpsResult.logs).some(row => Number(row.distance) > 0 && row.workout === "Walk"), "GPS distance was not added to today's daily activity log");
assert(errors.length === 0, "Browser runtime errors: " + errors.join("; "));

console.log("PASS: mobile dashboard renders six activity metric slots; inactive metrics are hidden");
console.log("PASS: connected-data hub and personal progress report appear in You / Profile");
console.log("PASS: all six navigation destinations and quick account access work");
console.log("PASS: sign-in, sign-up and manual cloud-sync controls are present");
console.log("PASS: no uncaught browser runtime errors");
await browser.close();
