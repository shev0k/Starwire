"""Every string the iOS app asks for exists in the String Catalog.

The app looks strings up by name: L("name") in its Swift code, and the string names StarwireKit's
layouts, credits and game-screen texts give it. A name with no text would show the name itself
on screen, so this fails instead. Run from the repo root:
python3 -m unittest discover -s ios/scripts/tests -v
"""

import json
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
CATALOG = REPO_ROOT / "ios/Limelight/Starwire/Localizable.xcstrings"
APP = REPO_ROOT / "ios/Limelight"
KIT = REPO_ROOT / "ios/StarwireKit/Sources/StarwireKit"


class AppStringsTest(unittest.TestCase):
    def setUp(self):
        with open(CATALOG, encoding="utf-8") as f:
            self.catalog = json.load(f)["strings"]

    def test_every_L_name_in_the_app_is_in_the_catalog(self):
        missing = []
        for path in sorted(APP.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            for name in re.findall(r'\bL\("([A-Za-z0-9_.]+)"', text):
                if name not in self.catalog:
                    missing.append("%s: %s" % (path.relative_to(REPO_ROOT), name))
        self.assertEqual(missing, [])

    def test_every_text_name_in_the_game_screen_enums_is_in_the_catalog(self):
        missing = []
        for path in sorted((KIT / "GameScreen").glob("*.swift")):
            text = path.read_text(encoding="utf-8")
            for enum in re.findall(r"public enum \w+Text: String[^{]*\{(.*?)\n\}", text, re.S):
                for name in re.findall(r'case \w+ = "([a-z0-9_]+)"', enum):
                    if name not in self.catalog:
                        missing.append(name)
        self.assertEqual(missing, [])

    def test_every_credit_is_in_the_catalog(self):
        text = (KIT / "Settings/SettingsCredits.swift").read_text(encoding="utf-8")
        names = re.findall(r'"((?:ios_)?credit_[a-z0-9_]+|credits_section_[a-z_]+)"', text)
        self.assertTrue(names)
        self.assertEqual([n for n in names if n not in self.catalog], [])

    def test_the_microphone_failures_are_in_the_catalog(self):
        text = (APP / "Starwire/UI/MicPairingScreen.swift").read_text(encoding="utf-8")
        names = re.findall(r'return "(ios_mic_[a-z_]+)"', text)
        self.assertEqual(len(names), 7)
        self.assertEqual([n for n in names if n not in self.catalog], [])


if __name__ == "__main__":
    unittest.main()
