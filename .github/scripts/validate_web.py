from html.parser import HTMLParser
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
html = (ROOT / "index.html").read_text(encoding="utf-8")
manifest = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))
assert manifest.get("display") == "standalone", "manifest must request standalone app display"
assert manifest.get("short_name") == "GATIVX", "short app name missing"
assert (ROOT / "sw.js").is_file(), "service worker missing"
assert (ROOT / "icon.svg").is_file(), "SVG app icon missing"
assert (ROOT / "apple-touch-icon.png").is_file(), "iPhone touch icon missing"
for icon in manifest.get("icons", []):
    assert (ROOT / icon["src"].removeprefix("./")).is_file(), f"manifest icon missing: {icon['src']}"

class InlineScripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_script = False
        self.external = False
        self.parts = []
        self.scripts = []
    def handle_starttag(self, tag, attrs):
        if tag.lower() == "script":
            self.in_script = True
            self.external = any(k.lower() == "src" for k, _ in attrs)
            self.parts = []
    def handle_data(self, data):
        if self.in_script and not self.external:
            self.parts.append(data)
    def handle_endtag(self, tag):
        if tag.lower() == "script" and self.in_script:
            if not self.external and "".join(self.parts).strip():
                self.scripts.append("".join(self.parts))
            self.in_script = False
            self.external = False

parser = InlineScripts()
parser.feed(html)
with tempfile.TemporaryDirectory() as temp:
    for i, script in enumerate(parser.scripts):
        path = Path(temp) / f"inline-{i}.js"
        path.write_text(script, encoding="utf-8")
        subprocess.run(["node", "--check", str(path)], check=True)
subprocess.run(["node", "--check", str(ROOT / "sw.js")], check=True)
print(f"PASS: manifest, icons, service worker, and {len(parser.scripts)} inline JavaScript blocks")
