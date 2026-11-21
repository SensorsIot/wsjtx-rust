#!/usr/bin/env python3
"""The run of a suite's filter form (harness/project/suites.yaml `filter:`, read only by
`gate.py --suite NAME --filter WORDS`): the suite's own runner steps, each narrowed to the
tests that match a filter word, and RED when no step ran any test.

    filter_run.py SUITE WORD... STEP...
    STEP: @run ARGV... | @libtest ARGV... | @node ARGV... | @unittest ARGV...

The words are those of --filter; the gate puts them, each quoted, in place of `{filter}`.
Each step is a command of the suite's `run`, copied unchanged; the helper adds the
selection. A test runs when it matches any word:

- `@libtest` (a `cargo test` command): a word is a substring of the test path
  (`module::test_name`). Without a name filter of its own the words are libtest's filters.
  With one (a positional TESTNAME such as `decoder::`), the tests that command selects are
  listed (`--list`), those holding a word are kept and run by their exact names, so a word
  narrows the command's own selection and never widens it. Every `--skip`, `--exact` and
  `--ignored` of the command holds.
- `@node` (a `node --test` command): a word is a JavaScript regular expression on the test
  name. A command without `--test-name-pattern` gets the words as its pattern; one with it
  gets a single pattern that matches a name only when the command's own pattern and a word
  both match it (a second `--test-name-pattern` would widen the selection). Its
  `--test-skip-pattern` holds. The tests that ran are counted by node_test_count.mjs. The step
  runs with `--test-force-exit`: in a file none of whose tests match, node runs the `after`
  hooks before an asynchronous `before` hook has finished, so what that hook opens (a
  browser, a server) is never closed and the file would never end.
- `@unittest` (a `python -m unittest` command): a word is one `-k` (a substring of
  `module.Class.method`, or an fnmatch pattern when it holds `*`). Exit 5, "NO TESTS RAN",
  of a step that ran no test is no failure by itself.
- `@run`: a command that selects nothing (a build); it runs as written.

The steps run in order and the first that fails ends the run with its exit code. When
every step passed and none ran a test (a skipped test does not count), the run prints a line
naming the suite and the words and exits 1. Otherwise it exits 0.
"""
import os
import re
import shlex
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

MARKERS = ("@run", "@libtest", "@node", "@unittest")
NO_TESTS_RAN = 5
READ_GRACE = 5   # seconds the output is still read after the command has exited
# cargo options that take a value: a word after one is that value, not a test name filter.
CARGO_VALUE = {"--bin", "--test", "--example", "--bench", "-p", "--package", "--config", "--profile",
               "--features", "-F", "--target", "--message-format", "--manifest-path", "-j", "--jobs",
               "--target-dir", "--exclude", "--color", "-Z"}
CARGO_FLAG = {"--release", "--locked", "--frozen", "--offline", "--workspace", "--all", "--lib", "--bins",
              "--examples", "--tests", "--benches", "--all-targets", "--doc", "--no-run", "--no-fail-fast",
              "--all-features", "--no-default-features", "-q", "--quiet", "-v", "--verbose"}
# Under Windows a command line holds at most 32767 characters; exact test names are run in
# batches well below it.
BATCH_CHARS = 8000
LIBTEST_RESULT = re.compile(r"test result: \w+\. (\d+) passed; (\d+) failed;")
UNITTEST_RAN = re.compile(r"^Ran (\d+) tests? in ", re.M)
UNITTEST_SKIPPED = re.compile(r"^(?:OK|FAILED) \(.*?\bskipped=(\d+)", re.M)


class Refused(Exception):
    """A form the helper cannot run as written (exit 2)."""


def parse(argv):
    """(suite, words, [(marker, argv)]) of the command line."""
    if not argv:
        raise Refused("no suite named")
    suite, rest = argv[0], argv[1:]
    starts = [i for i, a in enumerate(rest) if a in MARKERS]
    if not starts:
        raise Refused(f"{suite}: no step")
    words = rest[:starts[0]]
    if not words:
        raise Refused(f"{suite}: no filter word")
    steps = []
    for n, i in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(rest)
        if i + 1 == end:
            raise Refused(f"{suite}: {rest[i]} without a command")
        steps.append((rest[i], rest[i + 1:end]))
    return suite, words, steps


def stream(argv):
    """(exit code, output text) of one command, its output shown as it comes. A process the
    command started and left running may hold the output pipe open: the output is read until
    the command has exited and READ_GRACE seconds more, not until the pipe closes."""
    out = sys.stdout.buffer
    sys.stdout.flush()
    try:
        proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except OSError as e:
        print(f"filter_run: cannot start {argv[0]}: {e}", file=sys.stderr)
        return 127, ""
    chunks = []

    def read():
        for raw in proc.stdout:
            out.write(raw)
            out.flush()
            chunks.append(raw)

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    rc = proc.wait()
    reader.join(READ_GRACE)
    return rc, b"".join(chunks).decode("utf-8", "replace")


