"""Tests for ios/scripts/strings-to-xcstrings.py.

Run from the repo root: python3 -m unittest discover -s ios/scripts/tests -v
Each rule is checked on a small fixture written to a temporary folder. No network, no clock.
"""

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "strings-to-xcstrings.py"
REPO_ROOT = SCRIPT.parent.parent.parent

spec = importlib.util.spec_from_file_location("strings_to_xcstrings", SCRIPT)
conv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(conv)

HEADER = '<?xml version="1.0" encoding="utf-8"?>\n'
RES = "app/src/main/res/"


def resources(body, extra_ns=""):
    return HEADER + '<resources xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2"%s>\n%s\n</resources>\n' % (
        extra_ns, body)


class Fixture:
    """A temporary repo root holding the given files."""

    def __init__(self, files):
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name)
        for rel, text in files.items():
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(text.encode("utf-8"))

    def close(self):
        self._dir.cleanup()


class ConverterTestCase(unittest.TestCase):
    def build(self, english, translations=None, ios=None, extra=None):
        """Build a catalog from inline XML. translations maps a folder suffix ("de") to XML."""
        files = {RES + "values/strings.xml": resources(english)}
        for suffix, body in (translations or {}).items():
            files[RES + "values-%s/strings.xml" % suffix] = resources(body)
        if ios is not None:
            files["ios/Strings/strings-ios.xml"] = resources(ios)
        files.update(extra or {})
        fixture = Fixture(files)
        self.addCleanup(fixture.close)
        self.root = fixture.root
        catalog, report = conv.build_catalog(fixture.root)
        return catalog["strings"], report

    def value(self, strings, key, locale="en"):
        return strings[key]["localizations"][locale]["stringUnit"]["value"]


class UnescapeTests(ConverterTestCase):
    def test_android_escapes(self):
        self.assertEqual(conv.unescape_android(r"it\'s \"fine\""), "it's \"fine\"")
        self.assertEqual(conv.unescape_android(r"a\nb\tc"), "a\nb\tc")
        self.assertEqual(conv.unescape_android(r"\@home \?"), "@home ?")
        self.assertEqual(conv.unescape_android("back\\\\slash"), "back\\slash")
        self.assertEqual(conv.unescape_android(r"café …"), "café …")

    def test_whole_string_quotes_are_removed_and_inside_kept(self):
        self.assertEqual(conv.unescape_android('"  two   spaces  "'), "  two   spaces  ")
        self.assertEqual(conv.unescape_android('"a\n   b"'), "a\n   b")

    def test_whitespace_collapses_and_ends_are_trimmed(self):
        self.assertEqual(conv.unescape_android("  a \n\t  b  "), "a b")
        # an escaped newline is kept, and so is a space after it
        self.assertEqual(conv.unescape_android("a\\n  b"), "a\n b")

    def test_markup_cdata_and_references_in_xml(self):
        strings, _ = self.build(
            '<string name="markup">Hello <b>big</b> <i>wide</i> <u>w</u> '
            '<xliff:g id="x" example="PC">%1$s</xliff:g>!</string>\n'
            '<string name="cdata"><![CDATA[Tap <here> & go]]></string>\n'
            '<string name="entity">Fish &amp; chips</string>')
        self.assertEqual(self.value(strings, "markup"), "Hello big wide w %1$@!")
        self.assertEqual(self.value(strings, "cdata"), "Tap <here> & go")
        self.assertEqual(self.value(strings, "entity"), "Fish & chips")


class PlaceholderTests(ConverterTestCase):
    def test_conversion(self):
        cases = {
            "%s": "%@",
            "%1$s of %2$s": "%1$@ of %2$@",
            "%d and %1$d": "%d and %1$d",
            "%,d files": "%d files",
            "%1$,d": "%1$d",
            "%.1f": "%.1f",
            "%1$.2f%%": "%1$.2f%%",
            "100%%": "100%%",
            "%05d": "%05d",
            "%3$+.1f": "%3$+.1f",
            "50% done": "50% done",
        }
        for source, want in cases.items():
            self.assertEqual(conv.convert_placeholders(source)[0], want, source)

    def test_signature_ignores_order_and_percent_signs(self):
        a = conv.convert_placeholders("%1$s has %2$d%%")[1]
        b = conv.convert_placeholders("%2$d for %1$s")[1]
        self.assertEqual(a, b)
        self.assertEqual(conv.convert_placeholders("%s")[1], conv.convert_placeholders("%1$s")[1])
        self.assertNotEqual(conv.convert_placeholders("%s")[1], conv.convert_placeholders("%d")[1])

    def test_matching_translation_is_kept(self):
        strings, report = self.build_pair("Hello %1$s, %2$d new", "Hallo %2$d neu, %1$s")
        self.assertEqual(self.value(strings, "k", "de"), "Hallo %2$d neu, %1$@")
        self.assertEqual(report.warnings, [])

    def test_wrong_count_or_type_is_left_out_with_a_warning(self):
        for translation in ("Hallo %1$s", "Hallo %1$s, %2$s", "Hallo"):
            strings, report = self.build_pair("Hello %1$s, %2$d new", translation)
            self.assertNotIn("de", strings["k"]["localizations"], translation)
            self.assertEqual(len(report.warnings), 1, translation)
            self.assertIn("de: k left out", report.warnings[0])

    def build_pair(self, english, german):
        return self.build('<string name="k">%s</string>' % english,
                          {"de": '<string name="k">%s</string>' % german})



