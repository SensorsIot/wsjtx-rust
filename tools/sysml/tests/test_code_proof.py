"""TR-23: the code proof listings `tests <rev>` and `traces <rev>`, their refusals, and
`traces` without a revision.

Each case builds a temporary git repository from hand-written fixtures and runs the tool as
a process whose repository is the fixture, in the fixture's folder, as the gate runs it. The
expected lines are written by hand. The cases on this repository read it and write nothing.
"""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
ROOT = TOOL.parents[1]
spec = importlib.util.spec_from_file_location("code_proof_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

# The tool as a process with the repository `argv[2]` as its root: its working tree holds the
# model, the FSD path the authority refuses and the oracle.
RUNNER = ("import importlib.util, sys\nfrom pathlib import Path\n"
          "spec = importlib.util.spec_from_file_location('sysml_tool', sys.argv[1])\n"
          "tool = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(tool)\n"
          "root = tool.ROOT = Path(sys.argv[2])\ntool.MODELS, tool.FSD = root / 'docs/sysml', root / 'docs/WSTX Rust FSD.md'\n"
          "tool.ORACLE = root / 'tools/sysml/architecture-oracle.json'\nraise SystemExit(tool.main(sys.argv[3:]))\n")


def environment(temporary=None) -> dict:
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    if temporary is not None:
        env.update(TMP=str(temporary), TEMP=str(temporary), TMPDIR=str(temporary))
    return env


def run(root: Path, *argv: str, temporary=None) -> tuple[int, list[str], str]:
    """(exit code, stdout lines, stderr with `\\n` line ends) of the tool on the repository `root`."""
    result = subprocess.run([sys.executable, "-c", RUNNER, str(TOOL), str(root), *argv], cwd=root,
                            capture_output=True, env=environment(temporary), timeout=900)
    return (result.returncode, result.stdout.decode("utf-8", "replace").splitlines(),
            result.stderr.decode("utf-8", "replace").replace("\r\n", "\n"))


class Repository:
    """A temporary git repository on `master`; `commit` writes a whole tree."""

    def __init__(self, folder: Path):
        self.root = folder
        folder.mkdir(parents=True, exist_ok=True)
        self.git("init", "-q", "-b", "master")

    def git(self, *args: str) -> str:
        env = environment()
        env.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        return subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(self.root), *args], check=True,
                              capture_output=True, text=True, env=env).stdout.strip()

    def write(self, files: dict):
        """The working tree holds exactly `files` (beside `.git`)."""
        for path in self.root.iterdir():
            if path.name != ".git":
                shutil.rmtree(path) if path.is_dir() else path.unlink()
        for key, text in files.items():
            target = self.root / key
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(text.encode("utf-8"))

    def commit(self, files: dict, message: str = "change") -> str:
        self.write(files)
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")


def edit(files: dict, key: str, old: str, new: str) -> dict:
    assert old in files[key], (key, old)
    return {**files, key: files[key].replace(old, new, 1)}


def moved(files: dict, old: str, new: str) -> dict:
    return {(new if key == old else key): text for key, text in files.items()}


# ---- The test inventory ----

RUST = "\n".join([
    "#[test]",
    "fn plain() {}",
    '#[tokio::test(flavor = "multi_thread", worker_threads = 2)]',
    "async fn threaded() {}",
    "#[tokio::test(start_paused = true)]",
    "async fn paused() {}",
    "#[test]",
    "#[ignore]",
    "fn ignored() {}",
    "#[tokio::test]",
    "pub async fn public_async() {}",
    "mod first {",
    "    #[test]",
    "    fn parses() {}",
    "}",
    "mod second {",
    "    #[test]",
    "    fn parses() {}",
    "}",
]) + "\n"
RUST_LINES = ["rust ignored", "rust parses", "rust parses", "rust paused", "rust plain", "rust public_async", "rust threaded"]
RUST_NEGATIVES = {
    "a line comment": ("server/src/n.rs", "// #[test]\nfn in_line_comment() {}\n"),
    "a block comment": ("server/src/n.rs", "/* #[test]\nfn in_block_comment() {} */\n"),
    "a string": ("server/src/n.rs", 'const S: &str = "#[test] fn in_string() {}";\n'),
    "a raw string": ("server/src/n.rs", 'const R: &str = r#"#[test] fn in_raw_string() {}"#;\n'),
    "a plain fn": ("server/src/n.rs", "fn plain_fn() {}\n"),
    "a file outside the source roots": ("tools/outside.rs", "#[test]\nfn outside() {}\n"),
}

