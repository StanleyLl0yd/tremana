#!/usr/bin/env python3
"""Validate localized string-table key parity before building any release."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Sources" / "TreMana" / "Resources"
LANGUAGES = ("en", "ru")
KEY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')


def parse(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith(("//", "/*", "*", "*/")):
            continue
        match = KEY.fullmatch(line)
        if not match:
            raise ValueError(f"{path}:{number}: invalid Localizable.strings entry")
        key, translated = match.groups()
        if key in result:
            raise ValueError(f"{path}:{number}: duplicate key {key!r}")
        if not translated:
            raise ValueError(f"{path}:{number}: empty value {key!r}")
        result[key] = translated
    if not result:
        raise ValueError(f"{path}: empty translation table")
    return result


def main() -> int:
    try:
        dictionaries = {
            language: parse(SOURCE / f"{language}.lproj" / "Localizable.strings")
            for language in LANGUAGES
        }
        base = set(dictionaries["en"])
        for language, values in dictionaries.items():
            keys = set(values)
            if keys != base:
                missing = sorted(base - keys)
                extra = sorted(keys - base)
                raise ValueError(f"{language}: missing={missing} extra={extra}")
            info = SOURCE / f"{language}.lproj" / "InfoPlist.strings"
            if not parse(info):
                raise ValueError(f"{language}: InfoPlist.strings is missing")
        print(f"Localization parity: {len(base)} keys × {len(LANGUAGES)} languages")
        return 0
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"Localization validation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
