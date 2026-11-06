import contextlib
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('tripsplit_release', Path(__file__).resolve().parents[1] / 'testflight.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

CONFIG = {'app_id': '123', 'bundle_id': 'example.app', 'group_id': 'internal', 'team_id': 'TEAM',
          'api_profile': 'test-profile', 'project_candidates': ['App.xcodeproj'], 'scheme': 'App', 'test_destination': 'simulator',
          'targets': {'App': {'bundle_id': 'example.app', 'profile': 'App.mobileprovision'},
                      'Watch': {'bundle_id': 'example.app.watchkitapp', 'profile': 'Watch.mobileprovision'}}}
PROFILES = {'App': 'app-profile', 'Watch': 'watch-profile'}
SHA = 'a' * 40


def bundle(path, identifier):
    path.mkdir(parents=True)
    (path / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier}, fmt=plistlib.FMT_BINARY))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'apple/ios').mkdir(parents=True)
        (self.root / 'App.xcodeproj').mkdir()
        (self.root / 'apple/ios/testflight.json').write_text(json.dumps(CONFIG))
        self.commands = []
        self.head = SHA
        self.dirty = ''
        self.toolchain = 'Xcode test'
        self.failure = None
        self.number = 8
        self.change_after = None
        self.embedded = [('Watch/Watch.app', 'example.app.watchkitapp')]
        self.receipt_on_failure = False
        for target, replacement in [('ROOT', self.root), ('identity', lambda *args: (PROFILES, 'certificate')), ('run', self.run_command)]:
            patcher = patch.object(release, target, replacement)
            patcher.start()
            self.addCleanup(patcher.stop)
        home = patch.object(Path, 'home', return_value=self.root)
        home.start()
        self.addCleanup(home.stop)

    def invoke(self, *args):
        with patch.object(sys, 'argv', ['testflight.py', *args]), contextlib.redirect_stdout(io.StringIO()):
            return release.main()

    @property
    def checkpoint(self):
        return next(self.root.glob('.local/state/testflight/tripsplit/*/build.json'))

    @property
    def state(self):
        return json.loads(self.checkpoint.read_text())

    def assert_no(self, *words):
        self.assertFalse(any(any(word in c for word in words) for c in self.commands), self.commands)

    def run_command(self, argv, **kwargs):
        self.commands.append(argv)
        log = kwargs.get('log')
        if log:
            log.write_text('successful command log')
        if argv[:3] == ['git', 'rev-parse', 'HEAD']:
            return self.head, 0
        if argv[:2] == ['git', 'status']:
            return self.dirty, 0
        if argv == ['xcodebuild', '-version']:
            return self.toolchain, 0
        if 'next-build-number' in argv:
            return json.dumps({'nextBuildNumber': self.number}), 0
        stage = None
        if argv[0] == 'xcodebuild' and argv[-1] == 'test':
            stage = 'tests'
        elif argv[-1] == 'archive':
            stage = 'archive'
        elif '-exportArchive' in argv:
            stage = 'export'
        elif argv[:2] == ['testflight', 'upload']:
            stage = 'upload'
        elif 'unlock' in argv:
            stage = 'unlock'
        elif argv[:3] == ['codesign', '--force', '--sign']:
            stage = 'signing'
        elif argv[:4] == ['asc', 'profiles', 'local', 'install']:
            stage = 'profile'
        if stage == 'upload' and (self.failure != 'upload' or self.receipt_on_failure):
            receipt = Path(argv[argv.index('--receipt') + 1])
            receipt.write_text(json.dumps({'app_id': CONFIG['app_id'], 'bundle_id': CONFIG['bundle_id'],
                                          'group_id': CONFIG['group_id'], 'source_sha': SHA, 'build_number': '8'}))
        if stage == self.failure and stage is not None:
            raise RuntimeError(stage + ' failed')
        if stage == 'archive':
            app = Path(argv[argv.index('-archivePath') + 1]) / 'Products/Applications/App.app'
            bundle(app, 'example.app')
            bundle(app / 'Frameworks/Kit.framework', 'example.kit')
            for path, identifier in self.embedded:
                bundle(app / path, identifier)
        if stage == 'export':
            export = Path(argv[argv.index('-exportPath') + 1])
            export.mkdir()
            (export / 'App.ipa').write_bytes(b'ipa')
        if stage == self.change_after and stage is not None:
            self.head = 'b' * 40
        return '{}', 0

    def test_other_group_receipt_cannot_reach_cli(self):
        receipt = self.root / 'receipt.json'
        receipt.write_text(json.dumps({**CONFIG, 'group_id': 'external'}))
        with self.assertRaisesRegex(RuntimeError, 'different app or group'):
            self.invoke('resume', '--receipt', str(receipt))
        self.assertEqual(self.commands, [])

    def test_dirty_source_prevents_signing_and_build(self):
        self.dirty = ' M App.swift'
        with self.assertRaisesRegex(RuntimeError, 'clean, committed'):
            self.invoke('release')
        self.assert_no('unlock', 'test', 'archive', 'upload')

    def test_check_unlocks_signs_verifies_and_installs_every_profile(self):
        self.assertEqual(self.invoke('check'), 0)
        unlock = next(i for i, c in enumerate(self.commands) if 'unlock' in c)
        sign = next(i for i, c in enumerate(self.commands) if c[0] == 'codesign' and '--sign' in c)
        installs = [c for c in self.commands if c[:4] == ['asc', 'profiles', 'local', 'install']]
        self.assertLess(unlock, sign)
        self.assertTrue(any('--verify' in c for c in self.commands))
        self.assertEqual({Path(c[c.index('--path') + 1]).name for c in installs}, {'App.mobileprovision', 'Watch.mobileprovision'})
        self.assertTrue(all('--force' in c for c in installs))
        self.assert_no('test', 'archive', 'upload', 'next-build-number')

    def test_preflight_failure_prevents_tests_and_build_allocation(self):
        for failure in ['unlock', 'signing', 'profile']:
            with self.subTest(failure=failure):
                self.failure = failure
                self.commands.clear()
                with self.assertRaisesRegex(RuntimeError, failure + ' failed'):
                    self.invoke('release')
                self.assert_no('test', 'archive', 'upload', 'next-build-number')

    def test_dry_run_has_no_mutations(self):
        self.assertEqual(self.invoke('release', '--dry-run'), 0)
        self.assert_no('unlock', 'set-partition-list', 'install', 'codesign', 'test', 'archive', 'upload')
        self.assertFalse((self.root / '.local').exists())

    def test_failed_tests_are_not_saved_or_reused(self):
        self.failure = 'tests'
        with self.assertRaisesRegex(RuntimeError, 'tests failed'):
            self.invoke('release')
        self.assertEqual(self.state['stage'], 'new')
        self.assertNotIn('tests', self.state)
        self.assert_no('archive', 'upload', 'next-build-number')
        self.failure = None
        self.commands.clear()
        self.invoke('release', '--state', str(self.checkpoint), '--stop-after', 'tests')
        self.assertTrue(any(c[-1] == 'test' for c in self.commands))

    def test_source_change_during_tests_prevents_checkpoint_and_archive(self):
        self.change_after = 'tests'
        with self.assertRaisesRegex(RuntimeError, 'same clean'):
            self.invoke('release')
        self.assertEqual(self.state['stage'], 'new')
        self.assert_no('archive', 'upload')

    def test_all_targets_keep_their_profiles_and_explicit_keychain(self):
        self.invoke('release', '--stop-after', 'export')
        archive = next(c for c in self.commands if c[-1] == 'archive')
        self.assertIn('PROVISIONING_PROFILE_SPECIFIER=$(TRIPSPLIT_PROFILE_$(TARGET_NAME))', archive)
        self.assertIn('TRIPSPLIT_PROFILE_App=app-profile', archive)
        self.assertIn('TRIPSPLIT_PROFILE_Watch=watch-profile', archive)
        self.assertTrue(any(c.startswith('OTHER_CODE_SIGN_FLAGS=--keychain ') for c in archive))
        options = plistlib.loads(next(self.checkpoint.parent.glob('export-*/ExportOptions.plist')).read_bytes())
        self.assertEqual(options['provisioningProfiles'], {'example.app': 'app-profile', 'example.app.watchkitapp': 'watch-profile'})
        self.assertTrue(options['testFlightInternalTestingOnly'])
        self.assertFalse(options['manageAppVersionAndBuildNumber'])
        self.assertEqual(options['destination'], 'export')
        self.assertEqual(self.state['stage'], 'exported')
        self.assert_no('upload')

    def test_unexpected_archive_bundle_prevents_export(self):
        self.embedded.append(('PlugIns/Share.appex', 'example.app.share'))
        with self.assertRaisesRegex(RuntimeError, "don't match"):
            self.invoke('release')
        self.assertEqual(self.state['stage'], 'tested')
        self.assert_no('-exportArchive', 'upload')

    def test_missing_extension_prevents_export(self):
        self.embedded = []
        with self.assertRaisesRegex(RuntimeError, "don't match"):
            self.invoke('release')
        self.assert_no('-exportArchive', 'upload')

    def test_resume_archive_failure_reuses_tests_but_reallocates_build_number(self):
        self.failure = 'archive'
        with self.assertRaisesRegex(RuntimeError, 'archive failed'):
            self.invoke('release')
        self.failure = None
        self.number = 9
        self.commands.clear()
        self.invoke('release', '--state', str(self.checkpoint), '--stop-after', 'archive')
        self.assert_no('test', 'upload')
        self.assertEqual(self.state['stage'], 'archived')
        self.assertEqual(self.state['build_number'], '9')
        self.assertEqual(len(list(self.checkpoint.parent.glob('archive-*'))), 2)

    def test_resume_export_failure_preserves_archive_and_tests(self):
        self.failure = 'export'
        with self.assertRaisesRegex(RuntimeError, 'export failed'):
            self.invoke('release')
        self.failure = None
        self.commands.clear()
        self.invoke('release', '--state', str(self.checkpoint), '--stop-after', 'export')
        self.assert_no('test', 'archive', 'upload', 'next-build-number')
        self.assertEqual(self.state['stage'], 'exported')
        self.assertEqual(len(list(self.checkpoint.parent.glob('export-*'))), 2)

    def test_each_stop_point_can_resume_without_earlier_stages(self):
        self.invoke('release', '--stop-after', 'tests')
        checkpoint = str(self.checkpoint)
        self.commands.clear()
        self.invoke('release', '--state', checkpoint, '--stop-after', 'archive')
        self.assert_no('test', '-exportArchive', 'upload')
        self.commands.clear()
        self.invoke('release', '--state', checkpoint, '--stop-after', 'export')
        self.assert_no('test', 'archive', 'upload')
        self.commands.clear()
        self.invoke('release', '--state', checkpoint)
        self.assert_no('test', 'archive', '-exportArchive')
        self.assertEqual(sum(c[:2] == ['testflight', 'upload'] for c in self.commands), 1)

    def test_source_toolchain_and_configuration_changes_reject_resume(self):
        self.invoke('release', '--stop-after', 'tests')
        for field in ['source', 'xcode', 'config']:
            with self.subTest(field=field):
                self.head = 'b' * 40 if field == 'source' else SHA
                self.toolchain = 'different' if field == 'xcode' else 'Xcode test'
                config = {**CONFIG, 'scheme': 'Different'} if field == 'config' else CONFIG
                (self.root / 'apple/ios/testflight.json').write_text(json.dumps(config))
                self.commands.clear()
                with self.assertRaisesRegex(RuntimeError, 'different source, configuration or Xcode'):
                    self.invoke('release', '--state', str(self.checkpoint))
                self.assert_no('unlock', 'test', 'archive', 'upload')

    def test_changed_artifacts_block_resume(self):
        self.invoke('release', '--stop-after', 'export')
        for kind in ['tests', 'archive', 'ipa']:
            with self.subTest(kind=kind):
                p = self.checkpoint.parent / self.state[kind]['path']
                target = next(p.rglob('Info.plist')) if p.is_dir() else p
                before = target.read_bytes()
                target.write_bytes(b'changed')
                self.commands.clear()
                with self.assertRaisesRegex(RuntimeError, 'missing or changed'):
                    self.invoke('release', '--state', str(self.checkpoint))
                self.assert_no('unlock', 'archive', 'upload')
                target.write_bytes(before)

    def test_source_change_during_archive_prevents_export_and_checkpoint(self):
        self.change_after = 'archive'
        with self.assertRaisesRegex(RuntimeError, 'same clean'):
            self.invoke('release')
        self.assertEqual(self.state['stage'], 'tested')
        self.assert_no('-exportArchive', 'upload')

    def test_source_change_during_export_prevents_upload(self):
        self.change_after = 'export'
        with self.assertRaisesRegex(RuntimeError, 'same clean'):
            self.invoke('release')
        self.assertEqual(self.state['stage'], 'archived')
        self.assert_no('upload')

    def test_consumed_number_prevents_upload(self):
        self.invoke('release', '--stop-after', 'export')
        self.number = 9
        self.commands.clear()
        with self.assertRaisesRegex(RuntimeError, 'consumed this build number'):
            self.invoke('release', '--state', str(self.checkpoint))
        self.assert_no('upload')

    def test_ambiguous_upload_with_receipt_only_resumes(self):
        self.failure = 'upload'
        self.receipt_on_failure = True
        with self.assertRaisesRegex(RuntimeError, 'upload failed'):
            self.invoke('release')
        self.commands.clear()
        self.invoke('release', '--state', str(self.checkpoint))
        self.assert_no('upload', 'test', 'archive', 'unlock', '-exportArchive')
        self.assertTrue(any(c[:2] == ['testflight', 'resume'] for c in self.commands))

    def test_ambiguous_upload_without_receipt_is_never_repeated(self):
        self.failure = 'upload'
        with self.assertRaisesRegex(RuntimeError, 'upload failed'):
            self.invoke('release')
        self.assertEqual(self.state['stage'], 'upload_started')
        self.commands.clear()
        with self.assertRaisesRegex(RuntimeError, 'do not upload again'):
            self.invoke('release', '--state', str(self.checkpoint))
        self.assert_no('upload', 'unlock', 'archive')

    def test_mismatched_upload_receipt_does_not_resume(self):
        self.invoke('release')
        receipt = self.checkpoint.parent / 'release.json'
        data = json.loads(receipt.read_text())
        data['build_number'] = 'other'
        receipt.write_text(json.dumps(data))
        self.commands.clear()
        with self.assertRaisesRegex(RuntimeError, 'does not match'):
            self.invoke('release', '--state', str(self.checkpoint))
        self.assert_no('resume', 'upload')

    def test_lock_prevents_preflight_and_build(self):
        folder = self.root / '.local/state/testflight/tripsplit'
        folder.mkdir(parents=True)
        with (folder / 'release.lock').open('a') as lock:
            release.fcntl.flock(lock, release.fcntl.LOCK_EX | release.fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, 'Another TripSplit'):
                self.invoke('check')
        self.assertEqual(self.commands, [])


