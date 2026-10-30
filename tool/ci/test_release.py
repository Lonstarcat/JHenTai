"""CI helper tests use synthetic credentials and disposable temporary folders."""
from __future__ import annotations

import base64
import os
from pathlib import Path
import plistlib
import re
import tempfile
import unittest
from unittest.mock import patch

import release


class ReleaseTests(unittest.TestCase):
    def test_version(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "pubspec.yaml").write_text("version: 8.0.18+341\n", encoding="utf-8")
            self.assertEqual(release.version(root), "8.0.18+341e")
            (root / "pubspec.yaml").write_text("version: unsafe/name\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                release.version(root)

    def test_signing_rejects_missing_invalid_or_empty_base64(self) -> None:
        for data in ("", "not-base64!!", base64.b64encode(b"small").decode()):
            with self.assertRaises(ValueError):
                release.signing_payload(data, "storePassword=test", Path("/tmp/test.p12"))

    def test_signing_preserves_password_escaping_and_replaces_only_path(self) -> None:
        key = b"synthetic-not-a-real-keystore" * 8
        encoded = base64.b64encode(key).decode()
        properties = "\ufeffstorePassword=test\\=value\r\nkeyPassword=test\r\nkeyAlias=upload\r\nstoreType=PKCS12\r\nstoreFile=old.p12\r\n"
        decoded, output = release.signing_payload(encoded[:30] + "\n" + encoded[30:], properties, Path("/tmp/test.p12"))
        self.assertEqual(decoded, key)
        self.assertIn("storePassword=test\\=value\n", output)
        self.assertIn("storeType=PKCS12\n", output)
        self.assertIn("storeFile=/tmp/test.p12\n", output)
        self.assertNotIn("old.p12", output)
        self.assertEqual(output.count("storeFile="), 1)

    def test_missing_signing_fields(self) -> None:
        encoded = base64.b64encode(b"test" * 64).decode()
        for missing in ("storePassword", "keyPassword", "keyAlias"):
            fields = "\n".join(f"{key}=test" for key in ("storePassword", "keyPassword", "keyAlias") if key != missing)
            with self.assertRaises(ValueError):
                release.signing_payload(encoded, fields, Path("/tmp/test.p12"))

    def test_packaging_is_release_only_and_has_no_repository_push(self) -> None:
        workflow = (release.ROOT / ".github/workflows/build_android_macos_test.yml").read_text(encoding="utf-8")
        self.assertNotIn("git push", workflow)
        self.assertNotIn("release-action", workflow)
        self.assertNotIn("--debug", workflow)
        self.assertNotIn("--profile", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("--no-codesign", workflow)
        self.assertIn("ubuntu-22.04-arm", workflow)
        self.assertIn("build/windows/release-package/**", workflow)
        self.assertNotIn("path: build/**", workflow)

    def test_missing_apk_fails_instead_of_publishing_partial_set(self) -> None:
        with tempfile.TemporaryDirectory() as temp, patch.object(release, "ROOT", Path(temp)):
            with self.assertRaises(ValueError):
                release.package_android()

    def test_push_builds_only_remaining_platforms(self) -> None:
        workflow = (release.ROOT / ".github/workflows/build_android_macos_test.yml").read_text(encoding="utf-8")
        self.assertIn("default: windows-linux", workflow)
        self.assertIn("branches:\n      - feature/enhanced", workflow)
        guard = "    if: github.event_name == 'workflow_dispatch' && inputs.targets == 'all'"
        for job in ("android", "apple"):
            section = re.search(rf"^  {job}:\n(.*?)(?=^  \w+:|\Z)", workflow, re.M | re.S)[1]
            self.assertIn(guard + "\n", section)
        for job in ("windows", "linux"):
            section = re.search(rf"^  {job}:\n(.*?)(?=^  \w+:|\Z)", workflow, re.M | re.S)[1]
            self.assertIsNone(re.search(r"^    if:", section, re.M))
        # Exact guarded expression above: a push or remaining-only dispatch must
        # never schedule Apple/Android; explicit all-platform dispatch must.
        for event, targets, expected in (("push", "", False),
                                         ("workflow_dispatch", "windows-linux", False),
                                         ("workflow_dispatch", "all", True)):
            self.assertEqual(event == "workflow_dispatch" and targets == "all", expected)

    def test_signing_writes_private_files_and_refuses_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "android").mkdir()
            runner = root / "runner-temp"
            runner.mkdir()
            with patch.object(release, "ROOT", root), patch.dict(os.environ, {
                "RUNNER_TEMP": str(runner),
                "KEYSTORE_BASE64": base64.b64encode(b"synthetic" * 64).decode(),
                "KEY_PROPERTIES": "storePassword=test\nkeyPassword=test\nkeyAlias=upload\nstoreType=PKCS12\n",
            }):
                release.restore_signing()
                for target in release.signing_paths():
                    self.assertEqual(target.stat().st_mode & 0o777, 0o600)
                with self.assertRaises(ValueError):
                    release.restore_signing()

    def test_apk_output_allowlist_and_names(self) -> None:
        with tempfile.TemporaryDirectory() as temp, patch.object(release, "ROOT", Path(temp)):
            root = Path(temp)
            (root / "pubspec.yaml").write_text("version: 8.0.18+341\n", encoding="utf-8")
            apks = root / "build/app/outputs/flutter-apk"
            apks.mkdir(parents=True)
            for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
                (apks / f"app-{abi}-release.apk").write_bytes(b"synthetic APK")
            (apks / "key.properties").write_text("synthetic", encoding="utf-8")
            release.package_android()
            self.assertEqual({p.name for p in release.output_dir().iterdir()}, {
                "JHenTai-8.0.18+341e-armeabi-v7a.apk", "JHenTai-8.0.18+341e-arm64-v8a.apk",
                "JHenTai-8.0.18+341e-x64.apk",
            })

    def test_apple_identity_and_version_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Runner.app"
            app.mkdir()
            info = {"CFBundleIdentifier": release.IDENTITY,
                    "CFBundleShortVersionString": "8.0.18", "MinimumOSVersion": "15.0"}
            with patch.object(release, "version", return_value="8.0.18+341e"):
                (app / "Info.plist").write_bytes(plistlib.dumps(info))
                self.assertEqual(release.verify_plist(app, "MinimumOSVersion"), info)
                info["CFBundleIdentifier"] = "invalid.test"
                (app / "Info.plist").write_bytes(plistlib.dumps(info))
                with self.assertRaises(ValueError):
                    release.verify_plist(app, "MinimumOSVersion")


if __name__ == "__main__":
    unittest.main()
