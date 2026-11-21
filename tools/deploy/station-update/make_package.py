"""Deploy one pushed commit: build or reuse its station package, then run the package's own install.

usage (Git Bash; the script itself is read from the commit, never from a working folder):
  set -o pipefail; git -C D:/Github/wsjtx-rust show <commit>:tools/deploy/station-update/make_package.py | python - <commit> [--dry-run]

The commit C must be on GitHub master. A push is one line `<old>..<new>  HEAD -> master` in a
merge-queue log under <git common dir>/harness-parallel/queue/logs/; its verdict is the log's
last line beginning with `harness gate`. A green push has the verdict `harness gate: <n>
suites, green`, a harness push one beginning with `harness gate: harness change`, and any
other push line is an other push. C's chain is walked back from the push whose new tip is C,
then the push whose new tip is that push's old tip, up to the first green push. C is deployed
when (a) a green push has C as its new tip; its log is the package's push-gate log; or (b)
the chain is one or more harness pushes followed by a green push whose new tip G is an
ancestor of C, and every path of `git diff --no-renames --name-only G C` is a harness path
of G: the harness checkout (the one submodule path that .gitmodules at G names and that is a
gitlink in G's tree, none when there are none or several), harness/project, and the
`harness_paths` of harness/project/config.yaml at G. In case (b) the build is C's, G's log is
the gate receipt, and gates.json adds `gated_commit` (G) and `harness_push_logs` (a copy
harness-push-<n>.log of each harness push's log, newest first).

It refuses with exit 1 before any folder is created or removed: a commit not on GitHub
master; a commit of the walk that no push has as its new tip (C itself, a commit inside a
push, or the old tip of a harness push); a commit of the walk that more than one log shows
pushed; an other push in the chain; a G that is not an ancestor of C; and a diff from G to C
with paths that are no harness paths (the first 10 named). A log without a push line is
ignored.

The package lives in
<git common dir>/harness-parallel/resources/station-update/packages/<ver>/{package/, deploy/,
manifest.json, gates.json, gate-receipt-<ver>.log}, never in a working tree. A leftover
build folder <BUILD_ROOT>/<ver> of a stopped run is removed first. When the package folder
holds the commit's package it is reused; when its manifest names another commit it is
refused; when it holds no package of any commit (a failed or stopped attempt) it is removed.
When it is absent, the commit is exported with `git archive` into a clean directory on C: and
built there with `cargo build --release --locked -p wstx-rust`; a build that fails removes
both folders and prints the last lines of cargo's output. COPYING and every file under
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

import yaml

REPO = r"D:\Github\wsjtx-rust"
BUILD_ROOT = r"C:\wstx-build"
MECHANISM_DIR = "tools/deploy/station-update"
MECHANISM_FILES = ("tools/deploy/agent-client.ps1", "tools/deploy/station-probe.ps1", "tools/deploy/live-page-check.ps1")
POWERSHELL = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), r"System32\WindowsPowerShell\v1.0\powershell.exe")
USAGE = "usage: make_package.py <commit> [--dry-run]"
VERDICT = re.compile(r"harness gate: \d+ suites, green")
HARNESS_VERDICT = "harness gate: harness change"
PUSH = re.compile(r"^\s*([0-9a-f]+)\.\.([0-9a-f]+)  HEAD -> master\s*$", re.M)
# The project's part of the harness and its configuration, as gate.py names them.
CONFIG_DIR = "harness/project"
CONFIG_FILE = CONFIG_DIR + "/config.yaml"
LISTED = 10


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


def pushes(repo):
    """Every push of the merge-queue logs: (log path, kind, old, new), kind being green, harness
    or other by the log's verdict. A log without a push line holds no push."""
    logs = os.path.join(common_dir(repo), "harness-parallel", "queue", "logs")
    found = []
    for name in sorted(os.listdir(logs)) if os.path.isdir(logs) else []:
        path = os.path.normpath(os.path.join(logs, name))
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        verdicts = [line for line in text.splitlines() if line.startswith("harness gate")]
        verdict = verdicts[-1] if verdicts else ""
        kind = ("green" if VERDICT.match(verdict) else
                "harness" if verdict.startswith(HARNESS_VERDICT) else "other")
        found += [(path, kind, old, new) for old, new in PUSH.findall(text)]
    return found


