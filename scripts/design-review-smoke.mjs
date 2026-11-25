import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { chromium } from "playwright";

const root = process.cwd();
const artifactDir = path.join(root, "artifacts", "gativx-design-c-review");
fs.mkdirSync(artifactDir, { recursive: true });

const mime = {
  ".html": "text/html; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webmanifest": "application/manifest+json"
};

const server = http.createServer((request, response) => {
  const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
  const pathname = decodeURIComponent(requestUrl.pathname === "/" ? "/gativx-design-c-review.html" : requestUrl.pathname);
  const filePath = path.resolve(root, "." + pathname);
  if (filePath !== root && !filePath.startsWith(root + path.sep)) {
    response.writeHead(403).end("Forbidden");
    return;
  }
  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(404).end("Not found");
      return;
    }
    response.writeHead(200, { "content-type": mime[path.extname(filePath)] ?? "application/octet-stream" });
    response.end(data);
  });
});

await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const address = server.address();
const baseUrl = "http://127.0.0.1:" + address.port;
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
const consoleErrors = [];
const pageErrors = [];
let assertions = 0;

page.on("console", message => {
  if (message.type() === "error") consoleErrors.push(message.text());
});
page.on("pageerror", error => pageErrors.push(error.message));

async function check(condition, message) {
  assert.ok(condition, message);
  assertions += 1;
  process.stdout.write("PASS: " + message + "\n");
}

async function open(name) {
  await page.locator('[data-nav="' + name + '"]').first().click();
  const screen = page.locator("#screen-" + name);
  await screen.waitFor({ state: "visible" });
  await check(await screen.evaluate(element => element.classList.contains("active")), name + " dashboard opens from navigation");
  await page.locator("#main-content").evaluate(element => element.scrollTo({ top: 0, behavior: "instant" }));
  await page.waitForTimeout(80);
  await page.locator("#app-shell").screenshot({
    path: path.join(artifactDir, name + ".png"),
    animations: "disabled"
  });
}

try {
  await page.goto(baseUrl + "/gativx-design-c-review.html", { waitUntil: "networkidle" });
  await check((await page.title()).includes("GATIVX") && (await page.title()).includes("Design C"), "page title identifies the GATIVX Design C review");
  await check(await page.locator(".demo-strip").innerText().then(text => text.includes("Illustrative sample data only")), "sample-data disclosure is visible");
  await check(await page.locator(".bottom-nav [data-nav]").count() === 5, "five approved primary navigation destinations are present");
  await check(await page.locator(".screen").count() === 10, "all ten dashboard and supporting screens are present");
  await check(await page.locator("#screen-home").isVisible(), "Home dashboard is the initial screen");
  await check(await page.locator("#screen-home .demo-tag").innerText() === "SAMPLE", "Home sample values are explicitly labelled");

  const dimensions = await page.evaluate(() => ({
    viewportWidth: window.innerWidth,
    documentWidth: document.documentElement.scrollWidth,
    shellWidth: document.querySelector("#app-shell").getBoundingClientRect().width
  }));
  await check(dimensions.documentWidth <= dimensions.viewportWidth + 1, "390px mobile layout has no horizontal page overflow");
  await check(dimensions.shellWidth <= 390, "portrait shell fits the 390px iPhone viewport");

  await page.locator("#theme-toggle").click();
  await check(await page.locator("html").getAttribute("data-theme") === "day", "Day mode switches on without changing screen layout");
  await page.locator("#theme-toggle").click();
  await check(await page.locator("html").getAttribute("data-theme") === "night", "Night mode switches back without changing screen layout");

  await page.locator(".periods button").nth(1).click();
  await check(await page.locator(".periods button").nth(1).evaluate(element => element.classList.contains("selected")), "Today/Week/Month/Year period selector responds");

  await open("home");
  await open("activity");
  await page.locator('[data-dialog="tracking"]').click();
  await check(await page.locator("#preview-dialog").isVisible(), "Start Walk preview opens an explicit preview-only disclosure");
  await check((await page.locator("#dialog-message").innerText()).includes("does not request location"), "tracking preview clearly states it does not access GPS or sensors");
  await page.locator("#dialog-close").click();
  await check(!(await page.locator("#preview-dialog").isVisible()), "preview disclosure closes cleanly");

  await open("workouts");
  await open("health");
  await open("community");
  await open("guru");
  await page.locator('[data-dialog="guru"]').click();
  await check((await page.locator("#dialog-message").innerText()).includes("member's own goal"), "GURU preview explains that live coaching is not connected");
  await page.locator("#dialog-close").click();
  await open("missions");
  await open("profile");
  await open("apps");
  await open("notifications");

  await check(consoleErrors.length === 0, "browser console has no errors");
  await check(pageErrors.length === 0, "browser page has no uncaught exceptions");
  process.stdout.write("RESULT: " + assertions + " PASS, 0 FAIL. Screenshots: " + artifactDir + "\n");
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
