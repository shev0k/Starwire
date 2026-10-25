#!/usr/bin/env python3
"""Convert Starwire for Android's strings into an Xcode String Catalog.

Reads, under the repo root:
  app/src/main/res/values/strings.xml           English, the source language
  app/src/main/res/values-*/strings.xml         the translations
  app/src/main/res/values*/arrays.xml           string arrays (the same format)
  ios/Strings/strings-ios.xml                   iOS-only English strings

Writes ios/Limelight/Starwire/Localizable.xcstrings. The keys stay the Android resource names
(array items are name.0, name.1 and so on), so Swift code looks strings up by those names.

  python3 ios/scripts/strings-to-xcstrings.py          write the catalog
  python3 ios/scripts/strings-to-xcstrings.py --check  write nothing; exit 1 if the file differs

Standard library only. Exit codes: 0 fine, 1 the catalog on disk is out of date (--check),
2 a problem with the input (for example a key in both Android's strings and strings-ios.xml).
"""

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SOURCE_LANGUAGE = "en"
RES_DIR = Path("app/src/main/res")
IOS_STRINGS = Path("ios/Strings/strings-ios.xml")
CATALOG = Path("ios/Limelight/Starwire/Localizable.xcstrings")

IOS_STRINGS_HEADER = """<?xml version="1.0" encoding="utf-8"?>
<!--
  iOS-only strings, English only, in the same format as Android's strings.xml.
  strings-to-xcstrings.py merges them into Localizable.xcstrings with Android's strings.
  A key must not also exist in app/src/main/res/values/strings.xml: that is an error.
-->
<resources/>
"""

# Folder suffixes that look like a language code but are Android qualifiers
NOT_LANGUAGES = {"car", "any", "tv"}
# Android's old language codes, and "no", which Apple calls nb
LEGACY_LANGUAGES = {"in": "id", "iw": "he", "ji": "yi", "no": "nb"}
# When two folders give the same Apple locale, these win
PREFERRED_FOLDERS = {"values-zh-rTW"}
PLURAL_QUANTITIES = ("zero", "one", "two", "few", "many", "other")