NODE = "\n".join([
    "const test = require('node:test');",
    "const it = test;",
    "test('a', () => {});",
    'test("b \\"q\\"", () => {});',
    "for (const x of [1]) test(`c ${x}`, () => {});",
    "async function sub(t) { await t.test('d', () => {}); }",
    "it('e', () => {});",
    "test.skip('f', () => {});",
    "test.only('g', () => {});",
    "test.todo('h');",
]) + "\n"
NODE_LINES = ["node a", 'node b "q"', "node c ${x}", "node d", "node e", "node f", "node g", "node h"]
NODE_NEGATIVES = {
    "a line comment": ("tests/n.test.cjs", "// test('x1', () => {});\n"),
    "a block comment": ("tests/n.test.cjs", "/* test('x2', () => {}); */\n"),
    "a string": ("tests/n.test.cjs", "const s = \"test('x3', () => {})\";\n"),
    "a template text": ("tests/n.test.cjs", "const s = `test('x4', () => {})`;\n"),
    "a regular expression test": ("tests/n.test.cjs", "const s = 'b';\n/re/.test(s);\n"),
    "a RegExp test": ("tests/n.test.cjs", "const re = /re/, s = 'b';\nre.test(s);\n"),
    "a regular expression literal": ("tests/n.test.cjs", "const re = /test('x5')/;\n"),
    "describe": ("tests/n.test.cjs", "describe('y', () => {});\n"),
    "a file not named *.test.*": ("tests/helper.cjs", "test('z', () => {});\n"),
    "a file outside the source roots": ("tools/n.test.cjs", "test('w', () => {});\n"),
}

PYTHON = "\n".join([
    "import unittest",
    "",
    "",
    "def test_m():",
    "    def test_inner():",
    "        pass",
    "",
    "",
    "class K(unittest.TestCase):",
    "    def test_k(self):",
    "        pass",
    "",
    "    async def test_j(self):",
    "        pass",
    "",
    "",
    "def helper():",
    "    pass",
]) + "\n"
PYTHON_LINES = ["python K.test_j", "python K.test_k", "python test_m"]
HARNESS = "harness_paths:\n  - tools/gate/\n"
PYTHON_NEGATIVES = {
    "the model tool's own tests": ("tools/sysml/tests/test_b.py", "def test_b():\n    pass\n"),
    "a harness path": ("tools/gate/test_c.py", "def test_c():\n    pass\n"),
    "a file not named test_*.py": ("tools/other.py", "def test_d():\n    pass\n"),
}
INVENTORY = {"server/src/clock.rs": RUST, "tests/all.test.cjs": NODE, "tools/test_a.py": PYTHON,
             "harness/project/config.yaml": HARNESS}


class InventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory(prefix="sysml-proof-test-")
        cls.repository = Repository(Path(cls.folder.name) / "repo")

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def setUp(self):
        self.root = self.repository.root

    def inventory(self, revision: str) -> list[str]:
        code, lines, errors = run(self.root, "tests", revision)
        self.assertEqual((code, errors), (0, ""), lines)
        return lines

    def test_tv177_rust_lines(self):
        """TV-177 (TR-23): `#[test]`, both `#[tokio::test(...)]` forms, an ignored test, a `pub async
        fn` test and two `parses` in two modules give exactly their lines; a test attribute in a
        comment, a string or a raw string, a plain fn and a file outside the roots give none."""
        base = {"server/src/clock.rs": RUST}
        self.assertEqual(self.inventory(self.repository.commit(base)), RUST_LINES)
        for name, (key, text) in RUST_NEGATIVES.items():
            with self.subTest(name):
                self.assertEqual(self.inventory(self.repository.commit({**base, key: text})), RUST_LINES)

    def test_tv178_node_lines(self):
        """TV-178 (TR-23): each call form gives its title, a template as written; a two-line template
        is written with `\\n`; comments, strings, regular expressions, `describe`, a file not named
        `*.test.*` and a file outside the roots give none."""
        base = {"tests/all.test.cjs": NODE}
        self.assertEqual(self.inventory(self.repository.commit(base)), NODE_LINES)
        with self.subTest("a two-line template"):
            two = {"tests/two.test.cjs": "test(`one\ntwo`, () => {});\n"}
            self.assertEqual(self.inventory(self.repository.commit(two)), ["node one\\ntwo"])
        for name, (key, text) in NODE_NEGATIVES.items():
            with self.subTest(name):
                self.assertEqual(self.inventory(self.repository.commit({**base, key: text})), NODE_LINES)

    def test_tv179_unreadable_node_title(self):
        """TV-179 (TR-23): a `test(` or `it(` whose title is a variable is refused with its line and
        prints nothing; `x.test(name)` is no test and not refused."""
        for name, text, line in (("test", "const name = 'n';\ntest(name, () => {});\n", 2),
                                 ("it", "const it = require('node:test');\nconst title = 't';\n\nit(title);\n", 4)):
            with self.subTest(name):
                revision = self.repository.commit({"tests/name.test.cjs": text})
                self.assertEqual(run(self.root, "tests", revision),
                                 (2, [], f"SysML check failed: unreadable test name: tests/name.test.cjs:{line}\n"))
        revision = self.repository.commit({"tests/name.test.cjs": "const x = /a/, name = 'n';\nx.test(name);\ntest('ok', () => {});\n"})
        self.assertEqual(self.inventory(revision), ["node ok"])

    def test_tv180_python_lines(self):
        """TV-180 (TR-23): module-level and class-body tests give their lines, a nested def and a
        helper none; the model tool's tests, a harness path, a file not named `test_*.py` and an
        untracked file give none."""
        base = {"tools/test_a.py": PYTHON, "harness/project/config.yaml": HARNESS}
        self.assertEqual(self.inventory(self.repository.commit(base)), PYTHON_LINES)
        for name, (key, text) in PYTHON_NEGATIVES.items():
            with self.subTest(name):
                self.assertEqual(self.inventory(self.repository.commit({**base, key: text})), PYTHON_LINES)
        with self.subTest("an untracked file"):
            revision = self.repository.commit(base)
            (self.root / "tools/test_e.py").write_text("def test_e():\n    pass\n", encoding="utf-8")
            self.assertEqual(self.inventory(revision), PYTHON_LINES)
            self.assertEqual(self.inventory("HEAD"), PYTHON_LINES)

    def test_tv182_move_keeps_the_inventory(self):
        """TV-182 (TR-23): moving a Rust, a Node and a Python test to other files keeps the
        inventory; a rename drops the base line, a removal leaves a base line out, a duplicate
        adds one."""
        base = self.repository.commit(INVENTORY)
        before = self.inventory(base)
        self.assertEqual(before, sorted(RUST_LINES + NODE_LINES + PYTHON_LINES))
        split = {
            **INVENTORY,
            "server/src/clock.rs": RUST.replace("mod second {\n    #[test]\n    fn parses() {}\n}\n", ""),
            "server/tests/other.rs": "mod third {\n    #[test]\n    fn parses() {}\n}\n",
            "tests/all.test.cjs": NODE.replace("it('e', () => {});\n", ""),
            "tests/more/other.test.cjs": "const it = require('node:test');\nit('e', () => {});\n",
            "tools/test_a.py": PYTHON.replace("def test_m():\n    def test_inner():\n        pass\n", ""),
            "fixtures/test_moved.py": "def test_m():\n    pass\n",
        }
        after = self.inventory(self.repository.commit(split))
        self.assertEqual((len(after), after), (len(before), before))
        renamed = self.inventory(self.repository.commit(edit(INVENTORY, "server/src/clock.rs", "fn plain()", "fn plain_renamed()")))
        self.assertNotIn("rust plain", renamed)
        self.assertEqual(len(renamed), len(before))
        removed = self.inventory(self.repository.commit(edit(INVENTORY, "tests/all.test.cjs", "test('a', () => {});\n", "")))
        self.assertEqual(Counter(before) - Counter(removed), Counter(["node a"]))
        twice = self.inventory(self.repository.commit({**INVENTORY, "tests/again.test.cjs": "test('a', () => {});\n"}))
        self.assertEqual((len(twice), Counter(twice) - Counter(before)), (len(before) + 1, Counter(["node a"])))


