"""TC-DOC-018: `paths` rewrites the code paths the model names from a rename list (CL-014-20).

Isolated fixtures in temporary trees, without the Pilot; the expected texts and listings
are written by hand, the line numbers counted in the fixture lines below. R6 runs the tool
on a `git archive` of HEAD.
"""
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("paths_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

ARCHITECTURE = "package WstxArchitecture {}\n"
R1_LIST = "# R1\nserver/src/contact.rs -> server/src/qso/contact.rs\n\nserver/tests/vectors.rs -> server/tests/qso/vectors.rs\n"
R1_MODEL = "\n".join([
    "// Canonical authority: SysML",                                                               # 1
    "package WstxRequirements {",                                                                  # 2
    "    // (server/src/contact.rs)",                                                              # 3
    "    // server/browser tools/call server/src/contact.rsx xserver/src/contact.rs ../server/src/contact.rs",  # 4
    "    requirement 'CL-003-01' {",                                                               # 5
    "        doc /* The contact log lives in server/src/contact.rs. */",                           # 6
    '        attribute implementation : String = "server/src/contact.rs";',                        # 7
    "    }",                                                                                       # 8
    "    verification 'TC-001-001' {",                                                             # 9
    '        attribute executable : String = "server/tests/vectors.rs::round_trip";',              # 10
    "    }",                                                                                       # 11
    "    part def Contact {",                                                                      # 12
    '        @ImplementedIn { module = "server/src/contact.rs"; }',                                # 13
    '        @ModelBindings::TestedBy { test = "server/tests/vectors.rs"; }',                      # 14
    '        @DetailTests { tests = "server/tests/vectors.rs; server/src/contact.rs"; }',          # 15
    '        @RetiredCase { identity = "TC-001-002"; test = "server/tests/vectors.rs"; }',         # 16
    "    }",                                                                                       # 17
    "}",                                                                                           # 18
]) + "\n"
R1_EXPECTED = "\n".join([
    "// Canonical authority: SysML",
    "package WstxRequirements {",
    "    // (server/src/qso/contact.rs)",
    "    // server/browser tools/call server/src/contact.rsx xserver/src/contact.rs ../server/src/contact.rs",
    "    requirement 'CL-003-01' {",
    "        doc /* The contact log lives in server/src/qso/contact.rs. */",
    '        attribute implementation : String = "server/src/qso/contact.rs";',
    "    }",
    "    verification 'TC-001-001' {",
    '        attribute executable : String = "server/tests/qso/vectors.rs::round_trip";',
    "    }",
    "    part def Contact {",
    '        @ImplementedIn { module = "server/src/qso/contact.rs"; }',
    '        @ModelBindings::TestedBy { test = "server/tests/qso/vectors.rs"; }',
    '        @DetailTests { tests = "server/tests/qso/vectors.rs; server/src/qso/contact.rs"; }',
    '        @RetiredCase { identity = "TC-001-002"; test = "server/tests/qso/vectors.rs"; }',
    "    }",
    "}",
]) + "\n"
CONTACT_KEY = "backend/qso/Contact.sysml"
# Two folders deep, with CRLF line endings; the link label shows the old path and stays.
CONTACT = "\r\n".join([
    "package QsoContact {",                                                                        # 1
    "    doc /* See [server/src/contact.rs](../../../../server/src/contact.rs#writer) and [vectors](../../../../server/tests/vectors.rs). */",  # 2
    "}",                                                                                           # 3
]) + "\r\n"
CONTACT_EXPECTED = "\r\n".join([
    "package QsoContact {",
    "    doc /* See [server/src/contact.rs](../../../../server/src/qso/contact.rs#writer) and [vectors](../../../../server/tests/qso/vectors.rs). */",
    "}",
]) + "\r\n"
R1_OUTPUT = """rewrote Requirements.sysml:3 server/src/contact.rs -> server/src/qso/contact.rs
rewrote Requirements.sysml:6 server/src/contact.rs -> server/src/qso/contact.rs
rewrote Requirements.sysml:7 server/src/contact.rs -> server/src/qso/contact.rs
rewrote Requirements.sysml:10 server/tests/vectors.rs -> server/tests/qso/vectors.rs
rewrote Requirements.sysml:13 server/src/contact.rs -> server/src/qso/contact.rs
rewrote Requirements.sysml:14 server/tests/vectors.rs -> server/tests/qso/vectors.rs
rewrote Requirements.sysml:15 server/tests/vectors.rs -> server/tests/qso/vectors.rs
rewrote Requirements.sysml:15 server/src/contact.rs -> server/src/qso/contact.rs
rewrote Requirements.sysml:16 server/tests/vectors.rs -> server/tests/qso/vectors.rs
rewrote backend/qso/Contact.sysml:2 ../../../../server/src/contact.rs -> ../../../../server/src/qso/contact.rs
rewrote backend/qso/Contact.sysml:2 ../../../../server/tests/vectors.rs -> ../../../../server/tests/qso/vectors.rs
Path rewrite: 11 rewrites in 2 model files
"""
R1_FILES = ("server/src/qso/contact.rs", "server/tests/qso/vectors.rs", "client/app.js", "tools/x.rs")

R2_MODEL = "\n".join([
    "// Canonical authority: SysML",                                                               # 1
    "package WstxRequirements {",                                                                  # 2
    "    doc /* The folder server/src/radio_control holds it; see server/src/radio_control/cat.rs. */",  # 3
    "    verification 'TC-001-001' {",                                                             # 4
    '        attribute executable : String = "server/src/radio_control/mod.rs::Configuration; server/src/radio_control_tests.rs";',  # 5
    "    }",                                                                                       # 6
    "    // server/src/radio_control/mod.rs::Configuration",                                       # 7
    "}",                                                                                           # 8
]) + "\n"
R2_EXPECTED = "\n".join([
    "// Canonical authority: SysML",
    "package WstxRequirements {",
    "    doc /* The folder server/src/radio_control holds it; see server/src/radio/control/cat.rs. */",
    "    verification 'TC-001-001' {",
    '        attribute executable : String = "server/src/radio/control/mod.rs::Configuration; server/src/radio_control_tests.rs";',
    "    }",
    "    // server/src/radio/control/mod.rs::Configuration",
    "}",
]) + "\n"
R2_OUTPUT = """rewrote Requirements.sysml:3 server/src/radio_control/cat.rs -> server/src/radio/control/cat.rs
rewrote Requirements.sysml:5 server/src/radio_control/mod.rs -> server/src/radio/control/mod.rs
rewrote Requirements.sysml:7 server/src/radio_control/mod.rs -> server/src/radio/control/mod.rs
Path rewrite: 3 rewrites in 1 model files
"""

# R4: a small model consistent with the tree, so each refusal stands alone.
SMALL = "\n".join([
    "// Canonical authority: SysML",                                                               # 1
    "package WstxRequirements {",                                                                  # 2
    "    requirement 'FR-003' {",                                                                  # 3
    '        attribute implementation : String = "server/src/qso/contact.rs";',                    # 4
    "    }",                                                                                       # 5
    "    // see server/tests/qso/vectors.rs",                                                      # 6
    "}",                                                                                           # 7
]) + "\n"
# R4: one checked binding to a missing file each, added as line 7 of SMALL.
MISSING_BINDINGS = (
    ("an unrelated FR declaration binding", "    requirement 'FR-004' { attribute implementation : String = \"server/src/missing.rs\"; }",
     "server/src/missing.rs"),
    ("a function @ImplementedIn", "    part def Store { @ImplementedIn { module = \"server/src/store.rs\"; } }", "server/src/store.rs"),
    ("a @DetailTests path", "    part def Store { @DetailTests { tests = \"client/app.js; server/tests/store.rs\"; } }",
     "server/tests/store.rs"),
    ("a TC declaration's attribute executable",
     "    verification 'TC-001-003' { attribute executable : String = \"tests/store.test.cjs::stores\"; }", "tests/store.test.cjs"),
)
# R7: a binding outside every declaration that holds a command line, not a path binding.
UNCHECKED = '    verification ArchitectureReview { attribute executable : String = "tools/sysml.py check; tools/missing.py"; }'
SMALL_CONTACT = "package QsoContact {\n    doc /* [vectors](../../../../server/tests/qso/vectors.rs) */\n}\n"


class PathRewriteTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.models = self.root / "docs/sysml"
        self.list = Path(self.temporary.name) / "renames.txt"

    def tree(self, models, files):
        for key, text in {"Architecture.sysml": ARCHITECTURE, **models}.items():
            self.write(self.models / key, text)
        for name in files:
            self.write(self.root / name, "// " + name + "\n")

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))

    def move(self, old, new):
        (self.root / new).parent.mkdir(parents=True, exist_ok=True)
        os.replace(self.root / old, self.root / new)

    def hashes(self):
        return {path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(self.models.rglob("*")) if path.is_file()}

    def paths(self, listing=None):
        """Run `paths` on the fixture with the list text `listing` (None: no list file),
        the validator and every process forbidden; returns (exit code, stdout, stderr)."""
        if listing is None:
            self.list.unlink(missing_ok=True)
        else:
            self.list.write_bytes(listing.encode("utf-8"))
        output, errors = io.StringIO(), io.StringIO()
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), \
                mock.patch.object(tool, "FSD", self.root / "docs/FSD.md"), \
                mock.patch.object(tool, "validate", side_effect=AssertionError("validator invoked")), \
                mock.patch.object(tool.subprocess, "run", side_effect=AssertionError("process started")), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["paths", str(self.list)])
        return status, output.getvalue(), errors.getvalue()

    def model(self, key):
        return (self.models / key).read_bytes().decode("utf-8")

    def refused(self, listing, *faults):
        before = self.hashes()
        self.assertEqual(self.paths(listing),
                         (2, "".join(fault + "\n" for fault in faults) + f"Path rewrite refused: {len(faults)} faults\n", ""))
        self.assertEqual(self.hashes(), before)

    # R1, R3, R5
    # Proves: CL-014-20; TC-DOC-018
    def test_file_renames_rewrite_every_form_and_nothing_else(self):
        self.tree({"Requirements.sysml": R1_MODEL, CONTACT_KEY: CONTACT}, R1_FILES)
        architecture = self.hashes()["docs/sysml/Architecture.sysml"]
        with self.subTest("R1 rewritten as written by hand"):
            self.assertEqual(self.paths(R1_LIST), (0, R1_OUTPUT, ""))
            self.assertEqual(self.model("Requirements.sysml"), R1_EXPECTED)
            self.assertEqual(self.model(CONTACT_KEY), CONTACT_EXPECTED)
            self.assertEqual(self.hashes()["docs/sysml/Architecture.sysml"], architecture)
        with self.subTest("R3 not paths: line 4 is unchanged"):
            self.assertEqual(self.model("Requirements.sysml").split("\n")[3], R1_MODEL.split("\n")[3])
        with self.subTest("R5 second run"):
            self.refused(R1_LIST, "Path not named by the model: server/src/contact.rs",
                         "Path not named by the model: server/tests/vectors.rs")

    # R2
    # Proves: CL-014-20; TC-DOC-018
    def test_folder_rename_rewrites_paths_below_it_only(self):
        self.tree({"Requirements.sysml": R2_MODEL},
                  ("server/src/radio/control/mod.rs", "server/src/radio/control/cat.rs", "server/src/radio_control_tests.rs"))
        self.assertEqual(self.paths("server/src/radio_control/ -> server/src/radio/control/\n"), (0, R2_OUTPUT, ""))
        self.assertEqual(self.model("Requirements.sysml"), R2_EXPECTED)

    # R7
    # Proves: CL-014-20; TC-DOC-018
    def test_unchecked_strings_are_rewritten_but_not_checked(self):
        def added(text, line):
            lines = text.split("\n")
            return "\n".join(lines[:17] + [line] + lines[17:])

        with self.subTest("a command line outside every declaration stays and refuses nothing"):
            self.tree({"Requirements.sysml": added(R1_MODEL, UNCHECKED), CONTACT_KEY: CONTACT}, R1_FILES)
            self.assertEqual(self.paths(R1_LIST), (0, R1_OUTPUT, ""))
            self.assertEqual(self.model("Requirements.sysml"), added(R1_EXPECTED, UNCHECKED))
        self.root = Path(self.temporary.name) / "second"
        self.models = self.root / "docs/sysml"
        bound = UNCHECKED.replace("tools/sysml.py check; tools/missing.py", "server/src/contact.rs")
        with self.subTest("a path there is rewritten by (a)"):
            self.tree({"Requirements.sysml": added(R1_MODEL, bound), CONTACT_KEY: CONTACT}, R1_FILES)
            self.assertEqual(self.paths(R1_LIST), (0, R1_OUTPUT.replace(
                "rewrote backend", "rewrote Requirements.sysml:18 server/src/contact.rs -> server/src/qso/contact.rs\nrewrote backend", 1)
                .replace("11 rewrites", "12 rewrites"), ""))
            self.assertEqual(self.model("Requirements.sysml"), added(R1_EXPECTED, bound.replace("src/contact", "src/qso/contact")))
        self.root = Path(self.temporary.name) / "third"
        self.models = self.root / "docs/sysml"
        with self.subTest("a path inside a command line is rewritten whole by (c) and names the entry"):
            lines = SMALL.split("\n")
            self.tree({"Requirements.sysml": "\n".join(lines[:6] + [UNCHECKED] + lines[6:]), CONTACT_KEY: SMALL_CONTACT},
                      ("server/src/qso/contact.rs", "server/tests/qso/vectors.rs", "client/app.js", "tools/model/sysml.py"))
            self.assertEqual(self.paths("tools/sysml.py -> tools/model/sysml.py\n"), (0, (
                "rewrote Requirements.sysml:7 tools/sysml.py -> tools/model/sysml.py\n"
                "Path rewrite: 1 rewrites in 1 model files\n"), ""))
            self.assertEqual(self.model("Requirements.sysml"), "\n".join(
                lines[:6] + [UNCHECKED.replace("tools/sysml.py", "tools/model/sysml.py")] + lines[6:]))

    # R4
    # Proves: CL-014-20; TC-DOC-018
    def test_refusals_write_nothing(self):
        self.tree({"Requirements.sysml": SMALL, CONTACT_KEY: SMALL_CONTACT},
                  ("server/src/qso/contact.rs", "server/tests/qso/vectors.rs", "client/app.js"))
        for listing, fault in (
                ("server/src/contact.rs => server/src/qso/contact.rs\n", "Invalid rename line 1"),
                ("# first\nserver\\src\\gone.rs -> client/app.js\n", "Invalid rename line 2"),
                ("# only a comment\n\n", "Empty rename list"),
                ("/server/src/gone.rs -> client/app.js\n", "Invalid rename path: /server/src/gone.rs"),
                ("C:/server/src/gone.rs -> client/app.js\n", "Invalid rename path: C:/server/src/gone.rs"),
                ("server/../server/src/gone.rs -> client/app.js\n", "Invalid rename path: server/../server/src/gone.rs"),
                ("server/src/gone.rs -> docs/sysml/contact.rs\n", "Invalid rename path: docs/sysml/contact.rs"),
                ("server/src/gone.rs -> client/app.js\nserver/src/gone.rs -> client/app.js\n", "Duplicate rename: server/src/gone.rs"),
                ("server/src -> server/source\nserver/src/contact.rs -> server/src/qso/contact.rs\n",
                 "Overlapping renames: server/src, server/src/contact.rs"),
                ("server/src/a.rs -> server/src/b.rs\nserver/src/b.rs -> server/src/c.rs\n", "Chained rename: server/src/b.rs"),
                ("server/src/qso/contact.rs -> server/src/qso/contact.rs\n", "Rename to itself: server/src/qso/contact.rs"),
                ("server/src/qso/contact.rs -> server/tests/qso/vectors.rs\n", "Old path still present: server/src/qso/contact.rs"),
                ("server/src/gone.rs -> server/src/nowhere.rs\n", "New path missing: server/src/nowhere.rs"),
                ("server/src/gone.rs -> client/app.js\n", "Path not named by the model: server/src/gone.rs"),
        ):
            with self.subTest(fault=fault):
                self.refused(listing, fault)
        with self.subTest("two faults, sorted"):
            self.refused("server/src/qso/contact.rs -> server/src/qso/contact.rs\nx/a.rs -> x/b.rs\nx/a.rs -> x/b.rs\n",
                         "Duplicate rename: x/a.rs", "Rename to itself: server/src/qso/contact.rs")
        with self.subTest("a step-1 fault hides the step-2 faults"):
            self.refused("server/src/qso/contact.rs -> server/src/qso/contact.rs\nserver/src/gone.rs -> server/src/nowhere.rs\n",
                         "Rename to itself: server/src/qso/contact.rs")
        self.write(self.root / "tools/x.rs", "// outside the source roots\n")
        with self.subTest("a binding renamed outside the source roots"):
            os.remove(self.root / "server/src/qso/contact.rs")
            self.refused("server/src/qso/contact.rs -> tools/x.rs\n", "Path missing after rename: Requirements.sysml:4 tools/x.rs")
            self.write(self.root / "server/src/qso/contact.rs", "// back\n")
        for name, line, missing in MISSING_BINDINGS:
            with self.subTest(name + " to a missing file"):
                lines = SMALL.split("\n")
                self.write(self.models / "Requirements.sysml", "\n".join(lines[:6] + [line] + lines[6:]))
                self.move("server/tests/qso/vectors.rs", "server/tests/vectors2.rs")
                self.refused("server/tests/qso/vectors.rs -> server/tests/vectors2.rs\n",
                             "Path missing after rename: Requirements.sysml:7 " + missing)
                self.move("server/tests/vectors2.rs", "server/tests/qso/vectors.rs")
                self.write(self.models / "Requirements.sysml", SMALL)
        with self.subTest("a link to a missing file"):
            self.write(self.models / CONTACT_KEY, SMALL_CONTACT.replace(" */", " [gone](../../../../server/src/gone.rs) */"))
            self.move("server/src/qso/contact.rs", "server/src/contact2.rs")
            self.refused("server/src/qso/contact.rs -> server/src/contact2.rs\n",
                         "Path missing after rename: backend/qso/Contact.sysml:2 ../../../../server/src/gone.rs")
        with self.subTest("a missing list file"):
            before = self.hashes()
            status, output, errors = self.paths(None)
            self.assertEqual((status, output), (2, ""))
            self.assertTrue(errors.startswith("SysML check failed: "), errors)
            self.assertEqual(self.hashes(), before)
        with self.subTest("no authority"):
            self.write(self.models / "Requirements.sysml", SMALL.split("\n", 1)[1])
            before = self.hashes()
            status, output, errors = self.paths("server/src/qso/contact.rs -> server/src/contact2.rs\n")
            self.assertEqual((status, output), (2, ""))
            self.assertIn("SysML check failed: No declared functional authority", errors)
            self.assertEqual(self.hashes(), before)

    # R6
    # Proves: CL-014-20; TC-DOC-018
    def test_real_model_rewrites_a_moved_test_file_and_traces_pass(self):
        def status():
            return subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"], capture_output=True,
                                  encoding="utf-8", check=True).stdout

        repository = status()
        with mock.patch.object(tool, "ROOT", ROOT):
            tool.extract("HEAD", self.root, ("docs/sysml", "client", "server", "tests"))
        old, new = "tests/communication.test.cjs", "tests/protocol/communication.test.cjs"
        self.move(old, new)
        count = sum(path.read_bytes().decode("utf-8").count(old) for path in self.models.rglob("*.sysml"))
        self.assertGreater(count, 0)
        outside = {path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in self.root.rglob("*") if path.is_file() and not path.is_relative_to(self.models)}
        status_code, output, errors = self.paths(f"{old} -> {new}\n")
        self.assertEqual((status_code, errors), (0, ""), output)
        lines = output.splitlines()
        self.assertEqual(len([line for line in lines if line.startswith("rewrote ")]), count)
        self.assertEqual(lines[-1].split(" rewrites in ")[0], f"Path rewrite: {count}")
        self.assertEqual({path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in self.root.rglob("*") if path.is_file() and not path.is_relative_to(self.models)}, outside)
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), \
                mock.patch.object(tool, "FSD", self.root / "docs/WSTX Rust FSD.md"), \
                mock.patch.object(tool, "validate", side_effect=AssertionError("validator invoked")), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as traced:
            self.assertEqual(tool.main(["traces"]), 0, traced.getvalue())
        self.assertEqual(status(), repository)


if __name__ == "__main__":
    unittest.main()