REFERENCE = re.compile(r"@string/([A-Za-z0-9_.]+)")
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?([-#+0,]*)(\d+)?(?:\.(\d+))?([sSdfxXeEgGcC%])")
WHITESPACE = " \t\r\n\f\v"


class InputError(Exception):
    """A problem with the files being converted."""


class Report:
    def __init__(self):
        self.mappings = []
        self.warnings = []
        self.notes = []

    def lines(self):
        out = ["Locale mapping:"]
        out += ["  " + m for m in self.mappings] or ["  (none)"]
        out += ["Notes:"] + ["  " + n for n in self.notes] if self.notes else []
        out += ["Warnings:"] + ["  " + w for w in self.warnings] if self.warnings else []
        return out


# ---- Android string values ------------------------------------------------------------------


def element_text(elem):
    """Text of an element with inline markup (<b>, <xliff:g>...) dropped and its text kept."""
    parts = [elem.text or ""]
    for child in elem:
        parts.append(element_text(child))
        parts.append(child.tail or "")
    return "".join(parts)


def unescape_android(raw):
    """Android's rules for a string value: escapes, whole-string quotes, whitespace folding.

    An escaped character, and anything inside double quotes, is kept as written. Outside
    quotes, a run of whitespace becomes one space and the ends are trimmed, as aapt does.
    """
    out = []  # (character, foldable): foldable marks a space that came from plain whitespace
    quoted = False
    i = 0
    n = len(raw)
    while i < n:
        c = raw[i]
        if c == "\\" and i + 1 < n:
            nxt = raw[i + 1]
            if nxt == "n":
                out.append(("\n", False))
            elif nxt == "t":
                out.append(("\t", False))
            elif nxt == "u" and re.fullmatch(r"[0-9a-fA-F]{4}", raw[i + 2:i + 6]):
                out.append((chr(int(raw[i + 2:i + 6], 16)), False))
                i += 4
            else:  # \' \" \@ \? \\ and anything else: the character itself
                out.append((nxt, False))
            i += 2
            continue
        if c == '"':
            quoted = not quoted
        elif c in WHITESPACE and not quoted:
            if not out or not out[-1][1]:
                out.append((" ", True))
        else:
            out.append((c, False))
        i += 1
    while out and out[-1][1]:
        out.pop()
    while out and out[0][1]:
        out.pop(0)
    return "".join(ch for ch, _ in out)


def convert_placeholders(text):
    """Android's printf placeholders to Apple's. Returns (text, signature).

    The signature is a sorted list of (argument number, type), used to compare a translation
    with the English string. %% is not an argument.
    """
    signature = []
    implicit = 0

    def swap(m):
        nonlocal implicit
        index, flags, width, precision, conv = m.groups()
        if conv == "%":
            return m.group(0)
        if index:
            position = int(index)
        else:
            implicit += 1
            position = implicit
        kind = "@" if conv in "sS" else conv.lower()
        signature.append((position, kind))
        flags = flags.replace(",", "")
        out = "%" + (index + "$" if index else "") + flags + (width or "")
        if precision is not None:
            out += "." + precision
        return out + ("@" if kind == "@" else conv)

    return PLACEHOLDER.sub(swap, text), sorted(signature)


# ---- reading the XML ------------------------------------------------------------------------


class Resources:
    """What one set of resource files defines, with raw (not yet unescaped) values."""

    def __init__(self):
        self.strings = {}  # name -> raw
        self.plurals = {}  # name -> {quantity: raw}
        self.arrays = {}  # name -> [raw, ...]
        self.untranslatable = set()  # names of strings, plurals and arrays

    def add_file(self, path, report, label):
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as err:
            raise InputError("%s is not valid XML: %s" % (path, err))
        for elem in root:
            tag = elem.tag
            name = elem.get("name")
            if not isinstance(tag, str) or name is None:
                continue
            if elem.get("product") not in (None, "default"):
                continue
            if tag == "string":
                target = self.strings
                value = element_text(elem)
            elif tag == "plurals":
                target = self.plurals
                value = {}
                for item in elem.findall("item"):
                    quantity = item.get("quantity")
                    if quantity in PLURAL_QUANTITIES:
                        value[quantity] = element_text(item)
            elif tag == "string-array":
                target = self.arrays
                value = [element_text(item) for item in elem.findall("item")]
            else:
                continue
            if name in self.strings or name in self.plurals or name in self.arrays:
                report.warnings.append("%s: %s is defined twice; the last one is used"
                                       % (label, name))
                self.strings.pop(name, None)
                self.plurals.pop(name, None)
                self.arrays.pop(name, None)
            target[name] = value
            if elem.get("translatable") == "false":
                self.untranslatable.add(name)

    def keys(self):
        names = set(self.strings) | set(self.plurals)
        names |= {"%s.%d" % (a, i) for a, items in self.arrays.items() for i in range(len(items))}
        return names


def folder_locale(folder):
    """Apple locale for an Android values folder name, or None if it isn't a language folder."""
    m = re.fullmatch(r"values-b\+([A-Za-z0-9]{1,8}(?:\+[A-Za-z0-9]{1,8})*)", folder)
    if m:
        tags = m.group(1).split("+")
        tags[0] = LEGACY_LANGUAGES.get(tags[0], tags[0])
        return "-".join(tags)
    m = re.fullmatch(r"values-([a-z]{2,3})(?:-r([A-Z]{2}|[0-9]{3}))?", folder)
    if not m or m.group(1) in NOT_LANGUAGES:
        return None
    lang, region = m.groups()
    lang = LEGACY_LANGUAGES.get(lang, lang)
    if lang == "zh":
        if region == "CN":
            return "zh-Hans"
        if region in ("TW", "HK"):
            return "zh-Hant"
    if lang == "nb" and region == "NO":
        return "nb"
    return lang + ("-" + region if region else "")


def read_resources(root, report):
    """Returns (english Resources, {locale: Resources}) from the Android res folder."""
    res = root / RES_DIR
    english = Resources()
    base = res / "values"
    if not (base / "strings.xml").is_file():
        raise InputError("%s is missing" % (RES_DIR / "values" / "strings.xml"))
    for fname in ("strings.xml", "arrays.xml"):
        if (base / fname).is_file():
            english.add_file(base / fname, report, "values/" + fname)

    candidates = {}  # locale -> [folder names]
    for folder in sorted(p.name for p in res.iterdir() if p.is_dir()):
        if not folder.startswith("values-") or not (res / folder / "strings.xml").is_file():
            continue
        locale = folder_locale(folder)
        if locale is not None:
            candidates.setdefault(locale, []).append(folder)

    translations = {}
    for locale in sorted(candidates):
        folders = sorted(candidates[locale],
                         key=lambda f: (f not in PREFERRED_FOLDERS, len(f), f))
        for loser in folders[1:]:
            report.warnings.append("%s and %s both map to %s; %s is used, %s is left out"
                                   % (folders[0], loser, locale, folders[0], loser))
        folder = folders[0]
        found = Resources()
        for fname in ("strings.xml", "arrays.xml"):
            if (res / folder / fname).is_file():
                found.add_file(res / folder / fname, report, folder + "/" + fname)
        translations[locale] = found
        report.mappings.append("%s -> %s%s" % (folder, locale,
                                               "" if found.keys() else " (no strings)"))
    return english, translations


# ---- building the catalog -------------------------------------------------------------------


class Resolver:
    """Turns a raw value into final text, following @string/ references in one language."""

    def __init__(self, own, english, report):
        self.own = own  # Resources for this language (the English one for English)
        self.english = english
        self.report = report

    def resolve(self, raw, label, seen=()):
        """Returns (text, from_english): text is None if a reference can't be found."""
        ref = REFERENCE.fullmatch(raw.strip())
        if not ref:
            return unescape_android(raw), False
        name = ref.group(1)
        if name in seen:
            self.report.warnings.append("%s: @string/%s refers to itself" % (label, name))
            return None, False
        for source, fallback in ((self.own, False), (self.english, self.own is not self.english)):
            value = source.strings.get(name)
            if value is None or (not fallback and self.own is not self.english
                                 and unescape_android(value) == ""):
                continue
            text, inner = self.resolve(value, label, seen + (name,))
            if text is not None:
                return text, fallback or inner
        self.report.warnings.append("%s: @string/%s does not exist" % (label, name))
        return None, False


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural_unit(items):
    return {"variations": {"plural": {q: unit(v) for q, v in items.items()}}}


def build_catalog(root):
    """Returns (catalog dict, Report)."""
    report = Report()
    english, translations = read_resources(root, report)

    ios_path = root / IOS_STRINGS
    ios_only = Resources()
    if ios_path.is_file():
        ios_only.add_file(ios_path, report, str(IOS_STRINGS))
        clash = sorted(english.keys() & ios_only.keys())
        if clash:
            raise InputError("keys in both Android's strings and %s: %s"
                             % (IOS_STRINGS, ", ".join(clash)))
        for kind in ("strings", "plurals", "arrays"):
            getattr(english, kind).update(getattr(ios_only, kind))
        english.untranslatable |= ios_only.untranslatable

    entries = {}  # key -> catalog entry
    en_signature = {}  # key -> signature of English text (or {quantity: signature})
    en_resolver = Resolver(english, english, report)

    def add_english(key, untranslatable, localization):
        entry = {"extractionState": "manual",
                 "localizations": {SOURCE_LANGUAGE: localization}}
        if untranslatable:
            entry["shouldTranslate"] = False
        entries[key] = entry

    for name in sorted(english.strings):
        text, _ = en_resolver.resolve(english.strings[name], "en: " + name)
        if text is None:
            continue
        text, en_signature[name] = convert_placeholders(text)
        add_english(name, name in english.untranslatable, unit(text))

    for name in sorted(english.plurals):
        items = {}
        signatures = {}
        for quantity, raw in english.plurals[name].items():
            text, _ = en_resolver.resolve(raw, "en: %s[%s]" % (name, quantity))
            if text is not None:
                items[quantity], signatures[quantity] = convert_placeholders(text)
        if not items:
            continue
        en_signature[name] = signatures
        add_english(name, name in english.untranslatable, plural_unit(items))

    for name in sorted(english.arrays):
        for i, raw in enumerate(english.arrays[name]):
            key = "%s.%d" % (name, i)
            text, _ = en_resolver.resolve(raw, "en: " + key)
            if text is None:
                continue
            text, en_signature[key] = convert_placeholders(text)
            add_english(key, name in english.untranslatable, unit(text))

    def check_and_store(locale, key, text, signature):
        want = en_signature[key]
        if signature != want:
            report.warnings.append("%s: %s left out, its placeholders %s do not match English %s"
                                   % (locale, key, signature_text(signature), signature_text(want)))
            return False
        entries[key]["localizations"][locale] = unit(text)
        return True

    skipped = {}
    for locale in sorted(translations):
        found = translations[locale]
        resolver = Resolver(found, english, report)

        for name in sorted(found.strings):
            if name not in english.strings or name in english.untranslatable:
                skipped.setdefault(locale, []).append(name)
                continue
            if name not in entries:
                continue
            text, from_english = resolver.resolve(found.strings[name], "%s: %s" % (locale, name))
            if not text or from_english:
                continue
            text, signature = convert_placeholders(text)
            check_and_store(locale, name, text, signature)

        for name in sorted(found.plurals):
            if name not in english.plurals or name in english.untranslatable:
                skipped.setdefault(locale, []).append(name)
                continue
            if name not in entries:
                continue
            items = {}
            for quantity, raw in found.plurals[name].items():
                text, from_english = resolver.resolve(raw, "%s: %s[%s]" % (locale, name, quantity))
                if text and not from_english:
                    text, signature = convert_placeholders(text)
                    want = en_signature[name].get(quantity, en_signature[name].get("other"))
                    if signature != want:
                        report.warnings.append(
                            "%s: %s[%s] left out, its placeholders %s do not match English %s"
                            % (locale, name, quantity, signature_text(signature),
                               signature_text(want)))
                        items = None
                        break
                    items[quantity] = text
            if items and "other" in items:
                entries[name]["localizations"][locale] = plural_unit(items)

        for name in sorted(english.arrays):
            if name in english.untranslatable:
                continue
            english_items = english.arrays[name]
            own_items = found.arrays.get(name)
            if own_items is not None and len(own_items) != len(english_items):
                report.warnings.append("%s: array %s has %d items, English has %d; left out"
                                       % (locale, name, len(own_items), len(english_items)))
                continue
            for i, english_raw in enumerate(english_items):
                key = "%s.%d" % (name, i)
                if key not in entries:
                    continue
                if own_items is not None:
                    raw = own_items[i]
                elif REFERENCE.fullmatch(english_raw.strip()):
                    raw = english_raw  # the English item is a reference: use this language's
                else:
                    continue
                text, from_english = resolver.resolve(raw, "%s: %s" % (locale, key))
                if not text or from_english:
                    continue
                text, signature = convert_placeholders(text)
                check_and_store(locale, key, text, signature)

    for locale in sorted(skipped):
        report.notes.append("%s: %d translation(s) skipped, no English string or not translatable"
                            % (locale, len(skipped[locale])))

    for key in list(entries):
        if not entries[key]["localizations"]:
            del entries[key]
    catalog = {"sourceLanguage": SOURCE_LANGUAGE, "strings": entries, "version": "1.0"}
    return catalog, report


def signature_text(signature):
    return "[" + ", ".join("%d$%s" % (p, k) for p, k in signature) + "]" if signature else "[]"


def render(catalog):
    """The catalog as Xcode writes it: sorted keys, " : " separator, 2-space indent."""
    text = json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False,
                      separators=(",", " : "))
    return text + "\n"


def languages_in(catalog):
    found = set()
    for entry in catalog["strings"].values():
        found |= set(entry["localizations"])
    found.discard(SOURCE_LANGUAGE)
    return sorted(found)


def differing_keys(expected, on_disk_text):
    """Keys whose entries differ between the expected catalog and the file's text."""
    try:
        on_disk = json.loads(on_disk_text)
    except ValueError:
        return None
    have = on_disk.get("strings", {})
    want = expected["strings"]
    keys = sorted(k for k in set(have) | set(want) if have.get(k) != want.get(k))
    if on_disk.get("sourceLanguage") != expected["sourceLanguage"]:
        keys.insert(0, "(sourceLanguage)")
    if on_disk.get("version") != expected["version"]:
        keys.insert(0, "(version)")
    return keys


def write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))


