#!/usr/bin/env python3
"""Build isolated release fixtures; never access accounts or HID devices.

Run explicitly with `python3 tests/PackagingTests.py` (requires the normal
Swift/macOS build tools). This test compiles in a temporary source checkout.
"""
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile
import fnmatch
import hashlib
import subprocess
import uuid


def run():
    root = Path(__file__).resolve().parents[1]
    (root / "build").mkdir(exist_ok=True)
    with TemporaryDirectory(prefix="feralkey-packaging-", dir=root / "build") as temporary:
        fixture = Path(temporary)
        source_items = ["Sources", "Resources", "scripts", "tests", "docs", ".github", "LICENSE", "README.md",
                        "THIRD_PARTY.md", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md", ".gitignore", ".gitattributes", "FeralKey_logo.png"]
        subprocess.run(["/usr/bin/rsync", "-a", "--safe-links",
                        *[str(root / item) for item in source_items], str(fixture) + "/"], check=True)
        assert not (fixture / ".git").exists(), "test must also support ZIP source checkouts"
        sentinel = ("FeralKeyPackagingFixture:" + uuid.uuid4().hex).encode()
        unwanted = ["docs/private/nested/.env.production", "Sources/local/clientauth.json",
                    "Resources/auth.json", "Resources/private/nested/session-token.json",
                    "tests/local/private-token-copy.json", "scripts/local/feralkey-device-research-test.json",
                    "docs/.DS_Store", ".github/local/private.p8", "docs/private/session.pcapng",
                    "Resources/private/certificate.pem", "tests/local/session.har",
                    "Sources/private/device.key", "scripts/local/signing.p12"]
        for name in unwanted:
            target = fixture / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(sentinel)
        # A stale file in an old installed bundle must never survive a rebuild.
        stale = fixture / "build/FeralKey.app/Contents/Resources/staleauth.json"
        stale.parent.mkdir(parents=True, exist_ok=True)
        stale.write_bytes(sentinel)
        # Out-of-tree symlinks are excluded rather than dereferenced into ZIPs.
        (fixture / "docs/outside-file").symlink_to(root / "README.md")
        subprocess.run([str(fixture / "scripts/package.sh")], cwd=fixture, check=True)
        release = fixture / "build/releases"
        source_zip = release / "FeralKey-0.10.0-source.zip"
        app_zip = next(release.glob("FeralKey-0.10.0-macOS-*.zip"))
        patterns = [".env*", "*auth.json", "*token*.json", "*.xcuserstate",
                    "feralkey-device-research*.json", ".DS_Store", "*.pcap", "*.pcapng",
                    "*.btsnoop", "*.har", "*.p12", "*.p8", "*.pem", "*.key"]
        for archive in [source_zip, app_zip]:
            with ZipFile(archive) as zipped:
                assert zipped.testzip() is None
                for name in zipped.namelist():
                    assert not any(fnmatch.fnmatch(part, pattern) for part in Path(name).parts for pattern in patterns), name
                    assert sentinel not in zipped.read(name), name
                assert not any(name.endswith("/outside-file") for name in zipped.namelist())
        logo = (root / "FeralKey_logo.png").read_bytes()
        with ZipFile(source_zip) as zipped:
            assert zipped.read("FeralKey-0.10.0/FeralKey_logo.png") == logo
            for relative in ["Sources/Main.swift", "docs/KEYBOARD-GUIDE.md", "docs/ARCHITECTURE.md", ".github/workflows/ci.yml", "SECURITY.md", "CHANGELOG.md", "Resources/keycodes.json", "Resources/rk98-layout.json"]:
                assert zipped.read("FeralKey-0.10.0/" + relative) == (fixture / relative).read_bytes()
            unpacked = fixture / "unpacked-source"
            zipped.extractall(unpacked)
        subprocess.run(["python3", "scripts/check-repository.py"],
                       cwd=unpacked / "FeralKey-0.10.0", check=True)
        with ZipFile(app_zip) as zipped:
            assert zipped.read("FeralKey.app/Contents/Resources/FeralKey_logo.png") == logo
            runtime_json = {name for name in zipped.namelist() if name.endswith(".json")}
            assert runtime_json == {"FeralKey.app/Contents/Resources/keycodes.json", "FeralKey.app/Contents/Resources/rk98-layout.json"}, runtime_json
        app = fixture / "build/FeralKey.app"
        def hashes():
            return {str(path.relative_to(app)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in app.rglob("*") if path.is_file()}
        previous = hashes()
        # Inject a compiler failure after a complete valid app has been built.
        with (fixture / "Sources/Protocol.swift").open("a") as source:
            source.write("\n#error(\"intentional packaging regression fixture\")\n")
        failed = subprocess.run([str(fixture / "scripts/build.sh")], cwd=fixture,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert failed.returncode != 0, "compiler failure was not exercised"
        assert hashes() == previous, "failed build replaced or damaged the last good app"
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        print("PASS: nested fake credentials excluded from source/app ZIPs; stale resources removed; out-of-tree links excluded; original logo preserved; source ZIP works without Git; failed build preserves last signed app.")


if __name__ == "__main__":
    run()