class ConversionRuleTests(ConverterTestCase):
    def test_untranslatable_is_english_only_with_should_translate_false(self):
        strings, _ = self.build(
            '<string name="brand" translatable="false">Starwire</string>\n'
            '<string name="plain">Plain</string>',
            {"de": '<string name="brand">Sternendraht</string>\n'
                   '<string name="plain">Schlicht</string>'})
        self.assertIs(strings["brand"]["shouldTranslate"], False)
        self.assertEqual(list(strings["brand"]["localizations"]), ["en"])
        self.assertNotIn("shouldTranslate", strings["plain"])
        self.assertEqual(self.value(strings, "plain", "de"), "Schlicht")

    def test_entry_shape(self):
        strings, _ = self.build('<string name="a">A</string>')
        self.assertEqual(strings["a"], {
            "extractionState": "manual",
            "localizations": {"en": {"stringUnit": {"state": "translated", "value": "A"}}},
        })

    def test_plurals_keep_android_quantities(self):
        plural = ('<plurals name="files">'
                  '<item quantity="one">%d file</item>'
                  '<item quantity="other">%d files</item></plurals>')
        german = ('<plurals name="files">'
                  '<item quantity="one">%d Datei</item>'
                  '<item quantity="few">%d Dateien</item>'
                  '<item quantity="other">%d Dateien</item></plurals>')
        strings, _ = self.build(plural, {"de": german})
        en = strings["files"]["localizations"]["en"]["variations"]["plural"]
        self.assertEqual(set(en), {"one", "other"})
        self.assertEqual(en["one"]["stringUnit"], {"state": "translated", "value": "%d file"})
        de = strings["files"]["localizations"]["de"]["variations"]["plural"]
        self.assertEqual(set(de), {"one", "few", "other"})

    def test_plural_with_wrong_placeholders_is_left_out(self):
        plural = '<plurals name="files"><item quantity="other">%d files</item></plurals>'
        german = '<plurals name="files"><item quantity="other">%s Dateien</item></plurals>'
        strings, report = self.build(plural, {"de": german})
        self.assertNotIn("de", strings["files"]["localizations"])
        self.assertEqual(len(report.warnings), 1)

    def test_string_array_gets_one_key_per_item(self):
        strings, _ = self.build(
            '<string name="low">Low</string>\n<string name="high">High</string>\n'
            '<string-array name="levels"><item>@string/low</item><item>@string/high</item>'
            '<item>Literal</item></string-array>',
            {"de": '<string name="low">Niedrig</string>'})
        self.assertEqual(self.value(strings, "levels.0"), "Low")
        self.assertEqual(self.value(strings, "levels.1"), "High")
        self.assertEqual(self.value(strings, "levels.2"), "Literal")
        # the reference resolves in the same language; where that language has no such string,
        # the key has no entry for it and the app falls back to English
        self.assertEqual(self.value(strings, "levels.0", "de"), "Niedrig")
        self.assertNotIn("de", strings["levels.1"]["localizations"])
        self.assertNotIn("de", strings["levels.2"]["localizations"])

    def test_array_in_a_translation_is_matched_by_position(self):
        strings, _ = self.build(
            '<string-array name="a"><item>One</item><item>Two</item></string-array>',
            {"de": '<string-array name="a"><item>Eins</item><item>Zwei</item></string-array>'})
        self.assertEqual(self.value(strings, "a.1", "de"), "Zwei")

    def test_array_with_a_different_length_is_left_out(self):
        strings, report = self.build(
            '<string-array name="a"><item>One</item><item>Two</item></string-array>',
            {"de": '<string-array name="a"><item>Eins</item></string-array>'})
        self.assertNotIn("de", strings["a.0"]["localizations"])
        self.assertEqual(len(report.warnings), 1)

    def test_untranslatable_and_numeric_arrays_still_get_keys(self):
        strings, _ = self.build(
            '<string-array name="fps_values" translatable="false"><item>30</item>'
            '<item>60</item></string-array>\n'
            '<string-array name="names" translatable="false"><item>English</item></string-array>')
        self.assertEqual(self.value(strings, "fps_values.0"), "30")
        self.assertIs(strings["fps_values.1"]["shouldTranslate"], False)
        self.assertIs(strings["names.0"]["shouldTranslate"], False)

    def test_arrays_in_arrays_xml_are_read_too(self):
        strings, _ = self.build(
            '<string name="x">X</string>', {"de": '<string name="x">Y</string>'},
            extra={RES + "values/arrays.xml": resources(
                '<string-array name="names"><item>@string/x</item></string-array>')})
        self.assertEqual(self.value(strings, "names.0", "de"), "Y")

    def test_string_reference_resolves_in_the_same_language_then_english(self):
        strings, _ = self.build(
            '<string name="base">Base</string>\n<string name="only_en">Only English</string>\n'
            '<string name="a">@string/base</string>\n<string name="b">@string/only_en</string>',
            {"de": '<string name="base">Basis</string>\n'
                   '<string name="a">@string/base</string>\n'
                   '<string name="b">@string/only_en</string>'})
        self.assertEqual(self.value(strings, "a"), "Base")
        self.assertEqual(self.value(strings, "a", "de"), "Basis")
        # the translation only borrows English, so it is not a translation
        self.assertNotIn("de", strings["b"]["localizations"])

    def test_escaped_at_sign_is_not_a_reference(self):
        strings, _ = self.build('<string name="a">\\@string/base</string>')
        self.assertEqual(self.value(strings, "a"), "@string/base")

    def test_missing_reference_is_a_warning(self):
        strings, report = self.build('<string name="a">@string/nope</string>')
        self.assertNotIn("a", strings)
        self.assertEqual(len(report.warnings), 1)

    def test_empty_translations_are_skipped(self):
        strings, _ = self.build('<string name="a">A</string>\n<string name="b">B</string>',
                                {"de": '<string name="a"></string>\n<string name="b">""</string>'})
        self.assertEqual(list(strings["a"]["localizations"]), ["en"])
        self.assertEqual(list(strings["b"]["localizations"]), ["en"])

    def test_translation_with_no_english_key_is_skipped(self):
        strings, report = self.build('<string name="a">A</string>',
                                     {"de": '<string name="a">Aa</string>\n'
                                            '<string name="ghost">Geist</string>'})
        self.assertNotIn("ghost", strings)
        self.assertTrue(any("de: 1 translation" in n for n in report.notes))

    def test_unusable_folders_are_ignored(self):
        strings, report = self.build(
            '<string name="a">A</string>',
            {"night": '<string name="a">Dark</string>', "v31": '<string name="a">v31</string>',
             "land": '<string name="a">Land</string>', "sw600dp": '<string name="a">Tablet</string>',
             "w480dp-h520dp": '<string name="a">Wide</string>'},
            extra={RES + "values-fr/colors.xml": resources("")})
        self.assertEqual(list(strings["a"]["localizations"]), ["en"])
        self.assertEqual(report.mappings, [])

    def test_ios_only_strings_are_merged(self):
        strings, _ = self.build('<string name="a">A</string>',
                                ios='<string name="ios_only">Only on iPad</string>')
        self.assertEqual(self.value(strings, "ios_only"), "Only on iPad")

    def test_a_key_in_both_files_is_an_error(self):
        with self.assertRaises(conv.InputError) as caught:
            self.build('<string name="a">A</string>', ios='<string name="a">Again</string>')
        self.assertIn("a", str(caught.exception))

    def test_a_clash_with_an_array_key_is_an_error(self):
        with self.assertRaises(conv.InputError):
            self.build('<string-array name="x"><item>1</item></string-array>',
                       ios='<string name="x.0">Clash</string>')


