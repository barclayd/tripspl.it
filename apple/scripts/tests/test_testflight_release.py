import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("tripsplit_release", Path(__file__).resolve().parents[1] / "testflight.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

CONFIG = {"app_id": "123", "bundle_id": "example.app", "group_id": "internal", "team_id": "TEAM",
          "api_profile": "test", "project_candidates": ["App.xcodeproj"], "scheme": "App", "test_destination": "simulator",
          "targets": {"App": {"bundle_id": "example.app", "profile": "App.mobileprovision"},
                      "Watch": {"bundle_id": "example.app.watchkitapp", "profile": "Watch.mobileprovision"}}}
PROFILES = {"App": "app-profile", "Watch": "watch-profile"}


def bundle(path, identifier):
    path.mkdir(parents=True)
    (path / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}, fmt=plistlib.FMT_BINARY))


class ReleaseTests(unittest.TestCase):
    def setup_root(self, root):
        (root / "apple/ios").mkdir(parents=True)
        (root / "App.xcodeproj").mkdir()
        (root / "apple/ios/testflight.json").write_text(json.dumps(CONFIG))

    def test_receipt_for_another_group_never_reaches_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.setup_root(root)
            receipt = root / "receipt.json"
            receipt.write_text(json.dumps({**CONFIG, "group_id": "external"}))
            with patch.object(release, "ROOT", root), patch.object(release, "run") as run, \
                 patch.object(sys, "argv", ["testflight.py", "resume", "--receipt", str(receipt)]):
                with self.assertRaises(RuntimeError): release.main()
                run.assert_not_called()

    def test_failed_tests_or_changed_source_prevent_archive_and_upload(self):
        for failure in ("tests", "source"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self.setup_root(root)
                commands = []
                revisions = iter(["a" * 40, "b" * 40])

                def run(argv, **kwargs):
                    commands.append(argv)
                    if argv[:3] == ["git", "rev-parse", "HEAD"]: return next(revisions), 0
                    if argv[:2] == ["git", "status"]: return "", 0
                    if argv[0] == "xcodebuild" and failure == "tests": raise RuntimeError("tests failed")
                    return "{}", 0

                with patch.object(release, "ROOT", root), patch.object(Path, "home", return_value=root), \
                     patch.object(release, "identity", return_value=(PROFILES, "certificate")), \
                     patch.object(release, "run", side_effect=run), patch.object(sys, "argv", ["testflight.py", "release"]):
                    with self.assertRaises(RuntimeError): release.main()
                self.assertFalse(any("archive" in c or "upload" in c or "next-build-number" in c for c in commands))

    def test_dry_run_cannot_test_unlock_or_upload(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.setup_root(root)
            commands = []

            def run(argv, **kwargs):
                commands.append(argv)
                if argv[:3] == ["git", "rev-parse", "HEAD"]: return "a" * 40, 0
                if argv[:2] == ["git", "status"]: return "", 0
                return "{}", 0

            with patch.object(release, "ROOT", root), patch.object(release, "identity", return_value=(PROFILES, "certificate")), \
                 patch.object(release, "run", side_effect=run), patch.object(sys, "argv", ["testflight.py", "release", "--dry-run"]):
                self.assertEqual(release.main(), 0)
            self.assertFalse(any(c[0] == "xcodebuild" or "unlock" in c or "upload" in c for c in commands))

    def release(self, root, embedded, commands):
        """Runs a release whose archive embeds the given bundles, recording the commands it runs."""
        def run(argv, **kwargs):
            commands.append(argv)
            if argv[:3] == ["git", "rev-parse", "HEAD"]: return "a" * 40, 0
            if argv[:2] == ["git", "status"]: return "", 0
            if "next-build-number" in argv: return json.dumps({"nextBuildNumber": 8}), 0
            if argv[-1] == "archive":
                app = Path(argv[argv.index("-archivePath") + 1]) / "Products/Applications/App.app"
                bundle(app, "example.app")
                bundle(app / "Frameworks/Kit.framework", "example.kit")
                for path, identifier in embedded: bundle(app / path, identifier)
            if "-exportArchive" in argv:
                export = Path(argv[argv.index("-exportPath") + 1])
                export.mkdir()
                (export / "App.ipa").write_bytes(b"ipa")
            return "{}", 0

        with patch.object(release, "ROOT", root), patch.object(Path, "home", return_value=root), \
             patch.object(release, "identity", return_value=(PROFILES, "certificate")), \
             patch.object(release, "run", side_effect=run), patch.object(sys, "argv", ["testflight.py", "release"]):
            release.main()

    def test_signs_each_target_with_its_own_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.setup_root(root)
            commands = []
            self.release(root, [("Watch/Watch.app", "example.app.watchkitapp")], commands)
            archive = next(c for c in commands if c[-1] == "archive")
            self.assertIn("PROVISIONING_PROFILE_SPECIFIER=$(TRIPSPLIT_PROFILE_$(TARGET_NAME))", archive)
            self.assertIn("TRIPSPLIT_PROFILE_App=app-profile", archive)
            self.assertIn("TRIPSPLIT_PROFILE_Watch=watch-profile", archive)
            options = plistlib.loads(next(root.glob(".local/state/testflight/tripsplit/*/ExportOptions.plist")).read_bytes())
            self.assertEqual(options["provisioningProfiles"], {"example.app": "app-profile", "example.app.watchkitapp": "watch-profile"})
            self.assertTrue(any("upload" in c for c in commands))

    def test_archive_without_every_target_is_never_exported(self):
        for embedded in ([], [("Watch/Watch.app", "example.app.watchkitapp"), ("PlugIns/Share.appex", "example.app.share")]):
            with self.subTest(embedded=embedded), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self.setup_root(root)
                commands = []
                with self.assertRaises(RuntimeError): self.release(root, embedded, commands)
                self.assertTrue(any(c[-1] == "archive" for c in commands))
                self.assertFalse(any("-exportArchive" in c or "upload" in c for c in commands))


if __name__ == "__main__":
    unittest.main()
