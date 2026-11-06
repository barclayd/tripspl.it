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
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def save(path, data):
    """Commit a checkpoint only after a stage succeeds; interrupted writes stay atomic."""
    fd, temporary = tempfile.mkstemp(prefix=".checkpoint-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as file:
            json.dump(data, file, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def digest(path):
    """Bind saved tests and signed artifacts to their actual contents."""
    if path.is_file():
        with path.open("rb") as file:
            return hashlib.file_digest(file, "sha256").hexdigest()
    result = hashlib.sha256()
    for item in sorted(path.rglob("*")):
        result.update(str(item.relative_to(path)).encode() + b"\0")
        if item.is_symlink():
            result.update(b"link\0" + os.readlink(item).encode())
        elif item.is_file():
            with item.open("rb") as file:
                result.update(hashlib.file_digest(file, "sha256").digest())
    return result.hexdigest()


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


def signing_preflight(config, folder, env, output):
    """Exercise the private key before tests, and install every selected profile."""
    keychain = folder / "codex-testflight.keychain-db"
    credentials = ["--keychain", str(keychain), "--keychain-password-file", str(folder / "keychain-password")]
    run(["asc", "signing", "keychain", "unlock", *credentials, "--timeout", "3600"],
        env=env, log=output / "unlock.log")
    profiles, certificate = identity(config, folder, env)
    # Restore the dedicated key's codesign access without an interactive permission dialog.
    run(["asc", "signing", "keychain", "set-partition-list", *credentials],
        env=env, log=output / "key-access.log")
    with tempfile.TemporaryDirectory(prefix="signing-probe-", dir=output) as temporary:
        probe = Path(temporary) / "Probe.bundle"
        probe.mkdir()
        (probe / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": config["bundle_id"] + ".signing-probe",
            "CFBundleVersion": "1", "CFBundlePackageType": "BNDL"}))
        run(["codesign", "--force", "--sign", certificate, "--keychain", str(keychain),
             "--timestamp=none", str(probe)], env=env, timeout=30, log=output / "signing-probe.log")
        run(["codesign", "--verify", "--strict", str(probe)], env=env,
            log=output / "signing-verify.log")
    for target, signing in config["targets"].items():
        run(["asc", "profiles", "local", "install", "--path", str(folder / signing["profile"]), "--force"],
            env=env, log=output / f"profile-{target}.log")
    return profiles, certificate


def bundle_ids(archive):
    """The bundle IDs of the archived app and every app and extension embedded in it."""
    apps = list((archive / "Products/Applications").glob("*.app"))
    if len(apps) != 1:
        raise RuntimeError("The archive does not contain exactly one app.")
    return {plistlib.loads(info.read_bytes())["CFBundleIdentifier"]
            for info in apps[0].rglob("Info.plist") if info.parent.suffix in (".app", ".appex")}


def source_revision(env, expected=None):
    source, _ = run(["git", "rev-parse", "HEAD"], env=env)
    dirty, _ = run(["git", "status", "--porcelain"], env=env)
    if dirty or (expected is not None and source != expected):
        raise RuntimeError("Release requires the same clean, committed source; no further stage was started.")
    return source


def next_number(config, env):
    text, _ = run(["asc", "--profile", config["api_profile"], "builds", "next-build-number",
                   "--app", config["app_id"], "--platform", "IOS", "--output", "json"], env=env)
    return str(json.loads(text)["nextBuildNumber"])


def recorded_artifact(state, name, output):
    record = state[name]
    path = (output / record["path"]).resolve()
    if not path.is_relative_to(output.resolve()) or not path.exists() or digest(path) != record["sha256"]:
        raise RuntimeError(f"Saved {name} is missing or changed; it cannot be reused.")
    return path


def record_artifact(state, name, path, output):
    state[name] = {"path": str(path.relative_to(output)), "sha256": digest(path)}


def follow_receipt(config, receipt, action, env):
    data = json.loads(receipt.read_text())
    if any(data.get(k) != config[k] for k in ("app_id", "bundle_id", "group_id")):
        raise RuntimeError("Receipt belongs to a different app or group.")
    text, code = run(["testflight", action, "--receipt", str(receipt.resolve())],
                     env=env, timeout=240, accepted=(0, 7))
    print(text)
    return code


