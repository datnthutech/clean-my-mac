#!/usr/bin/env python3
"""Checks every relative link, image and #anchor in README.md, CHANGELOG.md and docs/*.md.

Anchors are computed the way GitHub does (lower-case, punctuation and emoji removed, spaces -> hyphens),
so a heading that is renamed without updating the links pointing at it fails CI.
Usage: python3 scripts/check_docs.py
"""
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = [ROOT / "README.md", ROOT / "CHANGELOG.md"] + sorted((ROOT / "docs").glob("*.md"))


def slug(heading: str) -> str:
    text = heading.replace("`", "").strip().lower()
    kept = "".join(c for c in text if unicodedata.category(c)[0] in "LNM" or c in " -_")
    return kept.replace(" ", "-")


def anchors(path: pathlib.Path) -> set:
    seen, result, in_code = {}, set(), False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("```"):
            in_code = not in_code
        if in_code:
            continue
        match = re.match(r"^(#{1,6})\s+(.*)$", line)
        if match:
            base = slug(match.group(2))
            count = seen.get(base, 0)
            seen[base] = count + 1
            result.add(base if count == 0 else f"{base}-{count}")
    return result


def main() -> int:
    cache, problems = {}, []
    for file in FILES:
        text = re.sub(r"```.*?```", "", file.read_text(encoding="utf-8"), flags=re.S)
        rel = file.relative_to(ROOT)
        for match in re.finditer(r"(?<!!)\[[^\]]*\]\(([^)\s]+)\)", text):
            target = match.group(1)
            if re.match(r"^(https?:|mailto:)", target):
                continue
            path, _, fragment = target.partition("#")
            dest = (file.parent / path).resolve() if path else file
            if not dest.exists():
                problems.append(f"{rel}: missing file {target}")
            elif fragment and dest.suffix == ".md":
                if fragment not in cache.setdefault(dest, anchors(dest)):
                    problems.append(f"{rel}: missing anchor {target}")
        for match in re.finditer(r"!\[[^\]]*\]\(([^)\s]+)\)", text):
            target = match.group(1)
            if not re.match(r"^https?:", target) and not (file.parent / target).exists():
                problems.append(f"{rel}: missing image {target}")
        for match in re.finditer(r'<img[^>]*src="([^"]+)"', text):
            target = match.group(1)
            if not re.match(r"^https?:", target) and not (file.parent / target).exists():
                problems.append(f"{rel}: missing image {target}")
    if problems:
        print("\n".join(problems))
        return 1
    print(f"Docs OK: links, images and anchors in {len(FILES)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
