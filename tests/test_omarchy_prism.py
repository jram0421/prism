"""Unit tests for bin/omarchy-prism. No hardware, OpenRGB or systemd needed.

Run from the repository root:  python3 -m unittest discover -s tests -v
"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "bin" / "omarchy-prism"


def load_module():
    loader = importlib.machinery.SourceFileLoader("omarchy_prism", str(SCRIPT))
    spec = importlib.util.spec_from_loader("omarchy_prism", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


prism = load_module()


class IsolatedConfig(unittest.TestCase):
    """Point every path at a temp dir and stub out the system probes."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        tmp = Path(self.tmp.name)
        self.saved = {}
        for name, value in {
            "CONFIG_DIR": tmp / "config",
            "CONFIG_FILE": tmp / "config" / "config.json",
            "STATE_DIR": tmp / "state",
            "RUNTIME_FILE": tmp / "state" / "runtime.json",
            "THEME_COLORS": tmp / "colors.toml",
            "service_state": lambda unit: "active",
        }.items():
            self.saved[name] = getattr(prism, name)
            setattr(prism, name, value)
        self.addCleanup(self.restore)

    def restore(self):
        for name, value in self.saved.items():
            setattr(prism, name, value)

    def cli(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = prism.main(list(args))
            except SystemExit as e:  # argparse errors
                code = e.code
        return code, out.getvalue(), err.getvalue()

    def write_runtime(self, devices):
        prism.write_atomic(prism.RUNTIME_FILE, json.dumps({"connected": True, "devices": devices}))


class ParsingTests(unittest.TestCase):
    def test_hex_forms(self):
        self.assertEqual(prism.normalize_hex("#FF2A9D"), "ff2a9d")
        self.assertEqual(prism.normalize_hex("f00"), "ff0000")
        self.assertEqual(prism.normalize_hex("Pink"), "ff2a9d")

    def test_hex_rejects_garbage(self):
        for bad in ("", "gg0000", "12345", "#1234567", "nope"):
            with self.assertRaises(prism.UserError):
                prism.normalize_hex(bad)

    def test_mode_is_case_and_separator_insensitive(self):
        self.assertEqual(prism.normalize_mode("spectrum-cycle"), "Spectrum Cycle")
        self.assertEqual(prism.normalize_mode("RAINBOW"), "Rainbow")
        with self.assertRaises(prism.UserError):
            prism.normalize_mode("disco")

    def test_sanitize_drops_invalid_values(self):
        cfg = prism.sanitize({"brightness": 900, "speed": "fast", "mode": "x", "color": "zz",
                             "power": "yes", "zones": {"a": 5, "b": -1, "c": True}})
        self.assertEqual(cfg["brightness"], 100)
        self.assertEqual(cfg["speed"], 50)
        self.assertEqual(cfg["mode"], "Static")
        self.assertEqual(cfg["color"], "ffffff")
        self.assertIs(cfg["power"], True)
        self.assertEqual(cfg["zones"], {"a": 5})

    def test_sanitize_non_dict(self):
        self.assertEqual(prism.sanitize(["nonsense"]), prism.DEFAULTS)


class EffectTests(unittest.TestCase):
    def test_speed_factor_anchor_points(self):
        self.assertAlmostEqual(prism.speed_factor(50), 1.0)
        self.assertAlmostEqual(prism.speed_factor(0), 0.25)
        self.assertAlmostEqual(prism.speed_factor(100), 4.0)

    def test_static_returns_color(self):
        self.assertEqual(prism.frame("Static", 3.0, 0, 10, (1, 2, 3)), (1, 2, 3))

    def test_flashing_is_all_or_nothing_and_synced(self):
        on = [prism.frame("Flashing", 0.0, p, 40, (255, 0, 0)) for p in range(40)]
        off = [prism.frame("Flashing", 0.3, p, 40, (255, 0, 0)) for p in range(40)]
        self.assertEqual(set(on), {(255, 0, 0)})
        self.assertEqual(set(off), {(0, 0, 0)})

    def test_spectrum_cycle_is_uniform_across_leds(self):
        colors = {prism.frame("Spectrum Cycle", 5.0, p, 40, (0, 0, 0)) for p in range(40)}
        self.assertEqual(len(colors), 1)

    def test_rainbow_varies_along_the_chain(self):
        colors = {prism.frame("Rainbow", 1.0, p, 40, (0, 0, 0)) for p in range(40)}
        self.assertGreater(len(colors), 20)

    def test_breathing_and_wave_never_exceed_base_color(self):
        for mode in ("Breathing", "Wave"):
            for t in (0.0, 0.7, 1.9, 4.2):
                r, g, b = prism.frame(mode, t, 3, 40, (200, 100, 50))
                self.assertLessEqual((r, g, b), (200, 100, 50))
                self.assertGreaterEqual(min(r, g, b), 0)


class ConfigTests(IsolatedConfig):
    def test_missing_config_gives_defaults(self):
        self.assertEqual(prism.load_config(), prism.DEFAULTS)

    def test_update_roundtrip_and_sanitizes(self):
        prism.update_config(lambda c: c.update(brightness=250, color="00ff40"))
        cfg = prism.load_config()
        self.assertEqual(cfg["brightness"], 100)
        self.assertEqual(cfg["color"], "00ff40")

    def test_corrupt_config_falls_back(self):
        prism.write_atomic(prism.CONFIG_FILE, "{not json")
        self.assertEqual(prism.load_config(), prism.DEFAULTS)

    def test_theme_accent(self):
        prism.THEME_COLORS.write_text('mode = "dark"\naccent = "#587ea8"\nselection = "#132143"\n')
        self.assertEqual(prism.theme_accent(), prism.boost_contrast("587ea8"))

    def test_boost_contrast_raises_saturation_and_value_without_shifting_hue(self):
        import colorsys
        hsv = lambda x: colorsys.rgb_to_hsv(*(int(x[i:i + 2], 16) / 255 for i in (0, 2, 4)))
        h0, s0, v0 = hsv("f38d70")
        h1, s1, v1 = hsv(prism.boost_contrast("f38d70"))
        self.assertAlmostEqual(h0, h1, places=2)  # red-orange is outside the green-cyan correction
        self.assertAlmostEqual(s1, min(1.0, s0 * prism.ACCENT_CONTRAST), places=2)
        self.assertGreaterEqual(v1, v0)

    def test_led_hue_pulls_greens_toward_pure_green_but_leaves_blues(self):
        self.assertEqual(prism.led_hue(120 / 360), 120 / 360)   # pure green untouched
        self.assertEqual(prism.led_hue(0.0), 0.0)               # red untouched
        self.assertEqual(prism.led_hue(240 / 360), 240 / 360)   # blue untouched
        for deg in (140, 153, 180, 200):
            shifted = prism.led_hue(deg / 360) * 360
            self.assertLess(shifted, deg)
            self.assertGreaterEqual(shifted, 120)

    def test_led_hue_is_continuous_and_monotonic(self):
        values = [prism.led_hue(d / 360) * 360 for d in range(0, 361)]
        self.assertTrue(all(b >= a for a, b in zip(values, values[1:])))
        self.assertTrue(all(b - a < 2.0 for a, b in zip(values, values[1:])))

    def test_teal_green_accent_is_not_left_blue(self):
        import colorsys
        r, g, b = (int(prism.boost_contrast("509475")[i:i + 2], 16) / 255 for i in (0, 2, 4))
        hue = colorsys.rgb_to_hsv(r, g, b)[0] * 360
        self.assertLess(hue, 140)
        self.assertGreater(g, b)

    def test_boost_contrast_caps_and_keeps_black_and_white(self):
        self.assertEqual(prism.boost_contrast("ff0000"), "ff0000")
        self.assertEqual(prism.boost_contrast("000000"), "000000")
        self.assertEqual(prism.boost_contrast("ffffff"), "ffffff")

    def test_theme_accent_missing(self):
        self.assertEqual(prism.theme_accent(), "")


class CliTests(IsolatedConfig):
    def test_color_sets_power_and_leaves_self_colored_modes(self):
        prism.update_config(lambda c: c.update(mode="Rainbow", power=False))
        self.assertEqual(self.cli("color", "ff0000")[0], 0)
        cfg = prism.load_config()
        self.assertEqual((cfg["color"], cfg["mode"], cfg["power"]), ("ff0000", "Static", True))

    def test_color_keeps_color_based_effects(self):
        prism.update_config(lambda c: c.update(mode="Breathing"))
        self.cli("color", "00ff40")
        self.assertEqual(prism.load_config()["mode"], "Breathing")

    def test_color_theme(self):
        prism.THEME_COLORS.write_text('accent = "#112233"\n')
        self.cli("color", "theme")
        self.assertEqual(prism.load_config()["color"], prism.boost_contrast("112233"))

    def test_color_theme_without_theme_fails(self):
        code, _, err = self.cli("color", "theme")
        self.assertEqual(code, 1)
        self.assertIn("accent", err)

    def test_invalid_input_is_reported_not_raised(self):
        for args in (("color", "nope"), ("mode", "disco"), ("brightness", "101"), ("speed", "-1"), ("brightness", "abc")):
            code, _, err = self.cli(*args)
            self.assertEqual(code, 1, args)
            self.assertTrue(err.startswith("omarchy-prism:"), args)

    def test_brightness_raises_power_but_zero_does_not(self):
        prism.update_config(lambda c: c.update(power=False))
        self.cli("brightness", "0")
        self.assertFalse(prism.load_config()["power"])
        self.cli("brightness", "40")
        cfg = prism.load_config()
        self.assertEqual((cfg["brightness"], cfg["power"]), (40, True))

    def test_toggle(self):
        self.cli("toggle")
        self.assertFalse(prism.load_config()["power"])
        self.cli("toggle")
        self.assertTrue(prism.load_config()["power"])

    def test_auto_off(self):
        self.cli("auto-off", "lock", "on")
        self.assertEqual(prism.load_config()["auto_off"], {"lock": True, "screensaver": False})

    def test_follow_adopts_accent_immediately(self):
        prism.THEME_COLORS.write_text('accent = "#abcdef"\n')
        self.cli("follow", "on")
        cfg = prism.load_config()
        self.assertTrue(cfg["follow_theme"])
        self.assertEqual(cfg["color"], prism.boost_contrast("abcdef"))

    def test_theme_hook_respects_follow_flag_and_ignores_theme_name_arg(self):
        prism.THEME_COLORS.write_text('accent = "#010203"\n')
        self.cli("theme-hook", "gruvbox")
        self.assertEqual(prism.load_config()["color"], "ffffff")
        prism.update_config(lambda c: c.update(follow_theme=True))
        self.assertEqual(self.cli("theme-hook", "gruvbox")[0], 0)
        self.assertEqual(prism.load_config()["color"], prism.boost_contrast("010203"))

    def test_unknown_extra_args_rejected_for_normal_commands(self):
        self.assertNotEqual(self.cli("status", "bogus")[0], 0)

    def test_status_json(self):
        code, out, _ = self.cli("status", "--json")
        data = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(data["config"]["mode"], "Static")
        self.assertIn("Rainbow", data["modes"])


class ZoneTests(IsolatedConfig):
    DEVICES = [
        {"name": "ENE DRAM", "zones": [{"key": "ENE DRAM/DRAM", "name": "DRAM", "leds": 8, "min": 8, "max": 8, "resizable": False}]},
        {"name": "Board", "zones": [
            {"key": "Board/Header 1", "name": "Header 1", "leds": 0, "min": 0, "max": 500, "resizable": True},
            {"key": "Board/Header 2", "name": "Header 2", "leds": 0, "min": 0, "max": 500, "resizable": True},
        ]},
    ]

    def test_zone_by_substring_and_clamp(self):
        self.write_runtime(self.DEVICES)
        self.assertEqual(self.cli("zone", "header 1", "24")[0], 0)
        self.assertEqual(prism.load_config()["zones"], {"Board/Header 1": 24})
        self.cli("zone", "header 2", "9999")
        self.assertEqual(prism.load_config()["zones"]["Board/Header 2"], 500)

    def test_zone_ambiguous_unknown_and_fixed_size(self):
        self.write_runtime(self.DEVICES)
        for query, fragment in (("header", "ambiguous"), ("nothing", "no resizable"), ("dram", "no resizable")):
            code, _, err = self.cli("zone", query, "10")
            self.assertEqual(code, 1, query)
            self.assertIn(fragment, err)

    def test_zone_rejects_non_numeric(self):
        self.write_runtime(self.DEVICES)
        self.assertEqual(self.cli("zone", "header 1", "lots")[0], 1)

    def test_devices_listing(self):
        self.write_runtime(self.DEVICES)
        _, out, _ = self.cli("devices")
        self.assertIn("resizable 0-500", out)


class DoctorTests(IsolatedConfig):
    def test_doctor_shape_and_exit_code(self):
        checks = prism.doctor_checks()
        self.assertTrue(checks)
        for c in checks:
            self.assertIn(c["status"], ("ok", "warn", "fail"))
            self.assertEqual(set(c), {"name", "status", "detail", "fix"})
        code, out, _ = self.cli("doctor", "--json")
        self.assertEqual(code, 1 if any(c["status"] == "fail" for c in json.loads(out)) else 0)


class RepoTests(unittest.TestCase):
    def test_manifest_matches_script_version(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        self.assertEqual(manifest["version"], prism.VERSION)
        self.assertEqual(manifest["entryPoints"]["barWidget"], "Panel.qml")
        self.assertTrue((ROOT / manifest["entryPoints"]["barWidget"]).exists())

    def test_modes_in_panel_match_script(self):
        panel = (ROOT / "Panel.qml").read_text()
        for mode in prism.MODES:
            self.assertIn(f'"{mode}"', panel)

    def test_panel_has_no_machine_specific_paths(self):
        for path in (ROOT / "Panel.qml", SCRIPT):
            self.assertNotIn("/home/", path.read_text(), path.name)


if __name__ == "__main__":
    unittest.main()