# ---- The trace listing ----

AUTHORITY = "\n".join([
    "// Canonical authority: SysML",
    "package WstxRequirements {",
    "    requirement 'FR-001' {",
    "        doc /* The station keeps time. */",
    "    }",
    "    requirement 'FR-002' {",
    "        doc /* The station shows time. */",
    "    }",
    "}",
]) + "\n"
STATION_CLOCK = "\n".join([
    "package WstxStationClock {",                                                                  # 1
    "    requirement 'CL-001-01' {",                                                               # 2
    "        doc /* The clock MUST hold station time. */",                                         # 3
    "        @Status { build = ImplementationState::implemented; }",                               # 4
    '        @ImplementedIn { module = "server/src/clock/time.rs; server/src/clock/tick.rs"; }',   # 5
    "    }",                                                                                       # 6
    "    requirement 'CL-002-01' {",                                                               # 7
    "        doc /* The clock MUST show station time. */",                                         # 8
    "        @Status { build = ImplementationState::target; }",                                    # 9
    "    }",                                                                                       # 10
    "    verification 'TC-001-001' {",
    "        doc /* The clock ticks. */",
    "        objective { verify 'CL-001-01'; }",
    "        @Automation { run = AutomationState::implemented; }",
    '        @TestedBy { test = "server/tests/clock.rs::ticks"; }',
    "    }",
    "    #derivation connection { end #original ::> 'FR-001'; end #derive ::> 'CL-001-01'; }",
    "    #derivation connection { end #original ::> 'FR-002'; end #derive ::> 'CL-002-01'; }",
    "}",
]) + "\n"
LOGBOOK = "\n".join([
    "package WstxLogbook {",
    "    requirement 'CL-001-02' {",
    "        subject log : Log;",
    "        doc /* The log MUST hold the contacts. */",
    "        @Status { build = ImplementationState::target; }",
    "    }",
    "    verification 'TC-001-002' {",
    "        doc /* The log holds a contact. */",
    "        objective { verify 'CL-001-02'; }",
    "        @Automation { run = AutomationState::implemented; }",
    '        @TestedBy { test = "tests/clock.test.cjs::first; tests/clock.test.cjs::second TC-001-002"; }',
    "    }",
    "    verification 'TC-002-001' {",
    "        doc /* The operator reads the time. */",
    "        objective { verify 'CL-002-01'; }",
    '        @Automation { run = AutomationState::planned; method = "manual"; }',
    "    }",
    "    #derivation connection { end #original ::> 'FR-001'; end #derive ::> 'CL-001-02'; }",
    "}",
]) + "\n"
CLOCK_PART = ("package WstxClockPart {\n    part def Clock {\n        @ImplementedIn { module = \"server/src/clock/mod.rs; "
              "server/src/clock/time.rs; server/src/clock/tick.rs\"; }\n"
              "        @DetailTests { tests = \"tests/clock.test.cjs\"; covers = \"the third tick\"; }\n    }\n}\n")