def build_release(config, signing, env, args, state_dir):
    source = source_revision(env)
    toolchain, _ = run(["xcodebuild", "-version"], env=env)
    context = {"source_sha": source, "config": config, "xcode": toolchain}
    if args.state:
        checkpoint = args.state.resolve()
        state = json.loads(checkpoint.read_text())
        if state.get("schema_version") != 1 or state.get("context") != context:
            raise RuntimeError("Saved release belongs to different source, configuration or Xcode; start a new release.")
        output = checkpoint.parent
    else:
        output = Path(tempfile.mkdtemp(prefix=f'{datetime.now(timezone.utc):%Y%m%dT%H%M%S}-{source[:8]}-', dir=state_dir))
        checkpoint = output / "build.json"
        state = {"schema_version": 1, "context": context, "stage": "new"}
        save(checkpoint, state)
    print(f"Build checkpoint: {checkpoint}", flush=True)
    stage = state["stage"]
    if stage not in ("new", "tested", "archived", "exported", "upload_started"):
        raise RuntimeError("Unknown release stage; no action was taken.")
    receipt = output / "release.json"
    if receipt.exists():
        uploaded = json.loads(receipt.read_text())
        if uploaded.get("source_sha") != source or uploaded.get("build_number") != state.get("build_number"):
            raise RuntimeError("Upload receipt does not match the saved build.")
        return follow_receipt(config, receipt, "resume", env)
    if stage == "upload_started":
        raise RuntimeError("Upload was attempted without a receipt. Reconcile the exact version/build with testflight track; do not upload again.")
    if stage != "new":
        recorded_artifact(state, "tests", output)
    if stage in ("archived", "exported"):
        recorded_artifact(state, "archive", output)
    if stage == "exported":
        recorded_artifact(state, "ipa", output)

    flags = ["--app", config["app_id"], "--bundle-id", config["bundle_id"], "--group-id", config["group_id"]]
    run(["testflight", "check", *flags], env=env, timeout=240)
    preflight_dir = Path(tempfile.mkdtemp(prefix="preflight-", dir=output))
    profiles, certificate = signing_preflight(config, signing, env, preflight_dir)
    cache = Path.home() / "Library/Caches/TripSplit/TestFlightDerivedData"
    common = ["xcodebuild", "-project", config["project"], "-scheme", config["scheme"], "-derivedDataPath", str(cache)]
    if stage == "new":
        run([*common, "-destination", config["test_destination"], "CODE_SIGNING_ALLOWED=NO", "test"],
            env=env, timeout=1800, log=output / "tests.log")
        source_revision(env, source)
        record_artifact(state, "tests", output / "tests.log", output)
        state["stage"] = stage = "tested"
        save(checkpoint, state)
    if args.stop_after == "tests":
        return 0

    if stage == "tested":
        source_revision(env, source)
        build_number = next_number(config, env)
        # A retry keeps the failed archive and logs for diagnosis.
        attempt = Path(tempfile.mkdtemp(prefix="archive-", dir=output))
        archive = attempt / "TripSplit.xcarchive"
        run(["asc", "signing", "keychain", "unlock", "--keychain", str(signing / "codex-testflight.keychain-db"),
             "--keychain-password-file", str(signing / "keychain-password"), "--timeout", "3600"],
            env=env, log=attempt / "unlock.log")
        run([*common, "-configuration", "Release", "-destination", "generic/platform=iOS", "-archivePath", str(archive),
             f'DEVELOPMENT_TEAM={config["team_id"]}', "CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={certificate}",
             f'OTHER_CODE_SIGN_FLAGS=--keychain "{signing / "codex-testflight.keychain-db"}"',
             "PROVISIONING_PROFILE_SPECIFIER=$(TRIPSPLIT_PROFILE_$(TARGET_NAME))",
             *[f"TRIPSPLIT_PROFILE_{target}={uuid}" for target, uuid in profiles.items()],
             f"CURRENT_PROJECT_VERSION={build_number}", "archive"], env=env, timeout=1800, log=attempt / "archive.log")
        if bundle_ids(archive) != {s["bundle_id"] for s in config["targets"].values()}:
            raise RuntimeError("The archived apps and extensions don't match testflight.json; no export was attempted.")
        source_revision(env, source)
        record_artifact(state, "archive", archive, output)
        state.update(stage="archived", build_number=build_number)
        stage = "archived"
        save(checkpoint, state)
    if args.stop_after == "archive":
        return 0

    if stage == "archived":
        source_revision(env, source)
        archive = recorded_artifact(state, "archive", output)
        attempt = Path(tempfile.mkdtemp(prefix="export-", dir=output))
        options = {"method": "app-store-connect", "destination": "export", "signingStyle": "manual",
                   "teamID": config["team_id"], "signingCertificate": certificate,
                   "provisioningProfiles": {config["targets"][target]["bundle_id"]: uuid for target, uuid in profiles.items()},
                   "testFlightInternalTestingOnly": True, "manageAppVersionAndBuildNumber": False, "uploadSymbols": True}
        plist = attempt / "ExportOptions.plist"
        plist.write_bytes(plistlib.dumps(options))
        run(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(attempt / "export"),
             "-exportOptionsPlist", str(plist)], env=env, timeout=900, log=attempt / "export.log")
        ipas = list((attempt / "export").glob("*.ipa"))
        if len(ipas) != 1:
            raise RuntimeError("Export did not produce exactly one IPA.")
        source_revision(env, source)
        record_artifact(state, "ipa", ipas[0], output)
        state["stage"] = "exported"
        save(checkpoint, state)
    if args.stop_after == "export":
        print(f"Signed IPA prepared; nothing uploaded. Resume with release --state {checkpoint}", flush=True)
        return 0

    source_revision(env, source)
    if int(next_number(config, env)) > int(state["build_number"]):
        raise RuntimeError("Another release consumed this build number. Start a new release; this IPA was not uploaded.")
    ipa = recorded_artifact(state, "ipa", output)
    # Save before invoking the upload helper, including failures before its own receipt exists.
    state["stage"] = "upload_started"
    save(checkpoint, state)
    print(f"Release receipt: {receipt}", flush=True)
    run(["testflight", "upload", *flags, "--ipa", str(ipa), "--source-sha", source, "--receipt", str(receipt)],
        env=env, timeout=1900, log=output / "upload-command.log")
    return follow_receipt(config, receipt, "resume", env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "release", "resume", "status"])
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--state", type=Path, help="Resume build.json from the same clean source and Xcode")
    parser.add_argument("--stop-after", choices=["tests", "archive", "export"], help="Save progress without uploading")
    parser.add_argument("--dry-run", action="store_true", help="Inspect the plan without unlocking, installing profiles or building")
    args = parser.parse_args()
    if args.action in ("resume", "status") and args.receipt is None:
        parser.error("--receipt is required")
    if args.receipt and args.action not in ("resume", "status"):
        parser.error("--receipt is only supported with resume or status")
    if (args.state or args.stop_after or args.dry_run) and args.action != "release":
        parser.error("--state, --stop-after and --dry-run are only supported with release")
    if args.dry_run and (args.state or args.stop_after):
        parser.error("--dry-run cannot be combined with --state or --stop-after")
    os.umask(0o077)
    config = json.loads((ROOT / "apple/ios/testflight.json").read_text())
    projects = [p for p in config["project_candidates"] if (ROOT / p).is_dir()]
    if len(projects) != 1:
        raise RuntimeError("Expected one committed TripSplit Xcode project; resolve missing/ambiguous paths.")
    config["project"] = projects[0]
    env = dict(os.environ, TESTFLIGHT_ASC_PROFILE=config["api_profile"], ASC_TELEMETRY_DISABLED="1")
    if args.action in ("resume", "status"):
        return follow_receipt(config, args.receipt, args.action, env)
    signing = Path(os.environ.get("TRIPSPLIT_SIGNING_DIR", str(Path.home() / ".config/testflight/signing/tripsplit"))).resolve()
    if args.dry_run:
        source = source_revision(env)
        profiles, _ = identity(config, signing, env)
        print(json.dumps({"source_sha": source, "app_id": config["app_id"], "group_id": config["group_id"],
                          "signing": "manual", "signing_verified": False, "targets": sorted(profiles), "internal_only": True,
                          "steps": ["signing preflight", "test", "allocate number", "archive", "export", "upload", "resume"]}, indent=2))
        return 0
    state_dir = Path.home() / ".local/state/testflight/tripsplit"
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state_dir / "release.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another TripSplit local release/check is running; wait for it to finish.") from None
        if args.action == "check":
            output = Path(tempfile.mkdtemp(prefix="check-", dir=state_dir))
            flags = ["--app", config["app_id"], "--bundle-id", config["bundle_id"], "--group-id", config["group_id"]]
            text, _ = run(["testflight", "check", *flags], env=env, timeout=240)
            signing_preflight(config, signing, env, output)
            report = dict(json.loads(text), signing_verified=True, profiles_installed=True,
                          archive_export_verified=False, logs=str(output))
            print(json.dumps(report, indent=2))
            return 0
        return build_release(config, signing, env, args, state_dir)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, KeyError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"TestFlight stopped: {error}", file=sys.stderr)
        sys.exit(1)