class LocaleTests(unittest.TestCase):
    def test_folder_to_apple_locale(self):
        cases = {
            "values-de": "de",
            "values-pt-rBR": "pt-BR",
            "values-es-r419": "es-419",
            "values-zh-rCN": "zh-Hans",
            "values-zh-rTW": "zh-Hant",
            "values-zh-rHK": "zh-Hant",
            "values-in": "id",
            "values-iw": "he",
            "values-ji": "yi",
            "values-nb": "nb",
            "values-no": "nb",
            "values-nb-rNO": "nb",
            "values-b+sr+Latn": "sr-Latn",
            "values-b+es+419": "es-419",
            "values-in-rID": "id-ID",
        }
        for folder, want in cases.items():
            self.assertEqual(conv.folder_locale(folder), want, folder)

    def test_qualifier_folders_are_not_languages(self):
        for folder in ("values", "values-night", "values-v31", "values-land", "values-sw600dp",
                       "values-w480dp-h520dp", "values-xhdpi", "values-de-v21", "values-ldrtl"):
            self.assertIsNone(conv.folder_locale(folder), folder)


class LocaleCollisionTests(ConverterTestCase):
    def test_taiwan_wins_over_hong_kong_and_the_loser_is_reported(self):
        strings, report = self.build(
            '<string name="a">A</string>',
            {"zh-rHK": '<string name="a">Hong Kong</string>',
             "zh-rTW": '<string name="a">Taiwan</string>'})
        self.assertEqual(self.value(strings, "a", "zh-Hant"), "Taiwan")
        self.assertTrue(any("values-zh-rHK" in w and "left out" in w for w in report.warnings))

    def test_every_mapping_is_reported(self):
        _, report = self.build(
            '<string name="a">A</string>',
            {"in": '<string name="a">Satu</string>', "zh-rCN": '<string name="a">Yi</string>',
             "fa": ""})
        self.assertEqual(report.mappings, ["values-fa -> fa (no strings)",
                                           "values-in -> id", "values-zh-rCN -> zh-Hans"])