LOG_PART = "package WstxLogPart {\n    part def Log {\n        @ImplementedIn { module = \"server/src/log/mod.rs\"; }\n    }\n}\n"
NODE_CLOCK = "\n".join([
    "const test = require('node:test');",
    "",
    "// Proves: TC-001-002",
    "test('first', () => {});",
    "",
    "test('second TC-001-002', () => {});",
    "",
    "test('third', () => {});",
]) + "\n"
TRACED = {
    "docs/sysml/Requirements.sysml": AUTHORITY,
    "docs/sysml/Shack.sysml": "package WstxShack {\n}\n",
    "docs/sysml/Context.sysml": "package WstxContext {\n}\n",
    "docs/sysml/backend/clock/Clock.sysml": CLOCK_PART,
    "docs/sysml/backend/clock/StationClock.sysml": STATION_CLOCK,
    "docs/sysml/backend/log/Log.sysml": LOG_PART,
    "docs/sysml/backend/log/Logbook.sysml": LOGBOOK,
    "server/src/clock/mod.rs": "pub mod tick;\npub mod time;\n",
    "server/src/clock/time.rs": "pub fn now() -> u64 {\n    0\n}\n",
    "server/src/clock/tick.rs": "pub fn tick() {}\n",
    "server/src/log/mod.rs": "pub fn log() {}\n",
    "server/tests/clock.rs": "// Proves: TC-001-001\n#[test]\nfn ticks() {}\n",
    "tests/clock.test.cjs": NODE_CLOCK,
}
LISTING = [
    "FR-001 partial clauses CL-001-01,CL-001-02",
    "FR-002 target clauses CL-002-01",
    "CL-001-01 implemented from FR-001 cases TC-001-001 link own tick.rs,time.rs",
    "CL-001-02 target from FR-001 cases TC-001-002 link part Log",
    "CL-002-01 target from FR-002 cases TC-002-001 link none",
    "TC-001-001 implemented automated verifies CL-001-01 tests rust ticks",
    "TC-001-002 implemented automated verifies CL-001-02 tests node first; node second TC-001-002",
    "TC-002-001 planned manual verifies CL-002-01 tests -",
]
CLOCK_KEY, LOG_KEY = "docs/sysml/backend/clock/StationClock.sysml", "docs/sysml/backend/log/Logbook.sysml"
# Each change of a trace, against TRACED, with the base line it removes.
CHANGES = {
    "a clause's state": (edit(TRACED, CLOCK_KEY, "ImplementationState::implemented", "ImplementationState::partial"),
                         "CL-001-01 implemented from FR-001 cases TC-001-001 link own tick.rs,time.rs"),
    "a case verifying another clause": (edit(TRACED, LOG_KEY, "verify 'CL-001-02'", "verify 'CL-001-01'"),
                                        "TC-001-002 implemented automated verifies CL-001-02 tests node first; node second TC-001-002"),
    "a bound test renamed": (edit(edit(TRACED, "server/tests/clock.rs", "fn ticks()", "fn ticks_on()"),
                                  CLOCK_KEY, "clock.rs::ticks", "clock.rs::ticks_on"),
                             "TC-001-001 implemented automated verifies CL-001-01 tests rust ticks"),
    "a Proves tag removed": (edit(edit(TRACED, "tests/clock.test.cjs", "// Proves: TC-001-002\n", ""),
                                  LOG_KEY, "tests/clock.test.cjs::first; ", ""),
                             "TC-001-002 implemented automated verifies CL-001-02 tests node first; node second TC-001-002"),
    "an own link to another file name": (edit(TRACED, CLOCK_KEY, "server/src/clock/time.rs;", "server/src/clock/mod.rs;"),
                                         "CL-001-01 implemented from FR-001 cases TC-001-001 link own tick.rs,time.rs"),
    "a part definition's link removed": ({key: (text if key != "docs/sysml/backend/log/Log.sysml" else
                                                "package WstxLogPart {\n    part def Log;\n}\n")
                                          for key, text in TRACED.items() if key != "server/src/log/mod.rs"},
                                         "CL-001-02 target from FR-001 cases TC-001-002 link part Log"),
    "an FR losing a clause": (edit(TRACED, LOG_KEY, "#original ::> 'FR-001'", "#original ::> 'FR-002'"),
                              "FR-001 partial clauses CL-001-01,CL-001-02"),
    "automated to manual": (edit(TRACED, CLOCK_KEY, "run = AutomationState::implemented; }",
                                 'run = AutomationState::implemented; method = "manual"; }'),
                            "TC-001-001 implemented automated verifies CL-001-01 tests rust ticks"),
}
TR13 = (edit(TRACED, CLOCK_KEY, "ImplementationState::target", "ImplementationState::implemented"),
        "CL-002-01 is delivered and has no code link: backend/clock/StationClock.sysml:7")
TR14 = ({**TRACED, "server/tests/clock.rs": "// Proves: TC-001-001\n#[test]\nfn ticks() {}\n\n"
                                             "// Proves: TC-009-009\n#[test]\nfn other() {}\n"},
        "Proves tag names an undeclared case: TC-009-009: server/tests/clock.rs:5")


class TraceListingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory(prefix="sysml-proof-test-")
        cls.repository = Repository(Path(cls.folder.name) / "repo")
        cls.base = cls.repository.commit(TRACED, "base")

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def setUp(self):
        self.root = self.repository.root
        self.repository.write(TRACED)

    def traces(self, revision: str) -> list[str]:
        code, lines, errors = run(self.root, "traces", revision)
        self.assertEqual((code, errors), (0, ""), lines)
        return lines

    def test_tv183_trace_listing(self):
        """TV-183 (TR-23): two FRs, three clauses (own link, link through a part definition, none)
        and three cases (a Rust test bound by name with its tag, two Node tests bound by name and
        named by tag and by title, manual) print exactly their eight lines; a detail test beside
        them prints none."""
        self.assertEqual(self.traces(self.base), LISTING)

    def test_tv184_move_keeps_the_listing(self):
        """TV-184 (TR-23): a linked module, a file of bound tests and a bound test moved, the
        model's paths updated: the listing is the same."""
        files = moved(TRACED, "server/src/clock/time.rs", "server/src/clock/inner/time.rs")
        files = edit(files, "docs/sysml/backend/clock/Clock.sysml", "server/src/clock/time.rs", "server/src/clock/inner/time.rs")
        files = edit(files, CLOCK_KEY, "server/src/clock/time.rs", "server/src/clock/inner/time.rs")
        files = moved(files, "tests/clock.test.cjs", "tests/clock/clock.test.cjs")
        files = edit(files, LOG_KEY, '"tests/clock.test.cjs::first; tests/clock.test.cjs::second TC-001-002"',
                     '"tests/clock/clock.test.cjs::first; tests/clock/clock.test.cjs::second TC-001-002"')
        files = edit(files, "docs/sysml/backend/clock/Clock.sysml", '"tests/clock.test.cjs"', '"tests/clock/clock.test.cjs"')
        files = moved(files, "server/tests/clock.rs", "server/tests/ticks.rs")
        files = edit(files, CLOCK_KEY, "server/tests/clock.rs::ticks", "server/tests/ticks.rs::ticks")
        self.assertEqual(self.traces(self.repository.commit(files, "move")), LISTING)

    def test_tv185_each_change_differs(self):
        """TV-185 (TR-23): each change of a trace (state, verified clause, test name, a `Proves:` tag
        with its name binding, own link file, part link, FR clauses, automated or manual), its own
        commit, leaves a base line out."""
        for name, (files, line) in CHANGES.items():
            with self.subTest(name):
                listing = self.traces(self.repository.commit(files, name))
                self.assertIn(line, LISTING)
                self.assertNotIn(line, listing)

    def test_tv186_trace_faults_at_a_revision(self):
        """TV-186 (TR-23): a TR-13 or TR-14 fault at the revision prints its fault line and no
        listing, while the working tree passes; a clean revision passes while the working tree
        holds the fault."""
        for name, (files, fault) in {"TR-13": TR13, "TR-14": TR14}.items():
            with self.subTest(name):
                revision = self.repository.commit(files, name)
                self.repository.write(TRACED)
                self.assertEqual(run(self.root, "traces")[0], 0)
                self.assertEqual(run(self.root, "traces", revision), (2, [fault], "SysML check failed: 1 faults\n"))
                self.repository.write(files)
                self.assertEqual(run(self.root, "traces")[0], 2)
                self.assertEqual(self.traces(self.base), LISTING)

    def test_tv181_working_tree_is_not_read(self):
        """TV-181 (TR-23): after a test is added and one removed, a clause's state edited and an
        untracked test and model file added, `tests` and `traces` at the revision print what they
        printed; the status, the stash list and the temporary folder are unchanged."""
        temporary = Path(self.folder.name) / "temporary"
        temporary.mkdir(exist_ok=True)
        status, stashes = self.repository.git("status", "--porcelain"), self.repository.git("stash", "list")

        def outputs():
            found = []
            for command in ("tests", "traces"):
                found.append(run(self.root, command, self.base, temporary=temporary))
                self.assertEqual(list(temporary.iterdir()), [])
                self.assertEqual(self.repository.git("stash", "list"), stashes)
                found.append(self.repository.git("status", "--porcelain"))
            return found

        before = outputs()
        self.assertEqual(before[0][:2], (0, ["node first", "node second TC-001-002", "node third", "rust ticks"]))
        self.assertEqual(before[2][:2], (0, LISTING))
        self.assertEqual((before[1], before[3]), (status, status))
        changed = edit(edit(TRACED, "tests/clock.test.cjs", "test('third', () => {});\n", "test('fourth', () => {});\n"),
                       CLOCK_KEY, "ImplementationState::target", "ImplementationState::partial")
        self.repository.write({**changed, "server/tests/clock.rs": "#[test]\nfn ticks() {}\n#[test]\nfn added() {}\n",
                               "tests/extra.test.cjs": "test('untracked', () => {});\n",
                               "docs/sysml/backend/clock/Extra.sysml": "package WstxExtra {\n}\n"})
        status = self.repository.git("status", "--porcelain")
        after = outputs()
        self.assertEqual([after[0], after[2]], [before[0], before[2]])
        self.assertEqual((after[1], after[3]), (status, status))

    def test_tv188_refusals(self):
        """TV-188 (TR-23): an unknown revision is refused by each form and `tests` without one; a
        raw string without its end is a source `tests` cannot read."""
        for command in ("tests", "check", "traces"):
            with self.subTest(command):
                self.assertEqual(run(self.root, command, "nosuchrev"),
                                 (2, [], "SysML check failed: unknown revision: nosuchrev\n"))
        code, lines, errors = run(self.root, "tests")
        self.assertEqual((code, lines), (2, []))
        self.assertTrue(errors.startswith("SysML check failed: unknown revision"), errors)
        revision = self.repository.commit({**TRACED, "server/src/bad.rs": 'fn a() {}\nconst S: &str = r#"open;\n'}, "bad")
        self.assertEqual(run(self.root, "tests", revision),
                         (2, [], "SysML check failed: source not readable: server/src/bad.rs:2: a raw string without its end\n"))