def resolve(repo, short):
    """The full commit a push line's short hash names, or None."""
    r = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "-q", short + "^{commit}"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def chain(repo, commit):
    """The push-gate log of the green push the commit rests on, its new tip G and the harness
    pushes walked from the commit back to it [(tip, log)], newest first; exits with the
    reason when the walk refuses."""
    found = pushes(repo)
    harness, x, seen = [], commit, set()
    while True:
        logs = sorted({path for path, _, _, new in found if x and x.startswith(new)})
        if not logs or x in seen:
            sys.exit(f"refused: no push-gate log shows the push of {x[:9]} to master")
        if len(logs) > 1:
            sys.exit(f"refused: {len(logs)} push-gate logs show the push of {x[:9]}: "
                     + ", ".join(os.path.basename(p) for p in logs))
        seen.add(x)
        log, kind, old = next((p, k, o) for p, k, o, new in found if p == logs[0] and x.startswith(new))
        if kind == "green":
            return log, x, harness
        if kind != "harness":
            sys.exit(f"refused: the push of {x[:9]} shows neither a green gate nor a harness change: "
                     + os.path.basename(log))
        harness.append((x, log))
        x = resolve(repo, old) or old


def declared_path(x):
    """A `harness_paths` entry as git writes paths, or None when it is no valid entry (gate.py
    declared_path)."""
    if not isinstance(x, str) or x != x.strip() or "\\" in x or x.startswith("/"):
        return None
    parts = x.rstrip("/").split("/")
    return None if not x.rstrip("/") or any(q in ("", ".", "..") for q in parts) else "/".join(parts)


def declared(repo, rev):
    """The `harness_paths` of the configuration at rev; an unreadable configuration or an
    invalid declaration declares none (gate.py declared and harness_paths)."""
    r = subprocess.run(["git", "-C", repo, "show", f"{rev}:{CONFIG_FILE}"], capture_output=True)
    try:
        config = (yaml.safe_load(r.stdout.decode("utf-8")) if r.returncode == 0 else None) or {}
    except (yaml.YAMLError, UnicodeError):
        return []
    extra = (config.get("harness_paths") or []) if isinstance(config, dict) else []
    paths = [declared_path(x) for x in extra] if isinstance(extra, list) else [None]
    return [] if None in paths else paths


def harness_checkout(repo, rev):
    """The harness checkout at rev: the one submodule path that .gitmodules at rev names and
    that is a gitlink in rev's tree, or None when there are none or several."""
    r = subprocess.run(["git", "-C", repo, "config", "-z", "--blob", f"{rev}:.gitmodules", "--get-regexp",
                        r"^submodule\..*\.path$"], capture_output=True, text=True)
    named = [entry.split("\n", 1)[1] for entry in r.stdout.split("\0") if "\n" in entry] if r.returncode == 0 else []
    links = []
    for path in dict.fromkeys(named):
        entry = git(repo, "ls-tree", rev, "--", path)
        if entry.startswith("160000 ") and entry.endswith("\t" + path):
            links.append(path)
    return links[0] if len(links) == 1 else None


def harness_paths(repo, rev):
    """The harness paths of rev, as gate.py classifies a push against its base rev."""
    own = harness_checkout(repo, rev)
    return ([own] if own else []) + [CONFIG_DIR, *declared(repo, rev)]


def is_harness_path(path, prefixes):
    return any(path == x or path.startswith(x + "/") for x in prefixes)


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


def manifest_commit(out):
    """The commit the folder's manifest names, or None when the folder holds no package of any
    commit: no manifest.json, or one that is not a JSON object with a string source_commit."""
    try:
        with open(os.path.join(out, "manifest.json"), encoding="utf-8") as f:
            manifest = json.load(f)
    except (OSError, ValueError):
        return None
    named = manifest.get("source_commit") if isinstance(manifest, dict) else None
    return named if isinstance(named, str) else None


