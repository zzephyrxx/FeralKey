#!/usr/bin/env python3
"""Offline publication checks. Reports locations, never matched secret values.

Checks common credential formats and repository paths, not arbitrary personal
data. --history inspects only commits reachable from HEAD, not private tool refs.
"""
from pathlib import Path
from urllib.parse import unquote, urlsplit
import argparse
import fnmatch
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRS = {".git", "build", "evidence", ".build", ".swiftpm", ".idea", ".vscode", "__pycache__"}
PRIVATE_NAMES = [".DS_Store", ".env*", "*auth.json", "*token*.json", "*.xcuserstate",
                 "feralkey-device-research*.json", "*.pcap", "*.pcapng", "*.btsnoop", "*.har",
                 "*.p12", "*.p8", "*.pem", "*.key"]
SECRETS = [
    re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})"),
    re.compile(rb"sk-(?:proj-)?[A-Za-z0-9_-]{24,}"),
    re.compile(rb"(?:AKIA|ASIA)[A-Z0-9]{16}"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
]
LINK = re.compile(r"!?\[[^\]\n]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)")
HTML_LINK = re.compile(r"(?:href|src)=[\"']([^\"']+)[\"']")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def forbidden(name):
    parts = Path(name).parts
    return any(part in EXCLUDED_DIRS or any(fnmatch.fnmatch(part, rule) for rule in PRIVATE_NAMES) for part in parts)


def anchors(path):
    found, counts = set(), {}
    for text in path.read_text(encoding="utf-8").splitlines():
        if not re.match(r"^#{1,6}\s", text):
            continue
        title = re.sub(r"^#{1,6}\s+|\s+#+$", "", text).lower()
        title = re.sub(r"[^\w\s-]", "", title).replace(" ", "-")
        n = counts.get(title, 0)
        counts[title] = n + 1
        found.add(title + (f"-{n}" if n else ""))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true", help="also inspect HEAD history")
    args = parser.parse_args()
    errors = []
    try:
        # An outer repository must not turn a source ZIP into a Git checkout.
        has_git = Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve() == ROOT
    except (subprocess.CalledProcessError, FileNotFoundError):
        has_git = False
    if has_git:
        names = set(git("ls-files", "--cached", "--others", "--exclude-standard", "-z").decode().split("\0")) - {""}
    else:
        names = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*")
                 if not any(part in EXCLUDED_DIRS for part in p.relative_to(ROOT).parts) and p.is_file()}
    scanned = 0
    for name in sorted(names):
        path = ROOT / name
        if forbidden(name):
            errors.append(f"Forbidden publication path: {name}")
            continue
        if not path.exists():  # deleted during a reviewed reorganization
            continue
        if path.is_symlink():
            errors.append(f"Review symlink before publication: {name}")
            continue
        data = path.read_bytes()
        scanned += 1
        for pattern in SECRETS:
            match = pattern.search(data)
            if match:
                line = data[:match.start()].count(b"\n") + 1
                errors.append(f"Potential credential: {name}:{line} (value withheld)")
        if path.suffix.lower() != ".md":
            continue
        text = re.sub(r"```[\s\S]*?```", "", data.decode("utf-8"))
        for target in LINK.findall(text) + HTML_LINK.findall(text):
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc:
                continue
            dest = (path.parent / unquote(parsed.path)).resolve() if parsed.path else path
            if not dest.is_relative_to(ROOT) or not dest.exists():
                errors.append(f"Broken local link: {name} -> {target}")
            elif parsed.fragment and dest.suffix == ".md" and unquote(parsed.fragment) not in anchors(dest):
                errors.append(f"Missing heading anchor: {name} -> {target}")
    history_count = 0
    if args.history:
        if not has_git:
            errors.append("History check requires a Git checkout.")
        else:
            seen = set()
            for commit in git("rev-list", "HEAD").decode().splitlines():
                entries = git("ls-tree", "-r", "-z", commit).split(b"\0")
                for entry in filter(None, entries):
                    metadata, raw_name = entry.split(b"\t", 1)
                    _, kind, oid = metadata.split()
                    name = raw_name.decode("utf-8")
                    if forbidden(name):
                        errors.append(f"Forbidden historical path: {commit[:8]}:{name}")
                    if kind != b"blob" or oid in seen:
                        continue
                    seen.add(oid)
                    data = git("cat-file", "blob", oid.decode())
                    history_count += 1
                    if any(pattern.search(data) for pattern in SECRETS):
                        errors.append(f"Potential historical credential: {commit[:8]}:{name} (value withheld)")
    if errors:
        print("\n".join(sorted(set(errors))), file=sys.stderr)
        return 1
    print(f"PASS: {scanned} working-tree files; local Markdown/HTML links and common credential/path checks.")
    if args.history:
        print(f"PASS: {history_count} unique blobs reachable from HEAD; common credential/path checks.")
    print("No network, account or hardware access. Manual privacy and license review still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