# ---- This repository ----

class ThisRepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        runs = {"tests HEAD": ("tests", "HEAD"), "traces HEAD": ("traces", "HEAD"), "tests HEAD^": ("tests", "HEAD^"),
                "traces": ("traces",)}
        with ThreadPoolExecutor(max_workers=3) as pool:
            futures = {name: pool.submit(run, ROOT, *argv) for name, argv in runs.items()}
            cls.results = {name: future.result() for name, future in futures.items()}

    def passed(self, name: str) -> list[str]:
        code, lines, errors = self.results[name]
        self.assertEqual(code, 0, errors + "\n".join(lines[-20:]))
        return lines

    def test_tv189_this_repository(self):
        """TV-189 (TR-23): `tests HEAD` lists one `rust` line per test attribute of the source roots
        and `node` lines of every `tests/*.test.cjs`; `traces HEAD` lists every FR, CL and TC of
        the catalog; `tests` passes at HEAD^."""
        lines = self.passed("tests HEAD")
        with tempfile.TemporaryDirectory(prefix="sysml-proof-test-") as folder:
            tree = Path(folder)
            original = tool.ROOT
            tool.ROOT = ROOT
            try:
                tool.extract("HEAD", tree)
            finally:
                tool.ROOT = original
            attributes = sum(len(tool.RUST_TEST_ATTRIBUTE.findall(path.read_text(encoding="utf-8")))
                             for name in tool.SOURCE_BINDING_ROOTS for path in (tree / name).rglob("*.rs"))
            self.assertEqual(len([line for line in lines if line.startswith("rust ")]), attributes)
            scripts = sorted((tree / "tests").glob("*.test.cjs"))
            self.assertTrue(scripts)
            for path in scripts:
                with self.subTest(path.name):
                    titles = tool.node_tests(path.name, path.read_text(encoding="utf-8"))
                    self.assertTrue(titles)
                    self.assertTrue(all("node " + title in lines for title in titles))
            entries = tool.canonical_catalog(tree / "docs/sysml", tree)
        listing = self.passed("traces HEAD")
        self.assertEqual([line.split(" ", 1)[0] for line in listing],
                         sorted(entries, key=lambda name: (("FR", "CL", "TC").index(name[:2]), name)))
        self.passed("tests HEAD^")

    def test_tv190_traces_without_a_revision(self):
        """TV-190 (TR-23): `traces` without a revision prints its summary line on this repository."""
        self.assertRegex(self.passed("traces")[-1], r"^Canonical source/model trace checks passed: \d+ identities; ")


if __name__ == "__main__":
    unittest.main()