class OutputTests(ConverterTestCase):
    FILES = {RES + "values/strings.xml": resources(
        '<string name="b">B é</string>\n<string name="a">A</string>'),
             RES + "values-de/strings.xml": resources('<string name="a">Ä</string>')}

    def render(self, files=None):
        fixture = Fixture(files or self.FILES)
        self.addCleanup(fixture.close)
        catalog, _ = conv.build_catalog(fixture.root)
        return conv.render(catalog)

    def test_layout_is_what_xcode_writes(self):
        text = self.render()
        self.assertTrue(text.startswith('{\n  "sourceLanguage" : "en",\n  "strings" : {\n'
                                        '    "a" : {\n      "extractionState" : "manual",\n'))
        self.assertTrue(text.endswith('  },\n  "version" : "1.0"\n}\n'))
        self.assertLess(text.index('"a" : {'), text.index('"b" : {'))
        self.assertIn("B é", text)  # not escaped
        self.assertNotIn("\\u", text)
        self.assertNotIn("\r", text)

    def test_two_runs_give_the_same_bytes(self):
        self.assertEqual(self.render().encode("utf-8"), self.render().encode("utf-8"))

    def test_main_writes_the_catalog_and_the_ios_file(self):
        fixture = Fixture(self.FILES)
        self.addCleanup(fixture.close)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(conv.main(["--root", str(fixture.root)]), 0)
        self.assertTrue((fixture.root / conv.IOS_STRINGS).is_file())
        written = (fixture.root / conv.CATALOG).read_bytes()
        self.assertEqual(written, self.render().encode("utf-8"))

    def test_check_passes_after_a_write_and_fails_after_a_change(self):
        fixture = Fixture(self.FILES)
        self.addCleanup(fixture.close)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(conv.main(["--root", str(fixture.root)]), 0)
            self.assertEqual(conv.main(["--root", str(fixture.root), "--check"]), 0)
            (fixture.root / RES / "values-de/strings.xml").write_bytes(
                resources('<string name="a">Anders</string>').encode("utf-8"))
            self.assertEqual(conv.main(["--root", str(fixture.root), "--check"]), 1)
        self.assertIn("differs: a", out.getvalue())

    def test_check_writes_nothing(self):
        fixture = Fixture(self.FILES)
        self.addCleanup(fixture.close)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(conv.main(["--root", str(fixture.root), "--check"]), 1)
        self.assertFalse((fixture.root / conv.CATALOG).exists())
        self.assertFalse((fixture.root / conv.IOS_STRINGS).exists())

    def test_a_clash_exits_with_2(self):
        files = dict(self.FILES)
        files["ios/Strings/strings-ios.xml"] = resources('<string name="a">Again</string>')
        fixture = Fixture(files)
        self.addCleanup(fixture.close)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(conv.main(["--root", str(fixture.root)]), 2)


class CommittedCatalogTests(unittest.TestCase):
    def test_the_committed_catalog_is_current(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = conv.main(["--root", str(REPO_ROOT), "--check"])
        self.assertEqual(status, 0, out.getvalue())

    def test_the_ios_strings_file_exists(self):
        self.assertTrue((REPO_ROOT / conv.IOS_STRINGS).is_file())


if __name__ == "__main__":
    unittest.main()
