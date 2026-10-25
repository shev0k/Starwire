"""The test apps' covers: the same SVGs every time, and apps.json changed only in image-path.
Run from the repo root: python3 -m unittest discover -s ios/scripts/tests -v
"""

import sys
import unittest
from pathlib import Path, PureWindowsPath

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "covers"))
import install_covers  # noqa: E402
import make_covers  # noqa: E402


class CoversTest(unittest.TestCase):
    def test_each_cover_is_the_same_every_time_and_vibeshine_sized(self):
        for name in make_covers.COVERS:
            svg = make_covers.cover(name)
            self.assertEqual(svg, make_covers.cover(name))
            self.assertIn('viewBox="0 0 600 800"', svg)

    def test_only_the_test_apps_image_path_changes(self):
        apps = {"env": {}, "apps": [
            {"name": "Desktop", "image-path": "desktop.png"},
            {"name": "Starwire test pattern", "image-path": "desktop.png", "cmd": "x", "virtual-display-layout": "extended_isolated"},
            {"name": "Starwire colour bars", "image-path": "desktop.png"},
            {"name": "Starwire gamepad tester", "image-path": "desktop.png"},
        ]}
        folder = PureWindowsPath(r"C:\covers")
        after = install_covers.with_covers(apps, folder)
        self.assertEqual(install_covers.changed_fields(apps, after), [
            ("Starwire test pattern", "image-path"),
            ("Starwire colour bars", "image-path"),
            ("Starwire gamepad tester", "image-path"),
        ])
        self.assertEqual(after["apps"][1]["image-path"], r"C:\covers\starwire-test-pattern.png")
        self.assertEqual(after["apps"][1]["virtual-display-layout"], "extended_isolated")
        self.assertEqual(apps["apps"][1]["image-path"], "desktop.png", "the original is left alone")

    def test_any_other_change_is_seen(self):
        apps = {"apps": [{"name": "Desktop", "cmd": ""}]}
        self.assertEqual(install_covers.changed_fields(apps, {"apps": [{"name": "Desktop", "cmd": "y"}]}),
                         [("Desktop", "cmd")])
        self.assertEqual(install_covers.changed_fields(apps, {"apps": []}), [("*", "structure")])


if __name__ == "__main__":
    unittest.main()