def main(argv=None):
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Convert Android strings to a String Catalog.")
    parser.add_argument("--check", action="store_true",
                        help="write nothing; exit 1 if the catalog on disk is out of date")
    parser.add_argument("--root", type=Path, default=here.parent.parent,
                        help="the repo root (default: this script's repo)")
    args = parser.parse_args(argv)
    root = args.root

    try:
        if not args.check and not (root / IOS_STRINGS).exists():
            write_text(root / IOS_STRINGS, IOS_STRINGS_HEADER)
        catalog, report = build_catalog(root)
    except InputError as err:
        print("error: %s" % err, file=sys.stderr)
        return 2

    for line in report.lines():
        print(line)
    expected = render(catalog)
    languages = languages_in(catalog)
    print("%d keys, %d languages besides English" % (len(catalog["strings"]), len(languages)))

    path = root / CATALOG
    if args.check:
        try:
            # A Windows checkout with core.autocrlf turns LF into CRLF; the commit has LF
            current = path.read_bytes().decode("utf-8").replace("\r\n", "\n")
        except FileNotFoundError:
            print("%s does not exist; run this script without --check" % CATALOG)
            return 1
        if current == expected:
            print("%s is current" % CATALOG)
            return 0
        keys = differing_keys(catalog, current)
        print("%s is out of date; run this script without --check" % CATALOG)
        if keys is None:
            print("  the file is not valid JSON")
        elif not keys:
            print("  same keys and values, but the formatting differs")
        else:
            for key in keys[:100]:
                print("  differs: " + key)
            if len(keys) > 100:
                print("  ... and %d more" % (len(keys) - 100))
        return 1

    write_text(path, expected)
    print("wrote %s" % CATALOG)
    return 0


if __name__ == "__main__":
    sys.exit(main())
