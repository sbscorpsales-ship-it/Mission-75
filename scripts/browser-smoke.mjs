import { chromium, webkit } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";
import http from "node:http";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const root = process.cwd();
const mime = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".json": "application/json", ".webmanifest": "application/manifest+json", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".css": "text/css" };
const server = http.createServer((req, res) => {
  const pathname = decodeURIComponent(new URL(req.url, "http://127.0.0.1").pathname);
  const relative = pathname === "/" ? "index.html" : pathname.slice(1);
  const target = path.resolve(root, relative);
  if (!target.startsWith(root + path.sep) && target !== path.join(root, "index.html")) {
    res.writeHead(403).end("Forbidden"); return;
  }
  fs.readFile(target, (error, data) => {
    if (error) { res.writeHead(404).end("Not found"); return; }
    res.writeHead(200, { "Content-Type": mime[path.extname(target)] || "application/octet-stream", "Cache-Control": "no-store" });
    res.end(data);
  });
});
await new Promise(resolve => server.listen(4173, "127.0.0.1", resolve));
const baseUrl = "http://127.0.0.1:4173/";

const assert = (condition, message) => { if (!condition) throw new Error(message); };

async function smoke(engine, label) {
  const browser = await engine.launch({ headless: true });
  try {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 1,
      geolocation: { latitude: 15.85, longitude: 74.50, accuracy: 5 },
      permissions: ["geolocation"]
    });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    // Deterministic Geolocation API callback stub: exercise the app's real
    // watchPosition, route filtering, finish, and local persistence logic.
    await page.addInitScript(() => {
      const callbacks = [];
      window.__gativxGeoCallbacks = callbacks;
      Object.defineProperty(navigator, "geolocation", {
        configurable: true,
        value: {
          watchPosition(success) { callbacks.push(success); return callbacks.length; },
          clearWatch() {},
          getCurrentPosition(success) {
            success({ coords: { latitude: 15.85, longitude: 74.50, accuracy: 5 }, timestamp: Date.now() });
          }
        }
      });
    });
    await page.route("https://**/*", route => route.abort());
    await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
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

    // Exercise the real GPS start/finish/save path with deterministic browser geolocation.
    await page.locator('[data-tab="walk"]').click();
    await page.locator("#gpsStart").click();
    await page.waitForTimeout(150);
    await page.evaluate(() => window.__gativxGeoCallbacks[0]({
      coords: { latitude: 15.85, longitude: 74.50, accuracy: 5 }, timestamp: Date.now()
    }));
    await page.waitForTimeout(1400);
    await page.evaluate(() => window.__gativxGeoCallbacks[0]({
      coords: { latitude: 15.85005, longitude: 74.50005, accuracy: 5 }, timestamp: Date.now()
    }));
    await page.waitForTimeout(200);
    page.once("dialog", dialog => dialog.accept());
    await page.locator("#gpsFinish").click();
    await page.waitForTimeout(250);
    const sessions = await page.evaluate(() => JSON.parse(localStorage.getItem("mission75.gps.sessions.v1") || "[]"));
    assert(sessions.length === 1, label + ": GPS walk was not saved to local storage");
    assert((sessions[0].points || []).length >= 2, label + ": saved GPS walk is missing route points: " + JSON.stringify(sessions[0]));
    assert(Number(sessions[0].distanceMeters) > 0, label + ": saved GPS walk has no measured distance");
    assert(errors.length === 0, label + ": browser runtime errors: " + errors.join("; "));
    console.log("PASS: " + label + " mobile dashboard, six tabs, account controls, GPS start/finish, route-point persistence, and no uncaught runtime errors");
    await context.close();
  } finally {
    await browser.close();
  }
}

try {
  await smoke(chromium, "Chromium / Chrome engine");
  await smoke(webkit, "WebKit / Safari engine");
} finally {
  await new Promise(resolve => server.close(resolve));
}
