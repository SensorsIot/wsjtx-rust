"""TC-DOC-015: `equivalence` and `identities` (CL-014-17).

The synthetic cases build commits of a small model in a temporary git repository and
compare them with the real pinned Pilot; each mutation's oracle is the edit itself. E1 and
E10 (b) read this repository's own history.
"""
import contextlib
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import importlib.util

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("equivalence_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"

META = """/* Shared metadata header. */
package Meta {
    private import ScalarValues::*;
    enum def State { enum planned; enum partial; }
    metadata def Status { attribute build : State; }
    metadata def ImplementedIn { attribute module : String; }
}
"""
CORE = """// Keep the core small.
package Core {
    private import ScalarValues::*;
    private import Meta::*;

    /* First package note. */
    /* Second package note. */
    attribute def Size {
        doc /* A size in bytes; see Core::Run. */
    }
    attribute def Spare;
    attribute def Limits {
        doc /* Bounds of the core. */
        attribute bufferBytes : Integer = 8192;
        attribute peers : Integer [0..4];
    }
    item def Command;
    item def Reply;
    item def Ticket;
    port def CommandPort {
        in item command : Command;
        out item reply : Reply;
    }
    part def Base;
    part def Other;
    part def <E1> Engine {
        @Status { build = State::planned; }
        @ImplementedIn { module = "server/a.rs"; }
        attribute size : Size;
        attribute rpm : Integer = 8192;
    }
    part def Station :> Base {
        doc /* The station. */
        attribute limits : Limits;
        port control : CommandPort;
        part engine : Engine;
        part spare : Engine;
        ref part target : Engine :> engine;
        ref item ticket : Ticket;
    }
    part def Variant :> Station {
        part bigEngine :>> engine;
    }
    requirement def Goal;
    requirement goal1 : Goal {
        subject s : Station;
    }
    requirement goal2 : Goal;
    requirement goal3 : Goal;
    dependency d1 from goal1 to goal2;
    part station : Station;
    satisfy goal1 by station;
    satisfy goal2 by station;
    verification def CheckGoal;
    verification check1 : CheckGoal {
        objective { verify goal1; }
    }
    part system {
        part a : Station;
        part b : Station;
        part c : Station;
        connect a to b;
        satisfy goal1 by a;
    }
    view overview {
        expose system::*;
    }
    action def Run {
        doc /* Runs, see [spec](Spec.md). */
    }
}
"""
EXTRA = """package Extra {
    private import ScalarValues::*;
    attribute def Limits {
        attribute bufferBytes : Integer = 100;
    }
    part def Gauge {
        attribute limit : Limits;
    }
}
"""
RUN = """    action def Run {
        doc /* Runs, see [spec](Spec.md). */
    }
"""
GAUGE = """    part def Gauge {
        attribute limit : Limits;
    }
"""
BASE = {
    "docs/sysml/Meta.sysml": META,
    "docs/sysml/Core.sysml": CORE,
    "docs/sysml/Extra.sysml": EXTRA,
    "docs/sysml/Spec.md": "The spec.\n",
    "docs/sysml/Other.md": "Another file.\n",
}
CITING = {
    "server/main.rs": "// See Core::Run.\n// See Core::Nothing.\nfn main() {}\n",
    ".harness/suites.yaml": "paths: [docs/sysml/Extra.sysml]\n",
}


def edit(files: dict, path: str, old: str, new: str) -> dict:
    """`files` with the one occurrence of `old` in `path` replaced by `new`."""
    assert files[path].count(old) == 1, (path, old)
    return {**files, path: files[path].replace(old, new)}


def moved(files: dict, ticket=True, run=True) -> dict:
    """Ticket and Run moved from Core to docs/sysml/sub/Ops.sysml, package Ops, with the
    import Core needs, the qualified name in Size's doc and Run's link updated."""
    members = []
    if ticket:
        files = edit(files, "docs/sysml/Core.sysml", "    item def Ticket;\n", "")
        files = edit(files, "docs/sysml/Core.sysml", "    private import Meta::*;\n",
                     "    private import Meta::*;\n    private import Ops::*;\n")
        members.append("    item def Ticket;\n")
    if run:
        files = edit(files, "docs/sysml/Core.sysml", "see Core::Run", "see Ops::Run")
        files = edit(files, "docs/sysml/Core.sysml", RUN, "")
        members.append(RUN.replace("(Spec.md)", "(../Spec.md)"))
    return {**files, "docs/sysml/sub/Ops.sysml": "package Ops {\n" + "".join(members) + "}\n"}


def limits_moved(files: dict, value="100") -> dict:
    """Both Limits moved to Moved.sysml, packages MovedA and MovedB."""
    core_limits = CORE[CORE.index("    attribute def Limits {"):CORE.index("    item def Command;")]
    extra_limits = EXTRA[EXTRA.index("    attribute def Limits {"):EXTRA.index("    part def Gauge {")]
    files = edit(files, "docs/sysml/Core.sysml", core_limits, "")
    files = edit(files, "docs/sysml/Core.sysml", "    private import Meta::*;\n",
                 "    private import Meta::*;\n    private import MovedA::*;\n")
    files = edit(files, "docs/sysml/Extra.sysml", extra_limits, "    private import MovedB::*;\n")
    text = ("package MovedA {\n    private import ScalarValues::*;\n" + core_limits + "}\n"
            "package MovedB {\n    private import ScalarValues::*;\n" + extra_limits.replace("100", value) + "}\n")
    return {**files, "docs/sysml/Moved.sysml": text}


def modes(package: str, user: str, literals: str = "enum ft4; enum ft8;") -> str:
    """A package holding an enum def Mode and a part def whose attribute `user` it types."""
    return (f"package {package} {{\n    enum def Mode {{ {literals} }}\n"
            f"    part def Use{package} {{\n        attribute {user} : Mode;\n    }}\n}}\n")


# E13, E14: equal same-named Modes in A and B; A's file renamed so that it is read after B's.
MODES = {"docs/sysml/A.sysml": modes("A", "a"), "docs/sysml/B.sysml": modes("B", "b")}
MODES_MOVED = {"docs/sysml/B.sysml": modes("B", "b"), "docs/sysml/Z/A.sysml": modes("A", "a")}
CORE_PATH = "docs/sysml/Core.sysml"
CITED = {**BASE, **CITING}
RUN_ONLY = moved(CITED, ticket=False)
NODOC = edit(BASE, CORE_PATH, "        doc /* Bounds of the core. */\n", "")
# Each synthetic case: (base files, head files). The base of E8 carries the citations.
CASES = {
    "E2": (BASE, edit(BASE, CORE_PATH, "The station.", "The station!")),
    "E3 attribute": (BASE, edit(BASE, CORE_PATH, "        attribute peers : Integer [0..4];\n", "")),
    "E3 action": (BASE, edit(BASE, CORE_PATH, RUN, "")),
    "E4 dependency": (BASE, edit(BASE, CORE_PATH, "from goal1 to goal2", "from goal1 to goal3")),
    "E4 verify": (BASE, edit(BASE, CORE_PATH, "verify goal1;", "verify goal2;")),
    "E4 type": (BASE, edit(BASE, CORE_PATH, "attribute size : Size;", "attribute size : Spare;")),
    "E5 value": (BASE, edit(BASE, CORE_PATH, "rpm : Integer = 8192;", "rpm : Integer = 8193;")),
    "E5 multiplicity": (BASE, edit(BASE, CORE_PATH, "[0..4]", "[0..5]")),
    "E5 rename": (BASE, edit(BASE, CORE_PATH, "action def Run {", "action def Execute {")),
    "E6": (BASE, edit(edit(BASE, "docs/sysml/Extra.sysml", GAUGE, ""), CORE_PATH, RUN, RUN + GAUGE)),
    "E6 qualified": (BASE, edit(edit(BASE, "docs/sysml/Extra.sysml", GAUGE, ""), CORE_PATH, RUN,
                                RUN + GAUGE.replace(": Limits", ": Extra::Limits"))),
    "E7": (BASE, moved(BASE)),
    "E7 citation": (BASE, edit(moved(BASE), CORE_PATH, "see Ops::Run", "see Ops::Ticket")),
    "E7 note": (BASE, edit(moved(BASE), CORE_PATH, "// Keep the core small.\n", "")),
    "E8 a": (CITED, RUN_ONLY),
    "E8 a updated": (CITED, edit(RUN_ONLY, "server/main.rs", "Core::Run", "Ops::Run")),
    "E8 b": (CITED, {**{k: v for k, v in CITED.items() if k != "docs/sysml/Extra.sysml"},
                     "docs/sysml/sub/Extra.sysml": EXTRA}),
    "E8 b updated": (CITED, {**{k: v for k, v in CITED.items() if k != "docs/sysml/Extra.sysml"},
                             "docs/sysml/sub/Extra.sysml": EXTRA,
                             ".harness/suites.yaml": "paths: [docs/sysml/sub/Extra.sysml]\n"}),
    "E8 d": (CITED, edit(RUN_ONLY, CORE_PATH, "    private import Meta::*;\n",
                         "    private import Meta::*;\n    public import Ops::Run;\n")),
    "E12 a": (BASE, edit(BASE, CORE_PATH, "attribute def Spare;", "item def Spare;")),
    "E12 b": (BASE, edit(BASE, CORE_PATH, "<E1>", "<E2>")),
    "E12 c": (BASE, edit(BASE, CORE_PATH, "in item command", "out item command")),
    "E12 d": (BASE, edit(BASE, CORE_PATH, "Station :> Base", "Station :> Other")),
    "E12 e": (BASE, edit(BASE, CORE_PATH, ":> engine;", ":> spare;")),
    "E12 f": (BASE, edit(BASE, CORE_PATH, ":>> engine;", ":>> spare;")),
    "E12 g": (BASE, edit(BASE, CORE_PATH, "satisfy goal1 by a;", "satisfy goal2 by a;")),
    "E12 h": (BASE, edit(BASE, CORE_PATH, "subject s : Station;", "subject s : Engine;")),
    "E12 i": (BASE, edit(BASE, CORE_PATH, "connect a to b;", "connect a to c;")),
    "E12 j status": (BASE, edit(BASE, CORE_PATH, "State::planned", "State::partial")),
    "E12 j module": (BASE, edit(BASE, CORE_PATH, "server/a.rs", "server/b.rs")),
    "E12 k dropped": (BASE, edit(BASE, CORE_PATH, "    /* First package note. */\n", "")),
    "E12 k altered": (BASE, edit(BASE, CORE_PATH, "Second package note.", "Second package note!")),
    "E12 l": (BASE, edit(BASE, CORE_PATH, "    satisfy goal2 by station;\n", "")),
    "E12 m": (BASE, edit(BASE, CORE_PATH, "[spec](Spec.md)", "[spec](Other.md)")),
    "E12 n": (BASE, limits_moved(BASE, "101")),
    "E12 n unchanged": (BASE, limits_moved(BASE)),
    # Review repair of a3e4ddd7: owners of same-named elements, expose, members of no package.
    "E12 o": (BASE, edit(edit(BASE, CORE_PATH, "bufferBytes : Integer = 8192;", "bufferBytes : Integer = 100;"),
                         "docs/sysml/Extra.sysml", "bufferBytes : Integer = 100;", "bufferBytes : Integer = 8192;")),
    "E12 p": (BASE, edit(edit(BASE, CORE_PATH, "        attribute peers : Integer [0..4];\n", ""),
                         "docs/sysml/Extra.sysml", "        attribute bufferBytes : Integer = 100;\n",
                         "        attribute bufferBytes : Integer = 100;\n        attribute peers : Integer [0..4];\n")),
    "E12 q": (BASE, edit(BASE, CORE_PATH, "expose system::*;", "expose system;")),
    "E12 q dropped": (BASE, edit(BASE, CORE_PATH, "        expose system::*;\n", "")),
    "E12 r": (BASE, edit(BASE, "docs/sysml/Meta.sysml", "Shared metadata header.", "Shared metadata header!")),
    "E12 r dropped": (BASE, edit(BASE, "docs/sysml/Meta.sysml", "/* Shared metadata header. */\n", "")),
    # Two Limits with equal own facts (no doc, as in the real model), the file of one moved
    # so that it is read first: equivalent, paired by their named members.
    "E12 s": (NODOC, {**{k: v for k, v in NODOC.items() if k != "docs/sysml/Extra.sysml"},
                      "docs/sysml/A/Extra.sysml": EXTRA}),
    "E13": (MODES, MODES_MOVED),
    "E14": (MODES, {**MODES_MOVED, "docs/sysml/Z/A.sysml": modes("A", "a", "enum ft4; enum ft8; enum ft2;")}),
}
# The #170 assignment table (issue #170, Technical details): part file -> moved identities.
TABLE = {
    "backend/modes/ModesCatalog.sysml": "CL-007-03 CL-007-04 CL-009-01 TC-005-001 TC-005-002 TC-004-001 TC-004-002 TC-004-003",
    "backend/receive/ReceiveCatalog.sysml": "CL-007-01 CL-007-05 CL-008-02 TC-004-004 CL-045-01 CL-045-02 CL-045-03 TC-045-001 TC-045-002",
    "backend/profile/ProfileCatalog.sysml": "CL-005-01 CL-005-04 CL-005-05 CL-006-01 TC-022-002 TC-022-003 TC-018-001 TC-018-002",
    "backend/mcp/McpCatalog.sysml": "CL-012-01 CL-012-02 TC-020-001 TC-020-002",
    "backend/audio/AudioCatalog.sysml": "CL-044-07 TC-044-006",
    "backend/radioControl/RadioControlCatalog.sysml": "CL-008-06 CL-022-04 CL-044-01 CL-044-02 CL-044-03 CL-044-04 "
    "TC-044-001 TC-044-003 CL-044-09 TC-044-012 CL-044-10 TC-044-008 CL-044-15 TC-044-020 TC-044-022 TC-044-021",
    "backend/web/WebCatalog.sysml": "CL-003-03 CL-003-06 TC-021-005 TC-021-008 CL-051-01",
    "backend/station/StationCatalog.sysml": "CL-008-07 CL-044-16 TC-044-023",
    "backend/transmit/TransmitCatalog.sysml": "CL-009-02 CL-009-03 CL-009-04 TC-006-001 TC-008-003 TC-008-002 CL-043-02",
    "backend/qso/QsoCatalog.sysml": "CL-011-03 CL-010-01 CL-010-04 CL-010-15 CL-010-12 TC-007-001 TC-007-005 TC-011-001 "
    "TC-011-002 CL-039-21 CL-039-23 TC-039-022 CL-055-01 TC-055-001 CL-110-01 TC-110-001 TC-110-002 TC-110-003 "
    "TC-110-005 TC-110-006 CL-111-02 CL-111-05 CL-111-08 CL-111-10 TC-111-003 TC-111-004 TC-111-006 TC-111-012 "
    "TC-111-016 CL-024-02 TC-024-005 TC-024-006 CL-024-03 TC-024-007 TC-024-008 TC-024-009 CL-024-04 TC-024-011 "
    "TC-024-012 TC-024-013 TC-024-014 CL-099-01 CL-099-02 TC-099-001 TC-099-002 TC-099-003 TC-099-004 CL-063-01 "
    "CL-063-02 TC-063-001 TC-063-002 TC-063-003 TC-063-004 CL-063-06 TC-063-011 CL-097-02 CL-097-03 CL-097-05 "
    "TC-097-004 TC-097-005 TC-097-006 TC-097-007 TC-097-008 TC-097-010",
    "interfaces/UdpCatalog.sysml": "CL-040-01 CL-040-02 CL-040-03 CL-040-04 CL-040-06 TC-012-006 CL-040-07 TC-012-007 "
    "TC-012-001 TC-012-002 TC-012-003 TC-012-004 CL-112-01 CL-112-02 CL-112-03 CL-112-04 CL-112-06 TC-112-001 "
    "TC-112-002 TC-112-003 TC-112-004 TC-112-006",
    "frontend/FrontendCatalog.sysml": "CL-010-16 CL-010-06 CL-073-01 TC-073-001 TC-073-002 TC-073-003 CL-057-03 TC-057-004 "
    "CL-039-04 CL-055-04 CL-055-05 TC-055-007 CL-051-02 CL-051-03 TC-051-002 CL-050-01 CL-050-02 CL-054-02 TC-050-001 "
    "TC-050-002 CL-050-03 CL-050-05 TC-050-003 TC-050-005 CL-050-07 TC-050-007 CL-050-08 TC-050-008 TC-054-002 "
    "CL-060-01 TC-060-001 CL-061-01 TC-061-001 TC-061-002 CL-037-01 CL-037-02 CL-037-03 TC-037-001 TC-037-002 "
    "CL-065-02 TC-065-003 TC-082-004 CL-037-04 TC-037-003 CL-061-02 TC-061-003 CL-061-03 TC-061-004 CL-061-05 "
    "TC-061-008 TC-061-009 CL-096-01 TC-096-001 TC-096-002",
}


class Repository:
    """A temporary git repository; `commit` writes a whole tree of files."""

    def __init__(self, folder: Path):
        self.root = folder
        self.git("init", "-q", "-b", "master")

    def git(self, *args: str) -> str:
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        env.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        return subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(self.root), *args], check=True,
                              capture_output=True, text=True, env=env).stdout.strip()

    def commit(self, files: dict, message: str = "change") -> str:
        for entry in self.root.iterdir():
            if entry.name != ".git":
                shutil.rmtree(entry) if entry.is_dir() else entry.unlink()
        for path, text in files.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8", newline="\n")
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")


