"""The filter forms of harness/project/suites.yaml (`filter:`, read only by
`gate.py --suite NAME --filter WORDS`) and harness/project/tools/filter_run.py, which they run.

The registry checks read suites.yaml and run nothing. The run checks build fixture tests
for each runner family in a temporary folder (a Cargo crate, a node --test file and a
unittest module) and run filter_run.py on them with the real runners: cargo, node and
Python. No station, radio or network.
"""
import copy
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

import yaml

# The checkout: three folders above harness/project/tests/.
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
REGISTRY = os.path.join(ROOT, "harness", "project", "suites.yaml")
HELPER = os.path.join(ROOT, "harness", "project", "tools", "filter_run.py")
HELPER_ARG = "harness/project/tools/filter_run.py"
PLACEHOLDER = "PLACEHOLDERWORD"
MARKERS = ("@run", "@libtest", "@node", "@unittest")

WITH_FORM = {
    "wstx-rust", "wstx-rust-decoder", "decoder-correctness", "live-station-browser", "live-station-latency",
    "protocol", "protocol-thin", "profiles", "recording-storage", "recording-display", "recording-thin",
    "recording-fixtures", "model-values", "test-tools", "native-flex", "operating-layout", "mcp",
    "radio-selection",
    "sysml-documentation", "sysml-tools", "sysml-architecture-context", "sysml-architecture",
    "sysml-equivalence-tests", "deploy-tooling", "test-bench", "fortran-reference-tools", "simulator-fixtures",
}
WITHOUT_FORM = {
    "live-receive-integration", "contact-browser", "radio-selection-thin",
    "sysml-equivalence", "source-model-traces", "decoder-quality",
}
REASON = "# No filter form:"


def left_out(step):
    """True for a step of a run that selects no tests and that a form leaves out."""
    return (step == ["python", "tools/sysml.py", "check"]
            or "--verify-manifest" in step
            or step == ["python", "tools/test/python/independent-vector-tool/test_cache.py"])


def entry_blocks(text):
    """{suite: the lines of its entry} of the registry text."""
    blocks, name = {}, None
    for line in text.splitlines():
        m = re.match(r"- suite: (\S+)", line)
        if m:
            name = m.group(1)
            blocks[name] = []
        elif line and not line.startswith(" "):
            name = None
        elif name:
            blocks[name].append(line)
    return blocks


def set_findings(rows, text):
    """The differences between the suites with and without a form and the lists above."""
    have = {r["suite"] for r in rows if "filter" in r}
    lack = {r["suite"] for r in rows if "filter" not in r}
    found = []
    if have != WITH_FORM:
        found.append(f"with a form: {sorted(have ^ WITH_FORM)} differ")
    if lack != WITHOUT_FORM:
        found.append(f"without a form: {sorted(lack ^ WITHOUT_FORM)} differ")
    blocks = entry_blocks(text)
    for name in sorted(lack):
        if not any(line.strip().startswith(REASON) for line in blocks.get(name, [])):
            found.append(f"{name}: no `{REASON}` reason comment in its entry")
    return found


def split_steps(tokens):
    steps, cur = [], []
    for t in tokens:
        if t == "&&":
            steps.append(cur)
            cur = []
        else:
            cur.append(t)
    return steps + [cur]


def step_findings(row):
    """What the suite's form runs that its run does not, or leaves out that it runs."""
    name, form = row["suite"], row["filter"]
    if form.count("{filter}") != 1:
        return [f"{name}: {{filter}} must stand once in the form"]
    run_steps = split_steps(shlex.split(row["run"]))
    segments = split_steps(shlex.split(form.replace("{filter}", PLACEHOLDER)))
    helper = segments[-1]
    if helper[:4] != ["python", HELPER_ARG, name, PLACEHOLDER] or len(helper) < 5 or helper[4] not in MARKERS:
        return [f"{name}: the form must end in `python {HELPER_ARG} {name} {{filter}} @<step> ...`"]
    steps, cur = [], None
    for t in helper[4:]:
        if t in MARKERS:
            cur = [t]
            steps.append(cur)
        else:
            cur.append(t)
    found = []
    for marker, *argv in steps:
        test_runner = (argv[:2] == ["cargo", "test"], argv[:1] == ["node"] and "--test" in argv,
                       argv[:3] == ["python", "-m", "unittest"])
        expected = {"@libtest": test_runner[0], "@node": test_runner[1], "@unittest": test_runner[2],
                    "@run": not any(test_runner)}[marker]
        if not expected:
            found.append(f"{name}: {marker} does not fit its command {shlex.join(argv)}")
    formed = segments[:-1] + [argv for _, *argv in steps]
    kept = [s for s in run_steps if not left_out(s)]
    if formed != kept:
        found.append(f"{name}: the form's steps {formed} are not the run's {kept}")
    return found


