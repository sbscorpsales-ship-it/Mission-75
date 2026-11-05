import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
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
assert(await page.locator("#stravaImportCard").isVisible(), "Strava history importer is missing");
const csv = 'Activity ID,Activity Date,Activity Name,Activity Type,Distance,Moving Time,Total Steps\\n12345,"Nov 20, 2025, 2:46:58 AM",Morning Walk,Walk,6491.6,3242,7340\n';
await page.locator("#stravaCsvFile").setInputFiles({ name: "activities.csv", mimeType: "text/csv", buffer: Buffer.from(csv) });
await page.locator("#stravaImportBtn").click();
assert((await page.locator("#stravaImportStatus").textContent()).includes("1 rows read"), "Strava CSV did not import");
assert((await page.locator("#stravaImportSummary").textContent()).includes("6.49 km"), "Strava distance conversion is incorrect");
await page.locator("#stravaImportBtn").click();
assert((await page.locator("#stravaImportSummary").textContent()).includes("1 activities stored"), "Duplicate Strava activity was not deduplicated");

assert(errors.length === 0, "Browser runtime errors: " + errors.join("; "));

console.log("PASS: mobile dashboard renders six activity metrics and connected-data hub");
console.log("PASS: all six navigation destinations and quick account access work");
console.log("PASS: sign-in, sign-up and manual cloud-sync controls are present");
console.log("PASS: no uncaught browser runtime errors");
await browser.close();
