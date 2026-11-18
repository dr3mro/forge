#!/usr/bin/env bats
load ../test_helper

@test "single-page website documents every CLI scope and option and has valid navigation targets" {
  run python3 - "$FORGE_PROJECT_DIR" <<'PY'
from collections import defaultdict
from html.parser import HTMLParser
from pathlib import Path
import sys

root = Path(sys.argv[1])

class Website(HTMLParser):
    def __init__(self):
        super().__init__()
        self.scope = None
        self.sections = defaultdict(list)
        self.ids = set()
        self.links = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if "id" in attributes:
            assert attributes["id"] not in self.ids, attributes["id"]
            self.ids.add(attributes["id"])
        if tag == "a" and attributes.get("href", "").startswith("#"):
            self.links.append(attributes["href"][1:])
        if tag == "details":
            self.scope = attributes["data-command"]

    def handle_endtag(self, tag):
        if tag == "details":
            self.scope = None

    def handle_data(self, data):
        if self.scope is not None:
            self.sections[self.scope].append(data)

site = Website()
site.feed((root / "docs/index.html").read_text())
assert {"install", "workflows", "commands"} <= site.ids
assert set(site.links) <= site.ids, set(site.links) - site.ids
for line in (root / "lib/cli-reference.tsv").read_text().splitlines():
    kind, scope, label, *_ = line.split("\t")
    assert scope in site.sections, scope
    assert label in "\n".join(site.sections[scope]), (kind, scope, label)
PY
  [ "$status" -eq 0 ]
}