def run(*argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = tool.main(["--cache-dir", str(CACHE), *argv])
    return code, out.getvalue(), err.getvalue()


class SyntheticEquivalenceTests(unittest.TestCase):
    """E2 to E9 and E12 on one temporary repository, compared in one batch."""

    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        repository = Repository(Path(cls.folder.name))
        commits = {}

        def sha(files):
            key = tuple(sorted(files.items()))
            if key not in commits:
                commits[key] = repository.commit(files)
            return commits[key]

        names = list(CASES)
        pairs = [(sha(base), sha(head)) for base, head in CASES.values()]
        cls.broken = sha(edit(BASE, CORE_PATH, "part def Base;", "part def Base :> Missing;"))
        cls.base = sha(BASE)
        cls.patch = mock.patch.object(tool, "ROOT", repository.root)
        cls.patch.start()
        results, cls.exports = tool.compare_revisions(pairs, CACHE)
        cls.results = dict(zip(names, results))

    @classmethod
    def tearDownClass(cls):
        cls.patch.stop()
        cls.folder.cleanup()

    def outcome(self, name: str, code: int, *expected: str):
        """The case exits with `code` and prints a line starting with each of `expected`."""
        found, lines = self.results[name]
        self.assertEqual(found, code, f"{name}:\n" + "\n".join(lines))
        for prefix in expected:
            self.assertTrue(any(line.startswith(prefix) for line in lines), f"{name}: no line {prefix!r}:\n" + "\n".join(lines))
        return lines

    def kind(self, name: str, prefix: str, word: str):
        """The case exits 1 with a line starting with `prefix` that names the kind `word`."""
        lines = self.outcome(name, 1, prefix)
        self.assertTrue(any(line.startswith(prefix) and word in line for line in lines),
                        f"{name}: no {prefix!r} line naming {word}:\n" + "\n".join(lines))

    # Proves: CL-014-17; TC-DOC-015
    def test_e2_doc_character(self):
        self.outcome("E2", 1, "changed Station doc Core.sysml -> Core.sysml")

    # Proves: CL-014-17; TC-DOC-015
    def test_e3_dropped_element(self):
        self.outcome("E3 attribute", 1, "missing Limits::peers Core Core.sysml")
        self.outcome("E3 action", 1, "missing Run Core Core.sysml")

    # Proves: CL-014-17; TC-DOC-015
    def test_e4_changed_target(self):
        self.kind("E4 dependency", "changed d1 ", "Dependency")
        self.kind("E4 verify", "changed check1 ", "RequirementVerificationMembership")
        lines = self.outcome("E4 type", 1, "changed Engine::size ")
        self.assertTrue(any("FeatureTyping" in line for line in lines if line.startswith("changed Engine::size ")), lines)

    # Proves: CL-014-17; TC-DOC-015
    def test_e5_value_multiplicity_rename(self):
        self.outcome("E5 value", 1, "changed Engine::rpm ")
        lines = self.outcome("E5 multiplicity", 1, "changed Limits::peers ")
        self.assertTrue(any("MultiplicityRange" in line for line in lines), lines)
        self.outcome("E5 rename", 1, "missing Run Core Core.sysml", "added Execute Core Core.sysml")

    # Proves: CL-014-17; TC-DOC-015
    def test_e6_reference_resolving_to_another_element(self):
        self.outcome("E6", 1, "changed Gauge::limit ")
        self.outcome("E6 qualified", 0, "moved Gauge Extra Extra.sysml -> Core Core.sysml")

    # Proves: CL-014-17; TC-DOC-015
    def test_e7_move_listed_and_equivalent(self):
        lines = self.outcome("E7", 0, "moved Run Core Core.sysml -> Ops sub/Ops.sysml",
                             "moved Ticket Core Core.sysml -> Ops sub/Ops.sysml", "pair Core.sysml -> sub/Ops.sysml: 2")
        self.assertEqual(len([line for line in lines if line.startswith("moved ")]), 2, lines)
        self.outcome("E7 citation", 1, "changed Size doc ")
        self.outcome("E7 note", 1, 'missing note "Keep the core small." Core.sysml')

    # Proves: CL-014-17; TC-DOC-015
    def test_e8_citations_outside_the_model(self):
        self.outcome("E8 a", 1, "stale-by-change server/main.rs:1 Core::Run")
        lines = self.outcome("E8 a updated", 0, "unresolved server/main.rs:2 Core::Nothing")
        self.assertFalse(any(line.startswith("stale-by-change") for line in lines), lines)
        self.outcome("E8 b", 1, "stale-by-change .harness/suites.yaml:1 docs/sysml/Extra.sysml")
        self.outcome("E8 b updated", 0)
        lines = self.outcome("E8 d", 0)
        self.assertFalse(any("Core::Run" in line for line in lines), lines)

    # Proves: CL-014-17; TC-DOC-015
    def test_e9_cannot_compare(self):
        code, _out, err = run("equivalence", "no-such-revision", self.base)
        self.assertEqual(code, 2)
        self.assertIn("unknown revision: no-such-revision", err)
        code, _out, err = run("equivalence", self.base, self.broken)
        self.assertEqual(code, 2)
        self.assertIn("fails the Pilot validation", err)

    # Proves: CL-014-17; TC-DOC-015
    def test_e12_each_mutation_is_named(self):
        expected = {
            "E12 a": ("changed Spare kind",),
            "E12 b": ("changed Engine ",),
            "E12 c": ("changed CommandPort::command ",),
            "E12 d": ("changed Station ",),
            "E12 e": ("changed Station::target ",),
            "E12 f": ("changed Variant::bigEngine ",),
            "E12 g": ("changed system ",),
            "E12 h": ("changed goal1::s ",),
            "E12 i": ("changed system ",),
            "E12 j status": ("changed Engine ",),
            "E12 j module": ("changed Engine ",),
            "E12 k dropped": ('missing package-level Comment "First package note." Core.sysml',),
            "E12 k altered": ('missing package-level Comment "Second package note." Core.sysml',
                              'added package-level Comment "Second package note!" Core.sysml'),
            "E12 l": ("missing package-level ",),
            "E12 m": ("changed Run doc ",),
            "E12 n": ("missing Limits::bufferBytes Extra Extra.sysml", "added Limits::bufferBytes MovedB Moved.sysml"),
        }
        for name, prefixes in expected.items():
            with self.subTest(name):
                self.outcome(name, 1, *prefixes)
        kinds = {
            "E12 b": ("changed Engine ", "declaredShortName"),
            "E12 c": ("changed CommandPort::command ", "direction"),
            "E12 d": ("changed Station ", "Subclassification"),
            "E12 e": ("changed Station::target ", "Subsetting"),
            "E12 f": ("changed Variant::bigEngine ", "Redefinition"),
            "E12 g": ("changed system ", "SatisfyRequirementUsage"),
            "E12 h": ("changed goal1::s ", "FeatureTyping"),
            "E12 i": ("changed system ", "ConnectionUsage"),
            "E12 j status": ("changed Engine ", "MetadataUsage"),
            "E12 j module": ("changed Engine ", "MetadataUsage"),
        }
        for name, (prefix, word) in kinds.items():
            with self.subTest(name):
                self.kind(name, prefix, word)
        self.outcome("E12 n unchanged", 0)

    # Proves: CL-014-17; TC-DOC-015
    def test_e12o_values_swapped_between_same_named_owners(self):
        lines = self.outcome("E12 o", 1)
        self.assertTrue(any("Limits" in line for line in lines if not line.startswith(("moved", "pair", "equivalent"))), lines)

    # Proves: CL-014-17; TC-DOC-015
    def test_e12s_same_named_owners_pair_by_their_members(self):
        self.outcome("E12 s", 0, "moved Limits Extra Extra.sysml -> Extra A/Extra.sysml")

    # Proves: CL-014-17; TC-DOC-015
    def test_e12p_member_moved_between_same_named_owners(self):
        self.outcome("E12 p", 1, "changed Limits::peers owner Core.sysml -> Extra.sysml")

    # Proves: CL-014-17; TC-DOC-015
    def test_e12q_expose_is_compared(self):
        self.kind("E12 q", "changed overview ", "Expose")
        self.kind("E12 q dropped", "changed overview ", "Expose")

    # Proves: CL-014-17; TC-DOC-015
    def test_e12r_comment_outside_any_package(self):
        self.outcome("E12 r", 1, 'missing package-level Comment "Shared metadata header." Meta.sysml',
                     'added package-level Comment "Shared metadata header!" Meta.sysml')
        self.outcome("E12 r dropped", 1, 'missing package-level Comment "Shared metadata header." Meta.sysml')

    # Proves: CL-014-17; TC-DOC-015
    def test_e13_equal_same_named_elements_pair_in_their_package(self):
        lines = self.outcome("E13", 0, "moved Mode A A.sysml -> A Z/A.sysml")
        self.assertFalse(any(line.startswith("moved ") and " B " in line for line in lines), lines)

    # Proves: CL-014-17; TC-DOC-015
    def test_e14_changed_element_leaves_its_equal_namesake_paired(self):
        lines = self.outcome("E14", 1, "missing Mode A A.sysml", "added Mode A Z/A.sysml",
                             "added Mode::ft2 A Z/A.sysml")
        for line in lines:
            if " owner " in line:
                self.assertTrue(line.endswith(" owner A.sysml -> Z/A.sysml"), lines)
        self.assertFalse([line for line in lines if "B.sysml" in line or "FeatureTyping.target" in line], lines)


class IdentityTests(unittest.TestCase):
    # Proves: CL-014-17; TC-DOC-015
    def test_e10a_one_identity_of_each_status(self):
        base = """package R {
    requirement 'FR-001' { doc /* unchanged */ }
    requirement 'CL-001-01' { doc /* moved */ }
    requirement 'CL-001-02' { doc /* changed */ }
    verification 'TC-001-001' { doc /* removed */ }
    verification 'TC-001-002' { doc /* retired */ }
    part def Holder {
        @DetailTests { tests = "tests/x.rs"; }
    }
}
"""
        head = base.replace("    requirement 'CL-001-01' { doc /* moved */ }\n", "") \
            .replace("/* changed */", "/* changed! */") \
            .replace("    verification 'TC-001-001' { doc /* removed */ }\n", "") \
            .replace("    verification 'TC-001-002' { doc /* retired */ }\n", "    requirement 'FR-002' { doc /* added */ }\n") \
            .replace('        @DetailTests { tests = "tests/x.rs"; }\n',
                     '        @DetailTests { tests = "tests/x.rs"; }\n'
                     '        @RetiredCase { identity = "TC-001-002"; test = "tests/x.rs"; }\n')
        other = "package R2 {\n    requirement 'CL-001-01' { doc /* moved */ }\n}\n"
        with tempfile.TemporaryDirectory() as folder:
            repository = Repository(Path(folder))
            old = repository.commit({"docs/sysml/R.sysml": base})
            new = repository.commit({"docs/sysml/R.sysml": head, "docs/sysml/sub/Other.sysml": other})
            with mock.patch.object(tool, "ROOT", repository.root):
                code, out, _err = run("identities", old, new)
        self.assertEqual(code, 0, out)
        self.assertEqual(out.splitlines(), [
            "FR-001 unchanged R.sysml -> R.sysml",
            "FR-002 added - -> R.sysml",
            "CL-001-01 moved R.sysml -> sub/Other.sysml",
            "CL-001-02 changed R.sysml -> R.sysml",
            "TC-001-001 removed R.sysml -> -",
            "TC-001-002 retired R.sysml -> - test tests/x.rs",
            "6 identities: 1 unchanged, 1 moved, 1 changed, 1 added, 1 retired, 1 removed",
        ])

    # R1 of #183: a case declared in the base and superseded in the head
    # Proves: CL-014-17; TC-DOC-015
    def test_e10c_superseded_case_is_retired_with_its_cases(self):
        base = """package R {
    verification 'TC-001-001' { doc /* superseded */ }
    verification 'TC-001-002' { doc /* takes over */ }
    verification 'TC-001-003' { doc /* takes over */ }
}
"""
        head = base.replace("    verification 'TC-001-001' { doc /* superseded */ }\n",
                            '    @RetiredCase { identity = "TC-001-001"; supersededBy = "TC-001-002; TC-001-003"; }\n')
        with tempfile.TemporaryDirectory() as folder:
            repository = Repository(Path(folder))
            old = repository.commit({"docs/sysml/R.sysml": base})
            new = repository.commit({"docs/sysml/R.sysml": head})
            with mock.patch.object(tool, "ROOT", repository.root):
                code, out, _err = run("identities", old, new)
        self.assertEqual(code, 0, out)
        self.assertEqual(out.splitlines(), [
            "TC-001-001 retired R.sysml -> - superseded by TC-001-002, TC-001-003",
            "TC-001-002 unchanged R.sysml -> R.sysml",
            "TC-001-003 unchanged R.sysml -> R.sysml",
            "3 identities: 2 unchanged, 0 moved, 0 changed, 0 added, 1 retired, 0 removed",
        ])

    @staticmethod
    def moved_case(link: str) -> str:
        """The `identities` line of TC-001-001, moved from R.sysml to web/W.sysml in the commit
        that moves Proto.sysml to station/, its link to Proto.sysml rewritten as `link`."""
        def case(package: str, target: str) -> str:
            return f"package {package} {{\n    verification 'TC-001-001' {{ doc /* See [protocol]({target}). */ }}\n}}\n"

        proto, other = "package Proto {\n    part def Station;\n}\n", "package Other {\n    part def Spare;\n}\n"
        with tempfile.TemporaryDirectory() as folder:
            repository = Repository(Path(folder))
            old = repository.commit({"docs/sysml/R.sysml": case("R", "Proto.sysml"),
                                     "docs/sysml/Proto.sysml": proto, "docs/sysml/Other.sysml": other})
            new = repository.commit({"docs/sysml/R.sysml": "package R {\n}\n", "docs/sysml/station/Proto.sysml": proto,
                                     "docs/sysml/Other.sysml": other, "docs/sysml/web/W.sysml": case("W", link)})
            with mock.patch.object(tool, "ROOT", repository.root):
                code, out, _err = run("identities", old, new)
        assert code == 0, out
        return out.splitlines()[0]

    # Proves: CL-014-17; TC-DOC-015
    def test_e15_link_following_a_moved_file(self):
        self.assertEqual(self.moved_case("../station/Proto.sysml"), "TC-001-001 moved R.sysml -> web/W.sysml")

    # Proves: CL-014-17; TC-DOC-015
    def test_e15_guard_link_retargeted_to_another_file(self):
        self.assertEqual(self.moved_case("../Other.sysml"), "TC-001-001 changed R.sysml -> web/W.sysml")

    # Proves: CL-014-17; TC-DOC-015
    def test_e10b_real_revisions_list_the_union(self):
        code, out, _err = run("identities", "8245ec5f0", "0e4b4c73a")
        self.assertEqual(code, 0, out)
        lines = out.splitlines()
        declared = set()
        for revision in ("8245ec5f0", "0e4b4c73a"):
            listing = subprocess.run(["git", "-C", str(ROOT), "grep", "-h", "-o", "-E",
                                      r"(requirement|verification)( def)? '(FR-[0-9]{3}|CL-[0-9]{3}-[0-9]{2}|TC-[0-9]{3}-[0-9]{3})'",
                                      revision, "--", "docs/sysml"], capture_output=True, text=True, check=True).stdout
            declared.update(re.findall(r"'([^']+)'", listing))
        listed = [line.split()[0] for line in lines[:-1]]
        self.assertEqual(len(listed), len(set(listed)))
        self.assertEqual(set(listed), declared)
        counts = [int(number) for number in re.findall(r"(\d+) [a-z]+", lines[-1].split(":", 1)[1])]
        self.assertEqual(sum(counts), len(listed))
        self.assertTrue(lines[-1].startswith(f"{len(listed)} identities: "), lines[-1])


class RealHistoryTests(unittest.TestCase):
    """E1: #170's parent 0a7a57162 against 5da7aab02, which divided Requirements.sysml."""

    # Proves: CL-014-17; TC-DOC-015
    def test_e1_divided_requirements_are_equivalent(self):
        status = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"], capture_output=True, text=True).stdout
        results, exports = tool.compare_revisions([("5da7aab02^1", "5da7aab02"), ("5da7aab02", "5da7aab02")], CACHE)
        (code, lines), (same, same_lines) = results
        self.assertEqual(code, 0, "\n".join(line for line in lines if not line.startswith(("unresolved", "moved")))[:6000])
        self.assertEqual(same, 0, "\n".join(same_lines)[-3000:])
        self.assertEqual(exports, 2)
        self.assertEqual(subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"], capture_output=True, text=True).stdout, status)
        code, out, _err = run("identities", "5da7aab02^1", "5da7aab02")
        self.assertEqual(code, 0, out)
        lines = out.splitlines()
        rows = {line.split()[0]: line.split()[1:] for line in lines[:-1]}
        self.assertEqual(len(rows), 522)
        self.assertEqual(sum(1 for identity in rows if identity.startswith("FR-")), 24)
        self.assertEqual(sum(1 for identity in rows if identity.startswith("CL-")), 195)
        self.assertEqual(sum(1 for identity in rows if identity.startswith("TC-")), 303)
        table = {identity: file for file, listed in TABLE.items() for identity in listed.split()}
        self.assertEqual(len(table), 202)
        moved = {identity: row[3] for identity, row in rows.items() if row[0] == "moved"}
        self.assertEqual(moved, table)
        self.assertEqual(sum(1 for row in rows.values() if row[0] == "unchanged"), 320)
        self.assertIn("TC-021-005", moved)
        self.assertIn("TC-021-008", moved)
        self.assertEqual(lines[-1], "522 identities: 320 unchanged, 202 moved, 0 changed, 0 added, 0 retired, 0 removed")


class MarkedCommitTests(unittest.TestCase):
    # Proves: CL-014-17; TC-DOC-015
    def test_e11_marked_commits_against_their_first_parent(self):
        with tempfile.TemporaryDirectory() as folder:
            repository = Repository(Path(folder))
            repository.commit(BASE, "base")
            repository.git("checkout", "-q", "-b", "work")
            first = repository.commit(moved(BASE, run=False), "Move Ticket\n\nModel-Move: pure")
            second = repository.commit(moved(BASE), "Move Run\n\nModel-Move: pure")
            unmarked = repository.commit(edit(moved(BASE), CORE_PATH, "attribute def Spare;",
                                              "attribute def Spare { doc /* spare */ }"), "Document Spare")
            with mock.patch.object(tool, "ROOT", repository.root):
                code, out, _err = run("equivalence", "--marked")
                self.assertEqual(code, 0, out)
                lines = out.splitlines()
                self.assertIn(f"checked {first}", lines)
                self.assertIn(f"checked {second}", lines)
                self.assertIn(f"skipped {unmarked} (no Model-Move: pure)", lines)
                self.assertIn("3 exports", lines)
                altering = repository.commit(edit(edit(moved(BASE), CORE_PATH, "attribute def Spare;",
                                                       "attribute def Spare { doc /* spare */ }"),
                                                  CORE_PATH, "The station.", "The station!"),
                                             "Move nothing\n\nModel-Move: pure")
                code, out, _err = run("equivalence", "--marked")
                self.assertEqual(code, 1, out)
                self.assertIn(f"commit {altering}: differences", out.splitlines())
                self.assertIn(f"differences in {altering}", out)
                repository.git("checkout", "-q", "-b", "plain", "master")
                repository.commit(edit(BASE, CORE_PATH, "The station.", "The station!"), "Plain change")
                code, out, _err = run("equivalence", "--marked")
                self.assertEqual(code, 0, out)
                self.assertIn("no marked commit", out.splitlines())


if __name__ == "__main__":
    unittest.main()
