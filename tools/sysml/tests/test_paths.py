"""TR-20: `paths` rewrites the code paths the model names from a rename list.

Isolated fixtures in temporary trees, without the Pilot; the expected texts and listings
are written by hand, the line numbers counted in the fixture lines below. The real-model
test runs the tool on a `git archive` of HEAD.
"""
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("paths_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

ARCHITECTURE = "package WstxArchitecture {}\n"
AUTHORITY = "// Canonical authority: SysML\npackage WstxRequirements {\n}\n"
R1_LIST = "# R1\nserver/src/contact.rs -> server/src/qso/contact.rs\n\nserver/tests/vectors.rs -> server/tests/qso/vectors.rs\n"
R1_MODEL = "\n".join([
    "// Canonical authority: SysML",                                                               # 1
    "package WstxRequirements {",                                                                  # 2
    "    doc /* The contact log (server/src/contact.rs) and its tests. */",                        # 3
    "    doc /* server/browser tools/call server/src/contact.rsx xserver/src/contact.rs ../server/src/contact.rs */",  # 4
    "}",                                                                                           # 5
]) + "\n"
R1_EXPECTED = "\n".join([
    "// Canonical authority: SysML",
    "package WstxRequirements {",
    "    doc /* The contact log (server/src/qso/contact.rs) and its tests. */",
    "    doc /* server/browser tools/call server/src/contact.rsx xserver/src/contact.rs ../server/src/contact.rs */",
    "}",
]) + "\n"
CONTACT_KEY = "backend/qso/Contact.sysml"
# Two folders deep, with CRLF line endings; the link label shows the old path and stays.
CONTACT = "\r\n".join([
    "package WstxQsoContactPart {",                                                                # 1
    "    part def Contact {",                                                                      # 2
    "        doc /* See [server/src/contact.rs](../../../../server/src/contact.rs#writer) and [vectors](../../../../server/tests/vectors.rs). */",  # 3
    '        @ImplementedIn { module = "server/src/contact.rs"; }',                                # 4
    '        @WstxModelBindings::DetailTests { tests = "server/tests/vectors.rs; server/src/contact.rs"; covers = "the log"; }',  # 5
    "    }",                                                                                       # 6
    "    requirement 'CL-003-01' {",                                                               # 7
    "        subject contact : Contact;",                                                          # 8
    "        doc /* The contact log MUST live in server/src/contact.rs. */",                       # 9
    "        @Status { build = ImplementationState::implemented; }",                               # 10
    '        @ImplementedIn { module = "server/src/contact.rs"; }',                                # 11
    "    }",                                                                                       # 12
    "    verification 'TC-001-001' {",                                                             # 13
    "        doc /* The round trip. */",                                                           # 14
    "        subject contact : Contact;",                                                          # 15
    "        @Automation { run = AutomationState::implemented; }",                                 # 16
    "        objective { verify 'CL-003-01'; }",                                                   # 17
    '        @TestedBy { test = "server/tests/vectors.rs::round_trip"; }',                         # 18
    "    }",                                                                                       # 19
    "}",                                                                                           # 20
]) + "\r\n"
CONTACT_EXPECTED = "\r\n".join([
    "package WstxQsoContactPart {",
    "    part def Contact {",
    "        doc /* See [server/src/contact.rs](../../../../server/src/qso/contact.rs#writer) and [vectors](../../../../server/tests/qso/vectors.rs). */",
    '        @ImplementedIn { module = "server/src/qso/contact.rs"; }',
    '        @WstxModelBindings::DetailTests { tests = "server/tests/qso/vectors.rs; server/src/qso/contact.rs"; covers = "the log"; }',
    "    }",
    "    requirement 'CL-003-01' {",
    "        subject contact : Contact;",
    "        doc /* The contact log MUST live in server/src/qso/contact.rs. */",
    "        @Status { build = ImplementationState::implemented; }",
    '        @ImplementedIn { module = "server/src/qso/contact.rs"; }',
    "    }",
    "    verification 'TC-001-001' {",
    "        doc /* The round trip. */",
    "        subject contact : Contact;",
    "        @Automation { run = AutomationState::implemented; }",
    "        objective { verify 'CL-003-01'; }",
    '        @TestedBy { test = "server/tests/qso/vectors.rs::round_trip"; }',
    "    }",
    "}",
]) + "\r\n"
R1_OUTPUT = """rewrote Requirements.sysml:3 server/src/contact.rs -> server/src/qso/contact.rs
rewrote backend/qso/Contact.sysml:3 ../../../../server/src/contact.rs -> ../../../../server/src/qso/contact.rs
rewrote backend/qso/Contact.sysml:3 ../../../../server/tests/vectors.rs -> ../../../../server/tests/qso/vectors.rs
rewrote backend/qso/Contact.sysml:4 server/src/contact.rs -> server/src/qso/contact.rs
rewrote backend/qso/Contact.sysml:5 server/tests/vectors.rs -> server/tests/qso/vectors.rs
rewrote backend/qso/Contact.sysml:5 server/src/contact.rs -> server/src/qso/contact.rs
rewrote backend/qso/Contact.sysml:9 server/src/contact.rs -> server/src/qso/contact.rs
rewrote backend/qso/Contact.sysml:11 server/src/contact.rs -> server/src/qso/contact.rs
rewrote backend/qso/Contact.sysml:18 server/tests/vectors.rs -> server/tests/qso/vectors.rs
Path rewrite: 9 rewrites in 2 model files
"""
R1_FILES = ("server/src/qso/contact.rs", "server/tests/qso/vectors.rs", "client/app.js", "tools/x.rs")

RADIO_KEY = "backend/radio/Radio.sysml"
R2_MODEL = "\n".join([
    "package WstxRadioPart {",                                                                     # 1
    "    doc /* The folder server/src/radio_control holds it; see server/src/radio_control/cat.rs. */",  # 2
    "    verification 'TC-001-001' {",                                                             # 3
    '        @TestedBy { test = "server/src/radio_control/mod.rs::Configuration; server/src/radio_control_tests.rs"; }',  # 4
    "    }",                                                                                       # 5
    "    doc /* server/src/radio_control/mod.rs::Configuration */",                                # 6
    "}",                                                                                           # 7
]) + "\n"
R2_EXPECTED = "\n".join([
    "package WstxRadioPart {",
    "    doc /* The folder server/src/radio_control holds it; see server/src/radio/control/cat.rs. */",
    "    verification 'TC-001-001' {",
    '        @TestedBy { test = "server/src/radio/control/mod.rs::Configuration; server/src/radio_control_tests.rs"; }',
    "    }",
    "    doc /* server/src/radio/control/mod.rs::Configuration */",
    "}",
]) + "\n"
R2_OUTPUT = """rewrote backend/radio/Radio.sysml:2 server/src/radio_control/cat.rs -> server/src/radio/control/cat.rs
rewrote backend/radio/Radio.sysml:4 server/src/radio_control/mod.rs -> server/src/radio/control/mod.rs
rewrote backend/radio/Radio.sysml:6 server/src/radio_control/mod.rs -> server/src/radio/control/mod.rs
Path rewrite: 3 rewrites in 1 model files
"""

LOG_KEY = "backend/qso/Log.sysml"
# Joined values whose literals meet at `; `: each literal holds whole paths.
JOINED_MODEL = "\n".join([
    "package WstxQsoLogPart {",                                                                    # 1
    "    part def Log {",                                                                          # 2
    "        @ImplementedIn {",                                                                    # 3
    '            module = "server/src/contact.rs; "',                                              # 4
    '                + "server/src/log.rs";',                                                      # 5
    "        }",                                                                                   # 6
    '        @DetailTests { tests = "server/tests/log.rs; " + "server/tests/vectors.rs"; covers = "the log"; }',  # 7
    "    }",                                                                                       # 8
    "}",                                                                                           # 9
]) + "\n"
JOINED_EXPECTED = "\n".join([
    "package WstxQsoLogPart {",
    "    part def Log {",
    "        @ImplementedIn {",
    '            module = "server/src/qso/contact.rs; "',
    '                + "server/src/log.rs";',
    "        }",
    '        @DetailTests { tests = "server/tests/log.rs; " + "server/tests/qso/vectors.rs"; covers = "the log"; }',
    "    }",
    "}",
]) + "\n"
JOINED_OUTPUT = """rewrote backend/qso/Log.sysml:4 server/src/contact.rs -> server/src/qso/contact.rs
rewrote backend/qso/Log.sysml:7 server/tests/vectors.rs -> server/tests/qso/vectors.rs
Path rewrite: 2 rewrites in 1 model files
"""
JOINED_FILES = ("server/src/qso/contact.rs", "server/src/log.rs", "server/tests/log.rs", "server/tests/qso/vectors.rs")
# A joined value is one value: its path ends at `::`, not at the end of a literal.
SYMBOL_MODEL = "\n".join([
    "package WstxQsoLogPart {",                                                                    # 1
    "    verification 'TC-001-002' {",                                                             # 2
    '        @TestedBy { test = "server/tests/vectors.rs::" + "round_trip"; }',                    # 3
    "    }",                                                                                       # 4
    "}",                                                                                           # 5
]) + "\n"
SYMBOL_EXPECTED = SYMBOL_MODEL.replace('"server/tests/vectors.rs::"', '"server/tests/qso/vectors.rs::"')
# A path split inside by `+` is still one path of the value.
SPLIT_MODEL = "\n".join([
    "package WstxQsoLogPart {",                                                                    # 1
    "    part def Log {",                                                                          # 2
    '        @ImplementedIn { module = "server/src/con" + "tact.rs"; }',                           # 3
    "    }",                                                                                       # 4
    "}",                                                                                           # 5
]) + "\n"

# The refusals: a small model consistent with the tree, so each refusal stands alone.
SMALL_KEY = "backend/qso/Store.sysml"
SMALL = "\n".join([
    "package WstxQsoStorePart {",                                                                  # 1
    "    part def Store {",                                                                        # 2
    "        doc /* [vectors](../../../../server/tests/qso/vectors.rs) */",                        # 3
    '        @ImplementedIn { module = "server/src/qso/contact.rs"; }',                            # 4
    "    }",                                                                                       # 5
    "    doc /* see server/tests/qso/vectors.rs */",                                               # 6
    "}",                                                                                           # 7
]) + "\n"
# One checked binding to a missing file each, added as line 7 of SMALL.
MISSING_BINDINGS = (
    ("a clause's own @ImplementedIn",
     "    requirement 'CL-003-02' { @ImplementedIn { module = \"server/src/missing.rs\"; } }", "server/src/missing.rs"),
    ("a part definition's @ImplementedIn",
     "    part def Shelf { @ImplementedIn { module = \"server/src/store.rs\"; } }", "server/src/store.rs"),
    ("a @DetailTests path",
     "    part def Shelf { @DetailTests { tests = \"client/app.js; server/tests/store.rs\"; covers = \"the shelf\"; } }",
     "server/tests/store.rs"),
    ("a case's @TestedBy",
     "    verification 'TC-001-003' { @TestedBy { test = \"tests/store.test.cjs::stores\"; } }", "tests/store.test.cjs"),
    ("the second literal of a joined value",
     "    part def Shelf { @ImplementedIn { module = \"client/app.js; \" + \"server/src/shelf.rs\"; } }", "server/src/shelf.rs"),
)
# A @TestedBy outside every case is a binding the catalog does not check: it holds a command line.
UNCHECKED = '    part def Review { @TestedBy { test = "tools/sysml.py check; tools/missing.py"; } }'
# A whole path in the model text, a relative link's leading `../` included; not part of a longer path.
WHOLE_PATH = r"(?<![\w./-])(?:\.\./)*{}(?![\w-]|\.[\w/-])"


def joined(line):
    """The text of the string literals of `line`, joined."""
    return "".join(re.findall(r'"([^"\r\n]*)"', line))


class PathRewriteTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.models = self.root / "docs/sysml"
        self.list = Path(self.temporary.name) / "renames.txt"

    def tree(self, models, files):
        for key, text in {"Architecture.sysml": ARCHITECTURE, "Requirements.sysml": AUTHORITY, **models}.items():
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

    def traces(self):
        """Run `traces` on the tree, the validator forbidden; returns (exit code, stdout, stderr)."""
        output, errors = io.StringIO(), io.StringIO()
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), \
                mock.patch.object(tool, "FSD", self.root / "docs/WSTX Rust FSD.md"), \
                mock.patch.object(tool, "validate", side_effect=AssertionError("validator invoked")), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["traces"])
        return status, output.getvalue(), errors.getvalue()

    def model(self, key):
        return (self.models / key).read_bytes().decode("utf-8")

    def refused(self, listing, *faults):
        before = self.hashes()
        self.assertEqual(self.paths(listing),
                         (2, "".join(fault + "\n" for fault in faults) + f"Path rewrite refused: {len(faults)} faults\n", ""))
        self.assertEqual(self.hashes(), before)

    def test_file_renames_rewrite_every_form_and_nothing_else(self):
        """TR-20: file renames rewrite @ImplementedIn, @TestedBy, @DetailTests, relative links and
        whole paths in text, and nothing that is not a whole path; a second run is refused."""
        self.tree({"Requirements.sysml": R1_MODEL, CONTACT_KEY: CONTACT}, R1_FILES)
        architecture = self.hashes()["docs/sysml/Architecture.sysml"]
        with self.subTest("rewritten as written by hand"):
            self.assertEqual(self.paths(R1_LIST), (0, R1_OUTPUT, ""))
            self.assertEqual(self.model("Requirements.sysml"), R1_EXPECTED)
            self.assertEqual(self.model(CONTACT_KEY), CONTACT_EXPECTED)
            self.assertEqual(self.hashes()["docs/sysml/Architecture.sysml"], architecture)
        with self.subTest("not paths: line 4 is unchanged"):
            self.assertEqual(self.model("Requirements.sysml").split("\n")[3], R1_MODEL.split("\n")[3])
        with self.subTest("second run"):
            self.refused(R1_LIST, "Path not named by the model: server/src/contact.rs",
                         "Path not named by the model: server/tests/vectors.rs")

    def test_folder_rename_rewrites_paths_below_it_only(self):
        """TR-20: a folder rename rewrites the paths below the folder, not the folder named alone
        nor a name that only begins like it."""
        self.tree({RADIO_KEY: R2_MODEL},
                  ("server/src/radio/control/mod.rs", "server/src/radio/control/cat.rs", "server/src/radio_control_tests.rs"))
        self.assertEqual(self.paths("server/src/radio_control/ -> server/src/radio/control/\n"), (0, R2_OUTPUT, ""))
        self.assertEqual(self.model(RADIO_KEY), R2_EXPECTED)

    def test_each_literal_of_a_joined_value_is_rewritten(self):
        """TR-20: the paths of every literal of a value joined by `+` are rewritten and checked."""
        self.tree({LOG_KEY: JOINED_MODEL}, JOINED_FILES)
        self.assertEqual(self.paths(R1_LIST), (0, JOINED_OUTPUT, ""))
        self.assertEqual(self.model(LOG_KEY), JOINED_EXPECTED)

    def test_a_joined_value_is_one_path(self):
        """TR-20: a joined value is one value: a path that ends at `::` in one literal, or that
        is split inside by `+`, is read and rewritten as one path."""
        with self.subTest("a test name in the next literal"):
            self.tree({LOG_KEY: SYMBOL_MODEL}, ("server/tests/qso/vectors.rs",))
            self.assertEqual(self.paths("server/tests/vectors.rs -> server/tests/qso/vectors.rs\n"), (0, (
                "rewrote backend/qso/Log.sysml:3 server/tests/vectors.rs -> server/tests/qso/vectors.rs\n"
                "Path rewrite: 1 rewrites in 1 model files\n"), ""))
            self.assertEqual(self.model(LOG_KEY), SYMBOL_EXPECTED)
        self.root = Path(self.temporary.name) / "second"
        self.models = self.root / "docs/sysml"
        with self.subTest("a path split inside"):
            self.tree({LOG_KEY: SPLIT_MODEL}, ("server/src/qso/contact.rs",))
            self.assertEqual(self.paths("server/src/contact.rs -> server/src/qso/contact.rs\n"), (0, (
                "rewrote backend/qso/Log.sysml:3 server/src/contact.rs -> server/src/qso/contact.rs\n"
                "Path rewrite: 1 rewrites in 1 model files\n"), ""))
            written, before = self.model(LOG_KEY).split("\n"), SPLIT_MODEL.split("\n")
            self.assertEqual(written[:2] + written[3:], before[:2] + before[3:])
            self.assertTrue(written[2].startswith("        @ImplementedIn { module = ") and written[2].endswith("; }"), written[2])
            self.assertEqual(joined(written[2]), "server/src/qso/contact.rs")

    def test_unchecked_strings_are_rewritten_but_not_checked(self):
        """TR-20: a binding the catalog does not check is rewritten but refuses nothing."""
        def added(text, index, line):
            lines = text.split("\n")
            return "\n".join(lines[:index] + [line] + lines[index:])

        with self.subTest("a command line outside every case stays and refuses nothing"):
            self.tree({"Requirements.sysml": added(R1_MODEL, 4, UNCHECKED), CONTACT_KEY: CONTACT}, R1_FILES)
            self.assertEqual(self.paths(R1_LIST), (0, R1_OUTPUT, ""))
            self.assertEqual(self.model("Requirements.sysml"), added(R1_EXPECTED, 4, UNCHECKED))
        self.root = Path(self.temporary.name) / "second"
        self.models = self.root / "docs/sysml"
        bound = UNCHECKED.replace("tools/sysml.py check; tools/missing.py", "server/src/contact.rs")
        with self.subTest("a path there is rewritten"):
            self.tree({"Requirements.sysml": added(R1_MODEL, 4, bound), CONTACT_KEY: CONTACT}, R1_FILES)
            self.assertEqual(self.paths(R1_LIST), (0, R1_OUTPUT.replace(
                "rewrote backend", "rewrote Requirements.sysml:5 server/src/contact.rs -> server/src/qso/contact.rs\nrewrote backend", 1)
                .replace("9 rewrites", "10 rewrites"), ""))
            self.assertEqual(self.model("Requirements.sysml"),
                             added(R1_EXPECTED, 4, bound.replace("src/contact", "src/qso/contact")))
        self.root = Path(self.temporary.name) / "third"
        self.models = self.root / "docs/sysml"
        with self.subTest("a path inside a command line is rewritten whole"):
            self.tree({SMALL_KEY: added(SMALL, 6, UNCHECKED)},
                      ("server/src/qso/contact.rs", "server/tests/qso/vectors.rs", "client/app.js", "tools/model/sysml.py"))
            self.assertEqual(self.paths("tools/sysml.py -> tools/model/sysml.py\n"), (0, (
                "rewrote backend/qso/Store.sysml:7 tools/sysml.py -> tools/model/sysml.py\n"
                "Path rewrite: 1 rewrites in 1 model files\n"), ""))
            self.assertEqual(self.model(SMALL_KEY), added(SMALL, 6, UNCHECKED.replace("tools/sysml.py", "tools/model/sysml.py")))

    def test_refusals_write_nothing(self):
        """TR-20: a malformed list, a missing moved file or a path that stays missing is refused
        with its faults and nothing is written."""
        self.tree({SMALL_KEY: SMALL}, ("server/src/qso/contact.rs", "server/tests/qso/vectors.rs", "client/app.js"))
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
        with self.subTest("a fault of the list hides the faults of the moved files"):
            self.refused("server/src/qso/contact.rs -> server/src/qso/contact.rs\nserver/src/gone.rs -> server/src/nowhere.rs\n",
                         "Rename to itself: server/src/qso/contact.rs")
        self.write(self.root / "tools/x.rs", "// outside the source roots\n")
        with self.subTest("a binding renamed outside the source roots"):
            os.remove(self.root / "server/src/qso/contact.rs")
            self.refused("server/src/qso/contact.rs -> tools/x.rs\n", "Path missing after rename: backend/qso/Store.sysml:4 tools/x.rs")
            self.write(self.root / "server/src/qso/contact.rs", "// back\n")
        for name, line, missing in MISSING_BINDINGS:
            with self.subTest(name + " to a missing file"):
                lines = SMALL.split("\n")
                self.write(self.models / SMALL_KEY, "\n".join(lines[:6] + [line] + lines[6:]))
                self.move("server/tests/qso/vectors.rs", "server/tests/vectors2.rs")
                self.refused("server/tests/qso/vectors.rs -> server/tests/vectors2.rs\n",
                             "Path missing after rename: backend/qso/Store.sysml:7 " + missing)
                self.move("server/tests/vectors2.rs", "server/tests/qso/vectors.rs")
                self.write(self.models / SMALL_KEY, SMALL)
        with self.subTest("a link to a missing file"):
            self.write(self.models / SMALL_KEY, SMALL.replace(" */", " [gone](../../../../server/src/gone.rs) */", 1))
            self.move("server/src/qso/contact.rs", "server/src/contact2.rs")
            self.refused("server/src/qso/contact.rs -> server/src/contact2.rs\n",
                         "Path missing after rename: backend/qso/Store.sysml:3 ../../../../server/src/gone.rs")
        with self.subTest("a missing list file"):
            before = self.hashes()
            status, output, errors = self.paths(None)
            self.assertEqual((status, output), (2, ""))
            self.assertTrue(errors.startswith("SysML check failed: "), errors)
            self.assertEqual(self.hashes(), before)
        with self.subTest("no authority"):
            self.write(self.models / "Requirements.sysml", AUTHORITY.split("\n", 1)[1])
            before = self.hashes()
            status, output, errors = self.paths("server/src/qso/contact.rs -> server/src/contact2.rs\n")
            self.assertEqual((status, output), (2, ""))
            self.assertIn("SysML check failed: No declared functional authority", errors)
            self.assertEqual(self.hashes(), before)

    def test_real_model_rewrites_a_moved_test_file_and_traces_keep_their_verdict(self):
        """TR-20: on the model of HEAD, every path of a moved test file is rewritten, nothing
        outside the model is written, and `traces` gives the verdict it gave before the move;
        the repository is not written."""
        with mock.patch.object(tool, "ROOT", ROOT):
            tool.extract("HEAD", self.root, ("docs/sysml", "client", "server", "tests"))
        texts = [path.read_bytes().decode("utf-8") for path in self.models.rglob("*.sysml")]
        for path in sorted((self.root / "tests").glob("*.test.cjs")):
            old = path.relative_to(self.root).as_posix()
            count = sum(len(re.findall(WHOLE_PATH.format(re.escape(old)), text)) for text in texts)
            if count:
                break
        else:
            self.fail("the model names no test file below tests/")
        new = "tests/moved/" + old.rpartition("/")[2]
        traced = self.traces()
        self.move(old, new)
        outside = {path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in self.root.rglob("*") if path.is_file() and not path.is_relative_to(self.models)}
        status_code, output, errors = self.paths(f"{old} -> {new}\n")
        self.assertEqual((status_code, errors), (0, ""), output)
        lines = output.splitlines()
        self.assertEqual(len([line for line in lines if line.startswith("rewrote ")]), count)
        self.assertEqual(lines[-1].split(" rewrites in ")[0], f"Path rewrite: {count}")
        self.assertEqual({path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in self.root.rglob("*") if path.is_file() and not path.is_relative_to(self.models)}, outside)
        self.assertEqual(self.traces(), tuple(part.replace(old, new) if isinstance(part, str) else part for part in traced))
        self.assertFalse((ROOT / new).exists())
        self.assertEqual([path for path in (ROOT / "docs/sysml").rglob("*.sysml") if new in path.read_bytes().decode("utf-8")], [])


if __name__ == "__main__":
    unittest.main()
