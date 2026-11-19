"""Deploy one pushed commit: build or reuse its station package, then run the package's own install.

usage (Git Bash; the script itself is read from the commit, never from a working folder):
  set -o pipefail; git -C D:/Github/wsjtx-rust show <commit>:tools/deploy/station-update/make_package.py | python - <commit> [--dry-run]

The commit must be on GitHub master, and exactly one merge-queue log under
<git common dir>/harness-parallel/queue/logs/ must show its green push gate; that log is the
package's push-gate log. The package lives in
<git common dir>/harness-parallel/resources/station-update/packages/<ver>/{package/, deploy/,
manifest.json, gates.json, gate-receipt-<ver>.log}, never in a working tree. When that folder
holds the commit's package it is reused; when it is absent, the commit is exported with
`git archive` into a clean directory on C: and built there with
`cargo build --release --locked -p wstx-rust`. COPYING and every file under
server/third-party are copied from the exported commit into package/. The deploy mechanism
files (every file under tools/deploy/station-update/ and MECHANISM_FILES) are copied from the
export into deploy/<their path>; the manifest lists their SHA-256. Then the package's own
station-update.ps1 runs with -Manifest (and -DryRun for --dry-run); the command exits with
its exit code.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile

REPO = r"D:\Github\wsjtx-rust"
BUILD_ROOT = r"C:\wstx-build"
MECHANISM_DIR = "tools/deploy/station-update"
MECHANISM_FILES = ("tools/deploy/agent-client.ps1", "tools/deploy/station-probe.ps1", "tools/deploy/live-page-check.ps1")
POWERSHELL = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), r"System32\WindowsPowerShell\v1.0\powershell.exe")
USAGE = "usage: make_package.py <commit> [--dry-run]"
VERDICT = re.compile(r"^harness gate: \d+ suites, green", re.M)
PUSH = re.compile(r"^\s*[0-9a-f]+\.\.([0-9a-f]+)  HEAD -> master\s*$", re.M)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, text=True).stdout.strip()


def common_dir(repo):
    return git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")


def packages_root(repo):
    """The shared packages folder of the repository, outside every working tree."""
    return os.path.join(common_dir(repo), "harness-parallel", "resources", "station-update", "packages")


def push_gate_logs(repo, commit):
    """The merge-queue logs that show a green gate and the push of `commit` to master."""
    logs = os.path.join(common_dir(repo), "harness-parallel", "queue", "logs")
    found = []
    for name in sorted(os.listdir(logs)) if os.path.isdir(logs) else []:
        path = os.path.normpath(os.path.join(logs, name))
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        if VERDICT.search(text) and any(commit.startswith(new) for new in PUSH.findall(text)):
            found.append(path)
    return found


def export(repo, commit, dest):
    """Extract the commit's tree (git archive, so its bytes, not a working folder's) into dest."""
    os.makedirs(dest)
    archive = dest + ".tar"
    subprocess.run(["git", "-C", repo, "archive", "--format=tar", "-o", archive, commit], check=True)
    with tarfile.open(archive) as t:
        t.extractall(dest, filter="data")
    os.remove(archive)


def mechanism_paths(src):
    """Every mechanism file of the export: the station-update folder and MECHANISM_FILES."""
    paths = []
    for root, _, names in os.walk(os.path.join(src, *MECHANISM_DIR.split("/"))):
        for name in names:
            paths.append(os.path.relpath(os.path.join(root, name), src).replace(os.sep, "/"))
    return sorted(paths) + list(MECHANISM_FILES)


def copy_mechanism(src, out):
    """Copy the mechanism files from the export to out/deploy/<path>; returns their manifest list."""
    files = []
    for path in mechanism_paths(src):
        source = os.path.join(src, *path.split("/"))
        if not os.path.isfile(source):
            sys.exit(f"the commit has no {path}: the package would carry no deploy mechanism")
        dest = os.path.join(out, "deploy", *path.split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(source, dest)
        files.append({"path": path, "sha256": sha256(dest)})
    return files


def holds_package(out, commit):
    """Whether the folder holds a package of the commit: a manifest that names it."""
    try:
        with open(os.path.join(out, "manifest.json"), encoding="utf-8") as f:
            return json.load(f).get("source_commit") == commit
    except (OSError, ValueError, AttributeError):
        return False


def build(commit, ver, out, gate_log):
    """Build the package of the commit into out from its git archive export."""
    src = os.path.join(BUILD_ROOT, ver, "src")
    target = os.path.join(BUILD_ROOT, ver, "target")
    export(REPO, commit, src)
    # The station reports this commit itself (x-wstx-source-commit on GET /, #33).
    env = dict(os.environ, CARGO_TARGET_DIR=target, CARGO_BUILD_JOBS="2", WSTX_SOURCE_COMMIT=commit)
    result = subprocess.run(["cargo", "build", "--release", "--locked", "-p", "wstx-rust"], cwd=src, env=env,
                            capture_output=True, text=True)
    os.makedirs(out)
    with open(os.path.join(out, "build.log"), "w", encoding="utf-8") as f:
        f.write(result.stdout + result.stderr)
    if result.returncode != 0:
        sys.exit(f"release build failed, see {out}\\build.log")
    exe = os.path.join(target, "release", "wstx-rust.exe")

    package = os.path.join(out, "package")
    # The licence files come from the exported commit itself: COPYING and every file under
    # server/third-party (notices travel with the copies, e.g. cty/LICENSE for cty.dat, #55).
    sources = [("wstx-rust.exe", exe), ("COPYING", os.path.join(src, "COPYING"))]
    third = os.path.join(src, "server", "third-party")
    for root, _, names in os.walk(third):
        for name in sorted(names):
            full = os.path.join(root, name)
            rel = os.path.relpath(full, third).replace(os.sep, "/")
            sources.append(("third-party/" + rel, full))
    if not any(path.startswith("third-party/") for path, _ in sources):
        sys.exit("server/third-party is missing or empty in the commit: the package would ship no notices")
    files = []
    for path, source in sources:
        dest = os.path.join(package, path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(source, dest)
        files.append({"path": path, "sha256": sha256(dest)})
    exe_hash = sha256(os.path.join(package, "wstx-rust.exe"))
    deploy_files = copy_mechanism(src, out)

    receipt = os.path.join(out, f"gate-receipt-{ver}.log")
    shutil.copyfile(gate_log, receipt)
    toolchain = subprocess.run(["rustc", "--version"], capture_output=True, text=True).stdout.strip()
    gates = {
        "source_commit": commit,
        "artifact_sha256": exe_hash,
        "status": "passed",
        "prepush_passed": True,
        "gate_receipt": {"path": receipt, "sha256": sha256(receipt)},
        "production_build_command": "cargo build --release --locked -p wstx-rust (clean git archive export on C:, CARGO_BUILD_JOBS=2, WSTX_SOURCE_COMMIT=<commit>)",
        "toolchain": toolchain,
    }
    gates_path = os.path.join(out, "gates.json")
    with open(gates_path, "w", encoding="utf-8") as f:
        json.dump(gates, f, indent=2)
    manifest = {
        "source_commit": commit,
        "artifact_sha256": exe_hash,
        "package_files": files,
        "deploy_files": deploy_files,
        "gate_receipt_path": gates_path,
        "gate_receipt_sha256": sha256(gates_path),
    }
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    shutil.rmtree(os.path.join(BUILD_ROOT, ver), ignore_errors=True)


def main(argv):
    if len(argv) not in (1, 2) or argv[0].startswith("-") or argv[1:] not in ([], ["--dry-run"]):
        sys.exit(USAGE)
    dry_run = len(argv) == 2
    commit = git(REPO, "rev-parse", argv[0] + "^{commit}")
    ver = commit[:9]
    if subprocess.run(["git", "-C", REPO, "fetch", "-q", "origin", "master"]).returncode != 0:
        sys.exit("refused: git fetch of GitHub master failed")
    if subprocess.run(["git", "-C", REPO, "merge-base", "--is-ancestor", commit, "FETCH_HEAD"]).returncode != 0:
        sys.exit(f"refused: {ver} is not on GitHub master")
    logs = push_gate_logs(REPO, commit)
    if not logs:
        sys.exit(f"refused: no push-gate log shows the push of {ver} to master")
    if len(logs) > 1:
        sys.exit(f"refused: {len(logs)} push-gate logs show the push of {ver}: "
                 + ", ".join(os.path.basename(p) for p in logs))
    print(f"push-gate log: {logs[0]}", flush=True)

    out = os.path.normpath(os.path.join(packages_root(REPO), ver))
    if not os.path.exists(out):
        build(commit, ver, out, logs[0])
        print(f"package {ver}: built {out}", flush=True)
    elif holds_package(out, commit):
        print(f"package {ver}: reused {out}", flush=True)
    else:
        sys.exit(f"refused: {out} exists and holds no package of {commit}")

    station_update = os.path.join(out, "deploy", "tools", "deploy", "station-update", "station-update.ps1")
    args = ["-Manifest", os.path.join(out, "manifest.json")] + (["-DryRun"] if dry_run else [])
    run = subprocess.run([POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                          station_update, *args])
    sys.exit(run.returncode)


if __name__ == "__main__":
    main(sys.argv[1:])