def load():
    with open(REGISTRY, encoding="utf-8") as f:
        text = f.read()
    return yaml.safe_load(text), text


class Registry(unittest.TestCase):
    def setUp(self):
        self.rows, self.text = load()

    def row(self, rows, name):
        return next(r for r in rows if r["suite"] == name)

    def test_the_suites_with_a_form_are_those_listed_and_the_others_give_their_reason(self):
        self.assertEqual(set_findings(self.rows, self.text), [])

    def test_a_suite_without_a_form_that_gains_one_fails_the_check(self):
        rows = copy.deepcopy(self.rows)
        self.row(rows, "live-receive-integration")["filter"] = "python x.py {filter}"
        self.assertNotEqual(set_findings(rows, self.text), [])

    def test_a_suite_with_a_form_that_loses_it_fails_the_check(self):
        rows = copy.deepcopy(self.rows)
        del self.row(rows, "protocol")["filter"]
        self.assertNotEqual(set_findings(rows, self.text), [])

    def test_a_suite_without_a_form_and_without_its_reason_fails_the_check(self):
        text = self.text.replace("  # No filter form: the run is a model check with no tests to select.\n", "")
        self.assertNotEqual(set_findings(self.rows, text), [])

    def test_each_form_runs_exactly_the_steps_of_its_run(self):
        for row in self.rows:
            if "filter" in row:
                with self.subTest(suite=row["suite"]):
                    self.assertEqual(step_findings(row), [])

    def test_a_form_that_drops_a_skip_of_its_run_fails(self):
        for name, skip in (("wstx-rust", "-- --skip decoder::"),
                           ("protocol", ' --test-skip-pattern="^TC-021-007|^a deferred client download'
                                        ' that holds station messages"')):
            row = copy.deepcopy(self.row(self.rows, name))
            self.assertIn(skip, row["filter"])
            row["filter"] = row["filter"].replace(skip, "")
            self.assertNotEqual(step_findings(row), [], name)

    def test_a_form_that_names_another_test_file_or_binary_fails(self):
        for name, old, new in (("profiles", "tests/profiles.test.cjs", "tests/communication.test.cjs"),
                               ("decoder-correctness", "--test decoder_signal", "--test audio_receive")):
            row = copy.deepcopy(self.row(self.rows, name))
            row["filter"] = row["filter"].replace(old, new)
            self.assertNotEqual(step_findings(row), [], name)

    def test_a_form_that_adds_a_second_name_pattern_fails(self):
        for name in ("protocol-thin", "recording-storage", "recording-thin"):
            row = copy.deepcopy(self.row(self.rows, name))
            row["filter"] = row["filter"].replace("--test-concurrency=1",
                                                  "--test-concurrency=1 --test-name-pattern=x", 1)
            self.assertNotEqual(step_findings(row), [], name)

    def test_a_step_of_the_run_that_selects_no_tests_is_left_out_only_where_listed(self):
        row = copy.deepcopy(self.row(self.rows, "profiles"))
        row["filter"] = row["filter"].replace("@run cargo build --workspace --locked ", "")
        self.assertNotEqual(step_findings(row), [])


LIB_RS = """
#[cfg(test)]
mod tests {
    #[test]
    fn alpha() {}
    #[test]
    fn bravo() {}
    #[test]
    fn charlie() {}
    #[test]
    fn delta_fails() {
        panic!("delta fails on purpose");
    }
}

#[cfg(test)]
mod other {
    #[test]
    fn alpha_elsewhere() {}
}
"""

