#!/usr/bin/env python3
"""Checks that every localization key used in the app exists in every language.

- Static keys are extracted from `l.t("...")` / `localizer.t("...")` calls and `message = "..."`.
- Keys built at runtime (e.g. "category.\\(...)") are expanded from the enum cases listed below.
- Fails when a key is missing, a file has a syntax error, or placeholders (%@) differ between languages.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "App" / "Sources"
LANGUAGES = ["en", "vi"]

CATEGORIES = ["applications", "documents", "media", "music", "archives", "developer", "caches",
              "iosBackups", "mail", "trash", "docker", "system", "other"]
HOTSPOTS = ["xcodeDerivedData", "xcodeArchives", "simulators", "userCaches", "trash", "iosBackups",
            "nodeModules", "downloads", "homebrewCache"]
HELP_TOPICS = ["quickStart", "fullDiskAccess", "scanning", "severity", "folders", "duplicates",
               "docker", "deleting", "faq"]

DYNAMIC_KEYS = (
    [f"severity.{s}" for s in ["critical", "warning", "info", "ok"]]
    + [f"category.{c}" for c in CATEGORIES]
    + [f"category.{c}.detail" for c in CATEGORIES]
    + [f"hotspot.{h}" for h in HOTSPOTS]
    + [f"hotspot.{h}.detail" for h in HOTSPOTS]
    + [f"drive.tab.{t}" for t in ["categories", "folders", "largeFiles"]]
    + [f"volume.kind.{k}" for k in ["system", "internalDrive", "external"]]
    + [f"folders.sort.{s}" for s in ["size", "name", "date"]]
    + [f"settings.external.{b}" for b in ["ask", "always", "never"]]
    + [f"language.{lang}" for lang in ["system", "vi", "en"]]
    + [f"help.{t}.title" for t in HELP_TOPICS]
    + [f"help.{t}.body" for t in HELP_TOPICS if t != "quickStart"]
    + [f"help.quickStart.step{i}.{part}" for i in range(1, 5) for part in ["title", "body"]]
    + [f"docker.step{i}" for i in range(1, 5)]
    + [f"onboarding.feature{i}" for i in range(1, 5)]
    + ["finding.lowSpace.critical.startup", "finding.lowSpace.warning.startup", "finding.lowSpace.external"]
)

ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')


def parse_strings(path: pathlib.Path) -> dict:
    entries = {}
    in_comment = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if in_comment:
            if "*/" in stripped:
                in_comment = False
            continue
        if not stripped or stripped.startswith("//"):
            continue
        if stripped.startswith("/*"):
            in_comment = "*/" not in stripped
            continue
        match = ENTRY.match(line)
        if not match:
            sys.exit(f"{path}:{number}: syntax error: {line}")
        key, value = match.groups()
        if key in entries:
            sys.exit(f"{path}:{number}: duplicate key {key}")
        entries[key] = value
    return entries


def used_keys() -> set:
    keys = set(DYNAMIC_KEYS)
    call = re.compile(r'\bt\("((?:[^"\\]|\\.)*)"')
    message = re.compile(r'message = "([^"]+)"')
    for file in SOURCES.rglob("*.swift"):
        text = file.read_text(encoding="utf-8")
        for key in call.findall(text) + message.findall(text):
            if "\\(" not in key:
                keys.add(key)
    return keys


WIN_APP = ROOT / "windows" / "src" / "CleanMyMac.App"
WIN_HOTSPOTS = ["windowsTemp", "userTemp", "windowsUpdateCache", "windowsOld", "recycleBin", "browserCaches", "nodeModules",
                "downloads", "iosBackups", "nuGetCache", "npmCache", "visualStudioCache"]
WIN_DYNAMIC_KEYS = (
    [f"severity.{s}" for s in ["critical", "warning", "info", "ok"]]
    + [f"volume.kind.{k}" for k in ["system", "internalDrive", "external"]]
    + [f"category.{c}" for c in CATEGORIES] + [f"category.{c}.detail" for c in CATEGORIES]
    + [f"hotspot.win.{h}" for h in WIN_HOTSPOTS] + [f"hotspot.win.{h}.detail" for h in WIN_HOTSPOTS]
    + [f"drive.tab.{t}" for t in ["categories", "folders", "largeFiles"]]
    + [f"docker.step{i}" for i in range(1, 5)]
    + [f"onboarding.feature{i}" for i in range(1, 5)]
    + [f"language.{lang}" for lang in ["system", "vi", "en"]]
    + [f"win.help.quickStart.step{i}.{part}" for i in range(1, 5) for part in ["title", "body"]]
    + [f"help.{t}.title" for t in ["quickStart", "severity", "folders", "duplicates"]]
    + ["help.severity.body", "help.duplicates.body", "win.help.folders.body"]
    + [f"win.help.{t}.{part}" for t in ["admin", "scanning", "docker", "deleting", "faq"] for part in ["title", "body"]]
    + ["win.finding.lowSpace.critical", "win.finding.lowSpace.warning", "finding.lowSpace.external"]
)


def check_windows(base_tables: dict) -> list:
    """Windows app: shared .strings + Windows overrides must cover every key the C# code uses."""
    if not WIN_APP.exists():
        return []
    overlays = {lang: parse_strings(WIN_APP / "Strings" / f"{lang}.strings") for lang in LANGUAGES}
    merged = {lang: {**base_tables[lang], **overlays[lang]} for lang in LANGUAGES}
    keys = set(WIN_DYNAMIC_KEYS)
    call = re.compile(r'\bT\("((?:[^"\\]|\\.)*)"')
    for file in WIN_APP.rglob("*.cs"):
        for key in call.findall(file.read_text(encoding="utf-8")):
            if not key.endswith("."):
                keys.add(key)
    problems = []
    for lang in LANGUAGES:
        for key in sorted(keys - merged[lang].keys()):
            problems.append(f"[windows/{lang}] missing key: {key}")
    if overlays["en"].keys() != overlays["vi"].keys():
        for key in sorted(overlays["en"].keys() ^ overlays["vi"].keys()):
            problems.append(f"[windows] override exists in only one language: {key}")
    for key, value in overlays["vi"].items():
        if key in overlays["en"] and value.count("%@") != overlays["en"][key].count("%@"):
            problems.append(f"[windows/vi] placeholder count differs for {key}")
    if not problems:
        print(f"Windows localization OK: {len(keys)} keys × {len(LANGUAGES)} languages")
    return problems


def main() -> int:
    tables = {lang: parse_strings(ROOT / "App" / "Resources" / f"{lang}.lproj" / "Localizable.strings") for lang in LANGUAGES}
    needed = used_keys()
    problems = []
    for lang, table in tables.items():
        for key in sorted(needed - table.keys()):
            problems.append(f"[{lang}] missing key: {key}")
    reference = tables["en"]
    for lang, table in tables.items():
        for key, value in table.items():
            if key in reference and value.count("%@") != reference[key].count("%@"):
                problems.append(f"[{lang}] placeholder count differs for {key}")
            if key not in reference:
                problems.append(f"[{lang}] key not in en: {key}")
    unused = sorted(reference.keys() - needed)
    for key in unused:
        print(f"note: unused key {key}")
    problems += check_windows(tables)
    if problems:
        print("\n".join(problems))
        return 1
    print(f"Localization OK: {len(needed)} keys × {len(LANGUAGES)} languages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
