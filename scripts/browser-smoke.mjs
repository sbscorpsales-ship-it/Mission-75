import { chromium, webkit } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";

const assert = (condition, message) => { if (!condition) throw new Error(message); };
const fileUrl = pathToFileURL(path.resolve("index.html")).href;

async function smoke(engine, label) {
  const browser = await engine.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.route("https://**/*", route => route.abort());
    await page.goto(fileUrl, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(6500);

    assert(await page.locator("#connectionHeading").isVisible(), label + ": connected-data hub is not visible");
    assert(await page.locator(".activity-grid .tile").count() === 6, label + ": expected six dashboard metrics");
    assert(await page.locator("[data-tab]").count() === 6, label + ": expected six navigation destinations");
    assert(await page.locator("#accountQuick").isVisible(), label + ": quick account control is missing");

    for (const tab of ["today", "trends", "log", "coach", "walk", "data"]) {
      await page.locator('[data-tab="' + tab + '"]').click();
      assert(await page.locator("#pane-" + tab).isVisible(), label + ": navigation failed for " + tab);
    }
    await page.locator("#accountQuick").click();
    assert(await page.locator("#pane-data").isVisible(), label + ": quick account control did not open account settings");
    assert(await page.locator("#cloudEmail").count() === 1, label + ": email sign-in field is missing");
    assert(await page.locator("#cloudPassword").count() === 1, label + ": password sign-in field is missing");
    assert(await page.locator("#cloudSignIn").count() === 1, label + ": sign-in action is missing");
    assert(await page.locator("#cloudSignUp").count() === 1, label + ": sign-up action is missing");
    assert(await page.locator("#cloudSyncNow").count() === 1, label + ": manual cloud-sync action is missing");
    assert(errors.length === 0, label + ": browser runtime errors: " + errors.join("; "));
    console.log("PASS: " + label + " mobile viewport, six dashboard metrics, six navigation tabs, account controls, and no uncaught runtime errors");
  } finally {
    await browser.close();
  }
}

await smoke(chromium, "Chromium / Chrome engine");
await smoke(webkit, "WebKit / Safari engine");