NODE_TEST = """
const test = require('node:test');
const assert = require('node:assert');
test('alpha', () => {});
test('bravo', () => {});
test('charlie', () => {});
test('delta fails', () => { assert.fail('delta fails on purpose'); });
test('echo only in node', () => {});
test('foxtrot skipped', { skip: true }, () => {});
"""

# A file whose asynchronous before hook opens a handle that only its after hook closes, as
# the browser test files do with Chromium.
NODE_HOOKED = """
const {test, before, after} = require('node:test');
let timer;
before(async () => { await new Promise(r => setTimeout(r, 300)); timer = setInterval(() => {}, 1000); });
after(async () => { clearInterval(timer); });
test('golf with hooks', async () => {});
"""

UNITTEST = """
import unittest


class Fixture(unittest.TestCase):
    def test_alpha(self):
        pass

    def test_bravo(self):
        pass

    def test_charlie(self):
        pass

    def test_delta_fails(self):
        self.fail("delta fails on purpose")
"""


class Runs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix="filter-forms-")
        crate = os.path.join(cls.dir, "crate")
        os.makedirs(os.path.join(crate, "src"))
        with open(os.path.join(crate, "Cargo.toml"), "w", encoding="utf-8") as f:
            f.write('[package]\nname = "filter_fixture"\nversion = "0.1.0"\nedition = "2021"\n\n[workspace]\n')
        with open(os.path.join(crate, "src", "lib.rs"), "w", encoding="utf-8") as f:
            f.write(LIB_RS)
        with open(os.path.join(cls.dir, "fixture.test.cjs"), "w", encoding="utf-8") as f:
            f.write(NODE_TEST)
        cls.hooked = os.path.join(cls.dir, "hooked.test.cjs")
        with open(cls.hooked, "w", encoding="utf-8") as f:
            f.write(NODE_HOOKED)
        cls.py = os.path.join(cls.dir, "py")
        os.makedirs(cls.py)
        with open(os.path.join(cls.py, "test_fixture.py"), "w", encoding="utf-8") as f:
            f.write(textwrap.dedent(UNITTEST))
        cls.env = {**os.environ, "CARGO_TARGET_DIR": os.path.join(cls.dir, "target")}
        cls.libtest = ["@libtest", "cargo", "test", "--manifest-path", os.path.join(crate, "Cargo.toml"), "--lib"]
        cls.node = ["@node", "node", "--test", "--test-concurrency=1", os.path.join(cls.dir, "fixture.test.cjs")]
        cls.unittest = ["@unittest", sys.executable, "-m", "unittest", "discover", "-s", cls.py,
                        "-p", "test_fixture.py", "-v"]
        # The fixture crate compiles once here, not inside the timed assertions.
        subprocess.run(["cargo", "test", "--manifest-path", os.path.join(crate, "Cargo.toml"), "--lib", "--no-run"],
                       env=cls.env, capture_output=True, check=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir, ignore_errors=True)

    def run_helper(self, words, *steps):
        argv = [sys.executable, HELPER, "fixture", *words]
        for step in steps:
            argv += step
        r = subprocess.run(argv, env=self.env, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=300)
        return r.returncode, r.stdout, r.stderr

    def family(self, name):
        return {"libtest": self.libtest, "node": self.node, "unittest": self.unittest}[name]

    def ran(self, family, out, test):
        return {"libtest": f"test tests::{test} ... ok" in out,
                "node": re.search(rf"✔ {test} \(", out) is not None,
                "unittest": f"test_{test} (" in out and "... ok" in out.split(f"test_{test} (", 1)[1].splitlines()[0]
                }[family]

    def test_two_words_run_the_two_tests_they_name_and_not_the_third(self):
        for family in ("libtest", "node", "unittest"):
            with self.subTest(family=family):
                rc, out, err = self.run_helper(["alpha", "bravo"], self.family(family))
                self.assertEqual(rc, 0, out + err)
                self.assertTrue(self.ran(family, out, "alpha"), out)
                self.assertTrue(self.ran(family, out, "bravo"), out)
                self.assertNotIn("charlie", out)
                self.assertNotIn("delta", out)

    def test_a_word_that_selects_no_test_is_red_in_every_runner_family(self):
        for family in ("libtest", "node", "unittest"):
            with self.subTest(family=family):
                rc, out, err = self.run_helper(["zulu"], self.family(family))
                self.assertNotEqual(rc, 0, out + err)
                self.assertIn("filter_run: fixture: no test selected by --filter zulu", err)

    def test_a_skipped_test_is_no_test_that_ran(self):
        rc, out, err = self.run_helper(["foxtrot"], self.node)
        self.assertNotEqual(rc, 0, out + err)
        self.assertIn("no test selected", err)

    def test_a_word_that_matches_in_one_step_of_two_passes(self):
        rc, out, err = self.run_helper(["echo"], self.libtest, self.node)
        self.assertEqual(rc, 0, out + err)
        self.assertIn("filter_run: fixture: 1 test(s) ran for --filter echo", out)

    def test_a_word_that_selects_a_failing_test_is_red_and_shows_its_failure(self):
        for family in ("libtest", "node", "unittest"):
            with self.subTest(family=family):
                rc, out, err = self.run_helper(["delta"], self.family(family))
                self.assertNotEqual(rc, 0, out + err)
                self.assertIn("delta fails on purpose", out)
                self.assertNotIn("no test selected", err)

    def test_a_word_narrows_a_cargo_test_name_filter_and_never_widens_it(self):
        rc, out, err = self.run_helper(["alpha"], self.libtest + ["tests::"])
        self.assertEqual(rc, 0, out + err)
        self.assertIn("test tests::alpha ... ok", out)
        self.assertNotIn("test other::alpha_elsewhere ... ok", out)
        rc, out, err = self.run_helper(["alpha_elsewhere"], self.libtest + ["tests::"])
        self.assertNotEqual(rc, 0, out + err)
        self.assertIn("no test selected", err)

    def test_a_word_narrows_a_node_name_pattern_and_never_widens_it(self):
        step = self.node[:4] + ["--test-name-pattern=^(alpha|charlie)"] + self.node[4:]
        rc, out, err = self.run_helper(["alpha|bravo"], step)
        self.assertEqual(rc, 0, out + err)
        self.assertTrue(self.ran("node", out, "alpha"), out)
        self.assertFalse(self.ran("node", out, "bravo"), out)
        self.assertNotIn("charlie", out)

    def test_a_node_file_whose_hooks_open_a_handle_ends_when_no_test_of_it_matches(self):
        for words, rc_expected in ((["alpha"], 0), (["zulu"], 1)):
            with self.subTest(words=words):
                t0 = time.monotonic()
                rc, out, err = self.run_helper(words, self.node + [self.hooked])
                self.assertEqual(rc, rc_expected, out + err)
                self.assertLess(time.monotonic() - t0, 60, out + err)

    def test_a_skip_of_the_step_holds_under_a_word(self):
        rc, out, err = self.run_helper(["alpha", "bravo"], self.libtest + ["--", "--skip", "bravo"])
        self.assertEqual(rc, 0, out + err)
        self.assertNotIn("tests::bravo", out)
        rc, out, err = self.run_helper(["alpha", "bravo"], self.node[:4] + ["--test-skip-pattern=^bravo"] + self.node[4:])
        self.assertEqual(rc, 0, out + err)
        self.assertTrue(self.ran("node", out, "alpha"), out)
        self.assertFalse(self.ran("node", out, "bravo"), out)

    def test_a_form_without_words_or_with_an_unknown_cargo_option_is_refused(self):
        rc, _, err = self.run_helper([], self.node)
        self.assertEqual(rc, 2)
        self.assertIn("no filter word", err)
        rc, _, err = self.run_helper(["alpha"], self.libtest[:3] + ["--mystery", "x"])
        self.assertEqual(rc, 2)
        self.assertIn("unknown cargo option --mystery", err)


if __name__ == "__main__":
    unittest.main()