def remove_leftover(path):
    """Remove what a failed or stopped run left at path, or refuse when it cannot be removed."""
    try:
        shutil.rmtree(path)
    except OSError as e:
        sys.exit(f"refused: the leftover {path} cannot be removed: {e}")
    print(f"removed the leftover {path}", flush=True)


def build(commit, ver, out, gate_log, gated=None, harness=()):
    """Build the package of the commit into out from its git archive export. A commit that
    rests on its green-gated ancestor `gated` carries that commit and the logs of the harness
    pushes [(tip, log)] in gates.json."""
    src = os.path.join(BUILD_ROOT, ver, "src")
    target = os.path.join(BUILD_ROOT, ver, "target")
    export(REPO, commit, src)
    # The station reports this commit itself (x-wstx-source-commit on GET /).
    env = dict(os.environ, CARGO_TARGET_DIR=target, CARGO_BUILD_JOBS="2", WSTX_SOURCE_COMMIT=commit)
    result = subprocess.run(["cargo", "build", "--release", "--locked", "-p", "wstx-rust"], cwd=src, env=env,
                            capture_output=True, encoding="utf-8", errors="replace")
    log = result.stdout + result.stderr
    if result.returncode != 0:
        # The run's own output is the failure's evidence: the last 10 lines of cargo, then the
        # failure line last, all on stdout.
        sys.stdout.reconfigure(errors="replace")
        for line in log.splitlines()[-10:]:
            print(line)
        print(f"release build failed (cargo exit {result.returncode})", flush=True)
        sys.exit(1)
    os.makedirs(out)
    with open(os.path.join(out, "build.log"), "w", encoding="utf-8") as f:
        f.write(log)
    exe = os.path.join(target, "release", "wstx-rust.exe")

    package = os.path.join(out, "package")
    # The licence files come from the exported commit itself: COPYING and every file under
    # server/third-party (notices travel with the copies, e.g. cty/LICENSE for cty.dat).
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
    }
    if gated:
        gates["gated_commit"] = gated
        gates["harness_push_logs"] = []
        for n, (_, log) in enumerate(harness, 1):
            copy = os.path.join(out, f"harness-push-{n}.log")
            shutil.copyfile(log, copy)
            gates["harness_push_logs"].append({"path": copy, "sha256": sha256(copy)})
    gates |= {
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
    gate_log, gated, harness = chain(REPO, commit)
    if harness:
        if subprocess.run(["git", "-C", REPO, "merge-base", "--is-ancestor", gated, commit]).returncode != 0:
            sys.exit(f"refused: {gated[:9]} is not an ancestor of {ver}")
        prefixes = harness_paths(REPO, gated)
        diff = git(REPO, "diff", "--no-renames", "--name-only", "-z", gated, commit).split("\0")
        other = [path for path in diff if path and not is_harness_path(path, prefixes)]
        if other:
            more = f" and {len(other) - LISTED} more" if len(other) > LISTED else ""
            sys.exit(f"refused: {ver} rests on {gated[:9]}, but these paths are no harness paths: "
                     + ", ".join(other[:LISTED]) + more)
    print(f"push-gate log: {gate_log}", flush=True)
    if harness:
        print(f"rests on {gated[:9]}: harness-only pushes " + " ".join(tip[:9] for tip, _ in harness), flush=True)

    out = os.path.normpath(os.path.join(packages_root(REPO), ver))
    build_dir = os.path.join(BUILD_ROOT, ver)
    if os.path.exists(build_dir):
        remove_leftover(build_dir)
    if os.path.exists(out) and manifest_commit(out) is None:
        remove_leftover(out)
    if not os.path.exists(out):
        try:
            build(commit, ver, out, gate_log, gated if harness else None, harness)
        except BaseException:
            # A build that ends without its manifest leaves neither folder behind.
            shutil.rmtree(out, ignore_errors=True)
            shutil.rmtree(build_dir, ignore_errors=True)
            raise
        print(f"package {ver}: built {out}", flush=True)
    elif manifest_commit(out) == commit:
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
