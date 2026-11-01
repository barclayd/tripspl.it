import argparse
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("tripsplit_release", Path(__file__).resolve().parents[1] / "testflight.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

CONFIG = {"app_id": "123", "bundle_id": "example.app", "group_id": "internal", "team_id": "TEAM",
          "api_profile": "test", "project_candidates": ["App.xcodeproj"], "scheme": "App", "test_destination": "simulator"}


class ReleaseTests(unittest.TestCase):
    def setup_root(self, root):
        (root / "ios").mkdir()
        (root / "App.xcodeproj").mkdir()
        (root / "ios/testflight.json").write_text(json.dumps(CONFIG))

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
                     patch.object(release, "identity", return_value=("profile", "certificate")), \
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

            with patch.object(release, "ROOT", root), patch.object(release, "identity", return_value=("profile", "certificate")), \
                 patch.object(release, "run", side_effect=run), patch.object(sys, "argv", ["testflight.py", "release", "--dry-run"]):
                self.assertEqual(release.main(), 0)
            self.assertFalse(any(c[0] == "xcodebuild" or "unlock" in c or "upload" in c for c in commands))


if __name__ == "__main__":
    unittest.main()