def cargo_parts(argv):
    """(cargo arguments without test name filters, test name filters, libtest arguments)."""
    if Path(argv[0]).stem != "cargo" or argv[1:2] != ["test"]:
        raise Refused(f"@libtest needs a cargo test command: {shlex.join(argv)}")
    split = argv.index("--") if "--" in argv else len(argv)
    head, libargs = argv[:split], argv[split + 1:]
    cargo, names = head[:2], []
    i = 2
    while i < len(head):
        a = head[i]
        if a in CARGO_VALUE:
            cargo += head[i:i + 2]
            i += 2
            continue
        if a.startswith("-"):
            if a not in CARGO_FLAG and not ("=" in a and a.split("=", 1)[0] in CARGO_VALUE):
                raise Refused(f"@libtest: unknown cargo option {a}")
            cargo.append(a)
        else:
            names.append(a)
        i += 1
    return cargo, names, libargs


def libtest_count(text):
    return sum(int(p) + int(f) for p, f in LIBTEST_RESULT.findall(text))


def run_libtest(argv, words):
    cargo, names, libargs = cargo_parts(argv)
    if not names:
        rc, text = stream(cargo + ["--"] + libargs + words)
        return rc, libtest_count(text)
    rc, text = stream(cargo + ["--"] + libargs + names + ["--list"])
    if rc:
        return rc, 0
    listed = []
    for line in text.splitlines():
        if line.endswith(": test"):
            name = line[:-len(": test")]
            if any(w in name for w in words) and name not in listed:
                listed.append(name)
    base = cargo + ["--"] + [a for a in libargs if a != "--exact"] + ["--exact"]
    ran, batch = 0, []
    for name in listed + [None]:
        if name is not None and sum(len(n) + 1 for n in batch) + len(name) < BATCH_CHARS:
            batch.append(name)
            continue
        if batch:
            rc, text = stream(base + batch)
            ran += libtest_count(text)
            if rc:
                return rc, ran
        batch = [name]
    return 0, ran


def node_pattern(words, own):
    """The one --test-name-pattern of a node step: a word, and the step's own pattern if any."""
    word = "|".join(f"(?:{w})" for w in words)
    if not own:
        return word
    mine = "|".join(f"(?:{p})" for p in own)
    return f"^(?=[\\s\\S]*(?:{word}))(?=[\\s\\S]*?(?:{mine}))"


def run_node(argv, words):
    if "--test" not in argv:
        raise Refused(f"@node needs a node --test command: {shlex.join(argv)}")
    if "--test-name-pattern" in argv:
        raise Refused("@node: write --test-name-pattern=PATTERN as one word")
    own = [a.split("=", 1)[1] for a in argv if a.startswith("--test-name-pattern=")]
    rest = [a for a in argv if not a.startswith("--test-name-pattern=")]
    fd, counted = tempfile.mkstemp(prefix="filter-run-", suffix=".txt")
    os.close(fd)
    try:
        reporter = Path(__file__).with_name("node_test_count.mjs").resolve().as_uri()
        at = rest.index("--test") + 1
        rest[at:at] = ["--test-name-pattern=" + node_pattern(words, own), "--test-force-exit",
                       "--test-reporter=spec", "--test-reporter-destination=stdout",
                       "--test-reporter=" + reporter, "--test-reporter-destination=" + counted]
        rc, _ = stream(rest)
        lines = Path(counted).read_text(encoding="utf-8", errors="replace").splitlines()
        return rc, sum(1 for line in lines if line.strip())
    finally:
        os.unlink(counted)


def run_unittest(argv, words):
    rc, text = stream(argv + [a for w in words for a in ("-k", w)])
    ran = sum(int(n) for n in UNITTEST_RAN.findall(text))
    skipped = sum(int(n) for n in UNITTEST_SKIPPED.findall(text))
    if rc == NO_TESTS_RAN and ran == 0:
        rc = 0
    return rc, ran - skipped


def run_plain(argv, words):
    rc, _ = stream(argv)
    return rc, 0


RUNNERS = {"@run": run_plain, "@libtest": run_libtest, "@node": run_node, "@unittest": run_unittest}


def main(argv=None):
    try:
        suite, words, steps = parse(sys.argv[1:] if argv is None else argv)
        for marker, command in steps:       # a malformed step refuses before any runs
            if marker == "@libtest":
                cargo_parts(command)
        ran = 0
        for marker, command in steps:
            rc, n = RUNNERS[marker](command, words)
            ran += n
            if rc:
                print(f"filter_run: {suite}: step failed (exit {rc}): {shlex.join(command)}", file=sys.stderr)
                return rc
    except Refused as e:
        print(f"filter_run: {e}", file=sys.stderr)
        return 2
    shown = " ".join(shlex.quote(w) for w in words)
    if ran == 0:
        print(f"filter_run: {suite}: no test selected by --filter {shown}", file=sys.stderr)
        return 1
    print(f"filter_run: {suite}: {ran} test(s) ran for --filter {shown}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
