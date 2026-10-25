"""The test apps' covers: the same SVGs every time, and apps.json changed only in image-path.
Run from the repo root: python3 -m unittest discover -s ios/scripts/tests -v
"""

import sys
import unittest
from pathlib import Path, PureWindowsPath

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "covers"))
import install_covers  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import install_latency_app  # noqa: E402
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


class LatencyAppTest(unittest.TestCase):
    def test_the_app_is_a_copy_of_the_colour_bars_with_the_latency_page(self):
        apps = {"apps": [
            {"name": "Desktop"},
            {"name": "Starwire colour bars", "cmd": "x -Url colour", "virtual-display-layout": "extended_isolated",
             "uuid": "abc"},
        ]}
        folder = Path("C:/StarwireTestPattern")
        after = install_latency_app.with_latency_app(apps, folder)
        self.assertEqual(after["apps"][:2], apps["apps"], "the other apps stay as they were")
        app = after["apps"][2]
        self.assertEqual(app["name"], "Starwire input latency")
        self.assertEqual(app["virtual-display-layout"], "extended_isolated")
        self.assertIn("input-latency.html", app["cmd"])
        self.assertNotIn("uuid", app)
        self.assertEqual(install_latency_app.with_latency_app(after, folder), after, "added once only")


if __name__ == "__main__":
    unittest.main()
