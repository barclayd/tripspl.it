#!/usr/bin/env python3
"""TripSplit's local internal release entrypoint. Requires the barclayd TestFlight tools."""
import argparse
import contextlib
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]


def run(args, *, env, log=None, timeout=60, accepted=(0,)):
    if log:
        print(f"Running {log.stem}; private log: {log}", flush=True)
    with contextlib.ExitStack() as stack:
        output = stack.enter_context(log.open("w")) if log else subprocess.PIPE
        process = subprocess.Popen(args, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                   stdout=output, stderr=subprocess.STDOUT if log else subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            stdout, _ = process.communicate(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(process.pid, signal.SIGINT)
            try:
                process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
            raise RuntimeError("Command interrupted; inspect the existing receipt before retrying an upload.") from None
    text = log.read_text() if log else stdout
    if process.returncode not in accepted:
        raise RuntimeError(f"{args[0]} failed (exit {process.returncode})." + (f" Inspect {log}." if log else " Output withheld."))
    return text.strip(), process.returncode


def identity(config, folder, env):
    """Each target's App Store profile UUID, and the one distribution identity they're all signed with."""
    keychain = folder / "codex-testflight.keychain-db"
    found, _ = run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)], env=env)
    profiles, identities = {}, set()
    for target, signing in config["targets"].items():
        profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(folder / signing["profile"])], env=env)[0].encode())
        entitlements = profile.get("Entitlements", {})
        if (profile.get("TeamIdentifier") != [config["team_id"]]
                or entitlements.get("application-identifier") != f'{config["team_id"]}.{signing["bundle_id"]}'
                or entitlements.get("get-task-allow") is not False or profile.get("ProvisionedDevices")
                or profile.get("ProvisionsAllDevices")
                or profile["ExpirationDate"].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc)):
            raise RuntimeError(f'{signing["profile"]} is expired or does not match the App Store identity of {signing["bundle_id"]}.')
        fingerprints = [hashlib.sha1(c).hexdigest().upper() for c in profile["DeveloperCertificates"]]
        matches = [sha for sha in fingerprints if sha in found.upper()]
        if len(matches) != 1:
            raise RuntimeError(f'The dedicated keychain has no unique valid identity matching {signing["profile"]}. Unlock it or repair signing.')
        profiles[target] = profile["UUID"]
        identities.add(matches[0])
    if len(identities) != 1:
        raise RuntimeError("The targets' profiles must share one distribution identity.")
    return profiles, identities.pop()


