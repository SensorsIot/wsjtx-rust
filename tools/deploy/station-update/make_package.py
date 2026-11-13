"""Build a station package for one pushed commit.

usage (Git Bash; the script itself is read from the commit, never from a working folder):
  git -C D:/Github/wsjtx-rust show <commit>:tools/deploy/station-update/make_package.py | python - <commit> <push-gate-log>

Exports the commit with `git archive` into a clean directory on C:, builds
`cargo build --release --locked -p wstx-rust` there, and writes
<git common dir>/harness-parallel/resources/station-update/packages/<ver>/{package/, deploy/,
manifest.json, gates.json, gate-receipt-<ver>.log}, never into a working tree. The gate log
must show the green push gate that published exactly this commit to master. COPYING and
every file under server/third-party are copied from the exported commit into package/. The
deploy mechanism files (every file under tools/deploy/station-update/ and MECHANISM_FILES)
are copied from the export into deploy/<their path>; the manifest lists their SHA-256, and
station-update.ps1 runs from there.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile

REPO = r"D:\Github\wsjtx-rust"
BUILD_ROOT = r"C:\wstx-build"
MECHANISM_DIR = "tools/deploy/station-update"
MECHANISM_FILES = ("tools/deploy/agent-client.ps1", "tools/deploy/station-probe.ps1", "tools/deploy/live-page-check.ps1")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, text=True).stdout.strip()


def packages_root(repo):
    """The shared packages folder of the repository, outside every working tree."""
    common = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    return os.path.join(common, "harness-parallel", "resources", "station-update", "packages")


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


def main():
    commit_arg, gate_log = sys.argv[1], sys.argv[2]
    commit = git(REPO, "rev-parse", commit_arg + "^{commit}")
    ver = commit[:9]
    git(REPO, "fetch", "-q", "origin", "master")
    subprocess.run(["git", "-C", REPO, "merge-base", "--is-ancestor", commit, "FETCH_HEAD"], check=True)
    log = open(gate_log, encoding="utf-8", errors="replace").read()
    if "suites, green" not in log or f"..{ver}  HEAD -> master" not in log:
        sys.exit(f"{gate_log} does not show a green push of {ver} to master")

    out = os.path.join(packages_root(REPO), ver)
    if os.path.exists(out):
        sys.exit(f"{out} already exists")
    src = os.path.join(BUILD_ROOT, ver, "src")
    target = os.path.join(BUILD_ROOT, ver, "target")
    export(REPO, commit, src)
    # The station reports this commit itself (x-wstx-source-commit on GET /, #33).
    env = dict(os.environ, CARGO_TARGET_DIR=target, CARGO_BUILD_JOBS="2", WSTX_SOURCE_COMMIT=commit)
    build = subprocess.run(["cargo", "build", "--release", "--locked", "-p", "wstx-rust"], cwd=src, env=env,
                           capture_output=True, text=True)
    os.makedirs(out)
    with open(os.path.join(out, "build.log"), "w", encoding="utf-8") as f:
        f.write(build.stdout + build.stderr)
    if build.returncode != 0:
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
    station_update = os.path.join(out, "deploy", "tools", "deploy", "station-update", "station-update.ps1")
    print(f"package {ver}: exe {exe_hash[:12]} ({os.path.getsize(os.path.join(package, 'wstx-rust.exe'))} bytes), "
          f"{len(files)} files, {len(deploy_files)} mechanism files -> {out}")
    print(f"install: powershell -NoProfile -ExecutionPolicy Bypass -File {station_update} -Manifest {os.path.join(out, 'manifest.json')}")


if __name__ == "__main__":
    main()
