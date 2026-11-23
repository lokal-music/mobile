"""Native widget and notification localization invariants.

Runs in Android CI's existing `python -m unittest discover -s tool -p
'ci_*_test.py'` step, without requiring an emulator.
"""
from __future__ import annotations

import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "android/app/src/main/res"
ANDROID = "{http://schemas.android.com/apk/res/android}"


def resource_names(path: Path) -> set[str]:
    document = ET.parse(path)
    values = document.getroot()
    return {
        node.attrib["name"]
        for node in values.findall("string")
    }


class NativeTurkishLocalizationTest(unittest.TestCase):
    def test_widget_resource_keys_have_complete_turkish_parity(self):
        english = resource_names(RESOURCES / "values/widget_strings.xml")
        turkish = resource_names(RESOURCES / "values-tr/widget_strings.xml")
        self.assertEqual(turkish, english)
        self.assertGreaterEqual(len(english), 50)

    def test_widget_resource_keys_have_complete_russian_parity(self):
        english = resource_names(RESOURCES / "values/widget_strings.xml")
        russian = resource_names(RESOURCES / "values-ru/widget_strings.xml")
        self.assertEqual(russian, english)
        self.assertGreaterEqual(len(english), 50)

    def test_widget_layouts_do_not_embed_english_labels(self):
        # Brand names and glyph-only transport arrows are intentionally fixed.
        allowed_literals = {"Lokal", "‹", "›"}
        for path in (RESOURCES / "layout").glob("widget_*.xml"):
            root = ET.parse(path).getroot()
            for element in root.iter():
                text = element.attrib.get(ANDROID + "text")
                if not text or text.startswith("@string/") or text in allowed_literals:
                    continue
                self.fail(f"{path.name}: untranslated android:text={text!r}")

    def test_notification_channel_uses_service_context_for_localized_description(self):
        # Kotlin's receiver inside NotificationChannel.apply is a
        # NotificationChannel, not an Android Context. This previously broke
        # :app:compileFullReleaseKotlin in release run 40266183722.
        source = (
            ROOT / "android/app/src/main/kotlin/com/mossapps/flick/MusicNotificationService.kt"
        ).read_text(encoding="utf-8")
        channel_setup = source.split("private fun createNotificationChannel()", 1)[1]
        channel_setup = channel_setup.split("private fun setupMediaSession()", 1)[0]
        self.assertIn(
            "description = WidgetPrefs.localizedText(this@MusicNotificationService,",
            channel_setup,
        )

    def test_native_runtime_resource_references_exist(self):
        names = resource_names(RESOURCES / "values/widget_strings.xml")
        native_dir = ROOT / "android/app/src/main/kotlin/com/mossapps/flick"
        referenced = set()
        for path in native_dir.rglob("*.kt"):
            source = path.read_text(encoding="utf-8")
            referenced.update(
                re.findall(r"R\.string\.((?:widget|native)_\w+)", source)
            )
        self.assertFalse(referenced - names, f"Unknown resource IDs: {referenced - names}")


if __name__ == "__main__":
    unittest.main()