class IdentityTests(unittest.TestCase):
    def test_wrong_team_bundle_expired_or_device_profile_is_rejected(self):
        certificate = b'certificate'
        fingerprint = release.hashlib.sha1(certificate).hexdigest().upper()
        base = {'TeamIdentifier': ['TEAM'], 'UUID': 'profile', 'DeveloperCertificates': [certificate],
                'ExpirationDate': (datetime.now(timezone.utc) + timedelta(days=30)).replace(tzinfo=None),
                'Entitlements': {'application-identifier': 'TEAM.example.app', 'get-task-allow': False}}
        config = {**CONFIG, 'targets': {'App': CONFIG['targets']['App']}}
        variants = [{'TeamIdentifier': ['OTHER']}, {'Entitlements': {'application-identifier': 'TEAM.other', 'get-task-allow': False}},
                    {'ExpirationDate': datetime(2020, 1, 1)}, {'ProvisionedDevices': ['device']}, {'ProvisionsAllDevices': True}]
        for change in variants:
            with self.subTest(change=change):
                with patch.object(release, 'run', side_effect=[(fingerprint, 0), (plistlib.dumps({**base, **change}).decode(), 0)]):
                    with self.assertRaisesRegex(RuntimeError, 'expired or does not match'):
                        release.identity(config, Path('/signing'), {})


if __name__ == '__main__':
    unittest.main()