def bundle_ids(archive):
    """The bundle IDs of the archived app and every app and extension embedded in it."""
    apps = list((archive / "Products/Applications").glob("*.app"))
    if len(apps) != 1:
        raise RuntimeError("The archive does not contain exactly one app.")
    return {plistlib.loads(info.read_bytes())["CFBundleIdentifier"]
            for info in apps[0].rglob("Info.plist") if info.parent.suffix in (".app", ".appex")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "release", "resume", "status"])
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--dry-run", action="store_true", help="Inspect the release plan without testing, signing or uploading")
    args = parser.parse_args()
    if args.action in ("resume", "status") and args.receipt is None:
        parser.error("--receipt is required")
    if args.dry_run and args.action != "release":
        parser.error("--dry-run is only supported with release")
    os.umask(0o077)
    configs = [ROOT / "apple/ios/testflight.json"]
    configs = [p for p in configs if p.is_file()]
    if len(configs) != 1:
        raise RuntimeError("Expected the TestFlight config at apple/ios/testflight.json.")
    config = json.loads(configs[0].read_text())
    projects = [p for p in config["project_candidates"] if (ROOT / p).is_dir()]
    if len(projects) != 1:
        raise RuntimeError("Expected one committed TripSplit Xcode project; resolve missing/ambiguous paths.")
    config["project"] = projects[0]
    env = dict(os.environ, TESTFLIGHT_ASC_PROFILE=config["api_profile"], ASC_TELEMETRY_DISABLED="1")
    if args.action in ("resume", "status"):
        # Match the app before allowing a saved receipt to choose a mutation target.
        receipt = json.loads(args.receipt.read_text())
        if any(receipt.get(k) != config[k] for k in ("app_id", "bundle_id", "group_id")):
            raise RuntimeError("Receipt belongs to a different app or group.")
        text, code = run(["testflight", args.action, "--receipt", str(args.receipt.resolve())], env=env, timeout=240, accepted=(0, 7))
        print(text)
        return code
    signing = Path(os.environ.get("TRIPSPLIT_SIGNING_DIR", str(Path.home() / ".config/testflight/signing/tripsplit")))
    flags = ["--app", config["app_id"], "--bundle-id", config["bundle_id"], "--group-id", config["group_id"]]
    text, _ = run(["testflight", "check", *flags], env=env, timeout=240)
    if args.action == "release" and not args.dry_run:
        run(["asc", "signing", "keychain", "unlock", "--keychain", str(signing / "codex-testflight.keychain-db"),
             "--keychain-password-file", str(signing / "keychain-password"), "--timeout", "3600"], env=env)
    profiles, certificate = identity(config, signing, env)
    if args.action == "check":
        report = json.loads(text)
        report["local_signing_identity_and_profile_match"] = True
        report["archive_export_verified"] = False
        print(json.dumps(report, indent=2))
        return 0
    source, _ = run(["git", "rev-parse", "HEAD"], env=env)
    dirty, _ = run(["git", "status", "--porcelain"], env=env)
    if dirty:
        raise RuntimeError("Commit the intended source first; release requires a clean checkout.")
    cache = Path.home() / "Library/Caches/TripSplit/TestFlightDerivedData"
    if args.dry_run:
        print(json.dumps({"source_sha": source, "app_id": config["app_id"], "group_id": config["group_id"],
                          "signing": "manual", "targets": sorted(profiles), "internal_only": True, "derived_data": str(cache),
                          "steps": ["test", "allocate number", "unlock signing", "archive", "export", "upload", "resume"]}, indent=2))
        return 0
    state = Path.home() / ".local/state/testflight/tripsplit"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state / "release.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another TripSplit local release is running; do not allocate another build.") from None
        output = state / f'{datetime.now(timezone.utc):%Y%m%dT%H%M%S}-{source[:8]}'
        output.mkdir(mode=0o700)
        common = ["xcodebuild", "-project", config["project"], "-scheme", config["scheme"], "-derivedDataPath", str(cache)]
        run([*common, "-destination", config["test_destination"], "CODE_SIGNING_ALLOWED=NO", "test"],
            env=env, timeout=1800, log=output / "tests.log")
        current, _ = run(["git", "rev-parse", "HEAD"], env=env)
        dirty, _ = run(["git", "status", "--porcelain"], env=env)
        if current != source or dirty:
            raise RuntimeError("Source changed during tests; no archive or upload was attempted.")
        number, _ = run(["asc", "--profile", config["api_profile"], "builds", "next-build-number", "--app", config["app_id"],
                         "--platform", "IOS", "--output", "json"], env=env)
        build_number = str(json.loads(number)["nextBuildNumber"])
        run(["asc", "signing", "keychain", "unlock", "--keychain", str(signing / "codex-testflight.keychain-db"),
             "--keychain-password-file", str(signing / "keychain-password"), "--timeout", "3600"], env=env)
        archive = output / "TripSplit.xcarchive"
        run([*common, "-configuration", "Release", "-destination", "generic/platform=iOS", "-archivePath", str(archive),
             f'DEVELOPMENT_TEAM={config["team_id"]}', "CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={certificate}",
             # Each target signs with its own profile: the app, its widgets, the watch app and its complications.
             "PROVISIONING_PROFILE_SPECIFIER=$(TRIPSPLIT_PROFILE_$(TARGET_NAME))",
             *[f"TRIPSPLIT_PROFILE_{target}={uuid}" for target, uuid in profiles.items()],
             f"CURRENT_PROJECT_VERSION={build_number}", "archive"],
            env=env, timeout=1800, log=output / "archive.log")
        if bundle_ids(archive) != {signing["bundle_id"] for signing in config["targets"].values()}:
            raise RuntimeError("The archived apps and extensions don't match the targets in testflight.json; no export was attempted.")
        current, _ = run(["git", "rev-parse", "HEAD"], env=env)
        dirty, _ = run(["git", "status", "--porcelain"], env=env)
        if current != source or dirty:
            raise RuntimeError("Source changed during archive; no upload was attempted.")
        options = {"method": "app-store-connect", "destination": "export", "signingStyle": "manual",
                   "teamID": config["team_id"], "signingCertificate": certificate,
                   "provisioningProfiles": {config["targets"][target]["bundle_id"]: uuid for target, uuid in profiles.items()},
                   "testFlightInternalTestingOnly": True,
                   "manageAppVersionAndBuildNumber": False, "uploadSymbols": True}
        plist = output / "ExportOptions.plist"
        plist.write_bytes(plistlib.dumps(options))
        run(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(output / "export"),
             "-exportOptionsPlist", str(plist)], env=env, timeout=900, log=output / "export.log")
        ipas = list((output / "export").glob("*.ipa"))
        if len(ipas) != 1:
            raise RuntimeError("Export did not produce exactly one IPA.")
        receipt = output / "release.json"
        print(f"Release receipt: {receipt}", flush=True)
        run(["testflight", "upload", *flags, "--ipa", str(ipas[0]), "--source-sha", source, "--receipt", str(receipt)],
            env=env, timeout=1900, log=output / "upload-command.log")
        text, code = run(["testflight", "resume", "--receipt", str(receipt)], env=env, timeout=240, accepted=(0, 7))
        print(text)
        return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, KeyError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"TestFlight stopped: {error}", file=sys.stderr)
        sys.exit(1)
