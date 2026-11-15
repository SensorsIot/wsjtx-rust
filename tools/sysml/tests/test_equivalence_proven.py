"""TC-DOC-020: the proven removals of `equivalence` (CL-014-22, CL-014-17).

The synthetic cases build commits of a small model in a temporary git repository and
compare them with the real pinned Pilot; every expected line is written by hand from the
edit. Neither P5 nor P6 reads the model of HEAD. P5 reads the model before #204 (PINNED) by
`git archive`; P6 checks out the merge of #204 (P6_BASE) in a temporary repository. The
tools are those of the working tree.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

from test_equivalence import Repository, edit

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("proven_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
# The pinned base commit of #204, whose model files equal those of its base.
PINNED = "f80c243c9"
# P6 needs #204's ModelBindings (TestLevel, TestLocation) and the old form of TC-007-002 and
# TC-085-006 (before #205), so it has its own base: the merge of #204 into master. P5 checks
# the mapping on the model before #204 and stays on PINNED.
P6_BASE = "728289975"

BINDINGS = """package ModelBindings {
    private import ScalarValues::*;
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
    enum def TestLocation { enum developmentPc; enum station; enum simulator; enum flexRadio; }
    metadata def Status { attribute build : ImplementationState; }
    metadata def Automation { attribute run : AutomationState; attribute method : String[0..1]; }
    metadata def ImplementedIn { attribute module : String; }
    metadata def TestedBy { attribute test : String; }
    metadata def TestLevel { attribute cost : Integer; attribute location : TestLocation; }
}
"""
FIRST_DOC = """        doc /* #### TC-001-001 — First case

             Proves CL-001-01, CL-001-02. See TC-001-002 and TC001001.
             Steps: open and check.
             2 — Isolated automated tests; Windows development PC, no radio. */
"""
MODEL = """package R {
    private import ScalarValues::*;
    private import ModelBindings::*;
    requirement 'FR-001' {
        doc /* The function. */
    }
    requirement 'CL-001-01' {
        doc /* The first clause. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/a.rs";
    }
    requirement 'CL-001-02' {
        doc /* The second clause. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'CL-001-03' {
        doc /* The third clause. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_001_01_to_FR_001 from 'CL-001-01' to 'FR-001';
    dependency CL_001_02_to_FR_001 from 'CL-001-02' to 'FR-001';
    dependency CL_001_03_to_FR_001 from 'CL-001-03' to 'FR-001';
    verification 'TC-001-001' {
""" + FIRST_DOC + """        attribute automation : AutomationState = AutomationState::implemented;
        attribute method : String = "automated";
        objective {
            verify 'CL-001-01';
            verify 'CL-001-02';
        }
        attribute executable : String = "tests/a.test.cjs";
    }
    dependency CL_001_01_verified_by_TC_001_001 from 'CL-001-01' to 'TC-001-001';
    dependency CL_001_02_verified_by_TC_001_001 from 'CL-001-02' to 'TC-001-001';
    verification 'TC-001-002' {
        doc /* TC-001-002, the second case.
             CL-001-01, CL-001-02
             | 2 — Isolated automated tests | table |
             Expected: shown. */
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'CL-001-01'; verify 'CL-001-02'; }
    }
    verification 'TC-001-003' {
        doc /* The third case checks CL-001-01/02 offline.
             **Level: 3 — Live read-only tests.** Watch it. */
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'CL-001-01'; verify 'CL-001-02'; verify 'CL-001-03'; }
    }
    verification ResolvedArchitectureGraph {
        doc /* Level 2 isolated model test. */
    }
    verification OtherGraph {
        doc /* Level 2 other model test. */
    }
}
"""
PATH = "docs/sysml/Requirements.sysml"
BASE = {"docs/sysml/shared/ModelBindings.sysml": BINDINGS, PATH: MODEL}
DEV = "        @TestLevel { cost = 2; location = TestLocation::developmentPc; }\n"
STATION = "        @TestLevel { cost = 4; location = TestLocation::station; }\n"
FIRST_AUTOMATION = "        attribute automation : AutomationState = AutomationState::implemented;\n"
FIRST_METHOD = '        attribute method : String = "automated";\n'
FIRST_EXECUTABLE = '        attribute executable : String = "tests/a.test.cjs";\n'
COST_LINE = "             2 — Isolated automated tests; Windows development PC, no radio. */\n"
DEPENDENCY = "    dependency CL_001_01_verified_by_TC_001_001 from 'CL-001-01' to 'TC-001-001';\n"


def edits(files: dict, *changes) -> dict:
    """`files` with each (old, new) of `changes` replaced once in the model file."""
    for old, new in changes:
        files = edit(files, PATH, old, new)
    return files


ALSO = ("Steps: open and check.", "Steps: open and check. Also: {}.")
# P1: each rule alone: (head, the one expected proven line).
SINGLE = {
    "case-number heading": (edits(BASE, ("#### TC-001-001 — First case", "First case")),
                            "proven case-number 'TC-001-001' Requirements.sysml -> Requirements.sysml"),
    "case-number plain": (edits(BASE, ("TC-001-002, the second case.", "the second case.")),
                          "proven case-number 'TC-001-002' Requirements.sysml -> Requirements.sysml"),
    "clause-list Proves": (edits(BASE, ("Proves CL-001-01, CL-001-02. See", "See")),
                           "proven clause-list 'TC-001-001' Requirements.sysml -> Requirements.sysml"),
    "clause-list bare line": (edits(BASE, ("             CL-001-01, CL-001-02\n", "")),
                              "proven clause-list 'TC-001-002' Requirements.sysml -> Requirements.sysml"),
    "cost line wording": (edits(BASE, (COST_LINE, "             no radio. */\n"), (FIRST_AUTOMATION, DEV + FIRST_AUTOMATION)),
                          "proven cost 'TC-001-001' Requirements.sysml -> Requirements.sysml"),
    "cost bold wording at a line start": (edits(BASE, ("**Level: 3 — Live read-only tests.** Watch it.", "Watch it."),
                                ("verify 'CL-001-03'; }\n", "verify 'CL-001-03'; }\n"
                                 "        @TestLevel { cost = 3; location = TestLocation::flexRadio; }\n")),
                          "proven cost 'TC-001-003' Requirements.sysml -> Requirements.sysml"),
    "cost element wording": (edits(BASE, ("doc /* Level 2 isolated model test. */", "doc /* isolated model test. */\n" + DEV)),
                             "proven cost ResolvedArchitectureGraph Requirements.sysml -> Requirements.sysml"),
    "dependency": (edits(BASE, (DEPENDENCY, "")),
                   "proven dependency CL_001_01_verified_by_TC_001_001 Requirements.sysml -> Requirements.sysml"),
    "status coverage": (edits(BASE, ("        doc /* The second clause. */\n        attribute coverage : ImplementationState = "
                                     "ImplementationState::target;\n",
                                     "        doc /* The second clause. */\n        @Status { build = ImplementationState::target; }\n")),
                        "proven status 'CL-001-02' Requirements.sysml -> Requirements.sysml"),
    "status implementation": (edits(BASE, ('        attribute implementation : String = "server/a.rs";\n',
                                           '        @ImplementedIn { module = "server/a.rs"; }\n')),
                              "proven status 'CL-001-01' Requirements.sysml -> Requirements.sysml"),
    "status automation": (edits(BASE, ("        attribute automation : AutomationState = AutomationState::planned;\n"
                                       "        objective { verify 'CL-001-01'; verify 'CL-001-02'; }\n",
                                       "        @Automation { run = AutomationState::planned; }\n"
                                       "        objective { verify 'CL-001-01'; verify 'CL-001-02'; }\n")),
                          "proven status 'TC-001-002' Requirements.sysml -> Requirements.sysml"),
    "status method": (edits(BASE, (FIRST_METHOD, '        @Automation { method = "automated"; }\n')),
                      "proven status 'TC-001-001' Requirements.sysml -> Requirements.sysml"),
    "status executable": (edits(BASE, (FIRST_EXECUTABLE, '        @TestedBy { test = "tests/a.test.cjs"; }\n')),
                          "proven status 'TC-001-001' Requirements.sysml -> Requirements.sysml"),
}
# The shorthand: in a base whose TC-001-003 verifies CL-001-01 and CL-001-02 only.
SHORTHAND_BASE = edits(BASE, ("verify 'CL-001-01'; verify 'CL-001-02'; verify 'CL-001-03'; }",
                              "verify 'CL-001-01'; verify 'CL-001-02'; }"))
SHORTHAND = (SHORTHAND_BASE, edits(SHORTHAND_BASE, ("checks CL-001-01/02 offline", "checks offline")),
             "proven clause-list 'TC-001-003' Requirements.sysml -> Requirements.sysml")
# A bold wording in the middle of a line: in a base whose TC-001-002 holds one.
SECOND_AUTOMATION = ("        attribute automation : AutomationState = AutomationState::planned;\n"
                     "        objective { verify 'CL-001-01'; verify 'CL-001-02'; }\n")
MID_BOLD_BASE = edits(BASE, ("Expected: shown.", "Expected: shown. **Level: 4 — Controlled live tests with operator consent.** Then."))
MID_BOLD = (MID_BOLD_BASE, edits(MID_BOLD_BASE, ("shown. **Level: 4 — Controlled live tests with operator consent.** Then.",
                                                 "shown. Then."),
                                 (SECOND_AUTOMATION,
                                  "        @TestLevel { cost = 4; location = TestLocation::flexRadio; }\n" + SECOND_AUTOMATION)),
            "proven cost 'TC-001-002' Requirements.sysml -> Requirements.sysml")
# An attribute the catalog does not read for a case: in a base whose TC-001-002 holds one.
FOREIGN_BASE = edits(BASE, (SECOND_AUTOMATION, '        attribute implementation : String = "server/a.rs";\n' + SECOND_AUTOMATION))
# The status forms #205 left (#219), in a base that holds each: qualified coverage on a named
# requirement without identity, on an attribute definition and on a clause; qualified automation
# and an executable on a verification without identity; a free-text method.
NAMED_COVERAGE = "        attribute coverage : ModelBindings::ImplementationState = ModelBindings::ImplementationState::partial;\n"
POLICY_COVERAGE = "        attribute coverage : ModelBindings::ImplementationState = ModelBindings::ImplementationState::implemented;\n"
GRAPH_AUTOMATION = "        attribute automation : ModelBindings::AutomationState = ModelBindings::AutomationState::implemented;\n"
GRAPH_EXECUTABLE = '        attribute executable : String = "tools/sysml.py check; tools/sysml/tests/test_a.py";\n'
OTHER_METHOD = '        attribute method : String = "manual independent contract correspondence review";\n'
THIRD_COVERAGE = "        attribute coverage : ModelBindings::ImplementationState = ModelBindings::ImplementationState::target;\n"
LEFT_BASE = edits(BASE, ("        doc /* Level 2 isolated model test. */\n",
                         "        doc /* Level 2 isolated model test. */\n" + GRAPH_AUTOMATION + GRAPH_EXECUTABLE),
                  ("        doc /* Level 2 other model test. */\n", "        doc /* Level 2 other model test. */\n" + OTHER_METHOD),
                  ("        doc /* The third clause. */\n        attribute coverage : ImplementationState = ImplementationState::target;\n",
                   "        doc /* The third clause. */\n" + THIRD_COVERAGE),
                  ("    verification ResolvedArchitectureGraph {",
                   "    requirement NamedClause {\n        doc /* A named requirement without identity. */\n" + NAMED_COVERAGE
                   + "    }\n    attribute def Policy {\n" + POLICY_COVERAGE
                   + "        attribute bounded : Boolean = true;\n    }\n    verification ResolvedArchitectureGraph {"))
# P1: each left form converted alone in LEFT_BASE: (head, the one expected proven line).
LEFT = {
    "status qualified coverage on a named requirement": (
        edits(LEFT_BASE, (NAMED_COVERAGE, "        @Status { build = ImplementationState::partial; }\n")),
        "proven status NamedClause Requirements.sysml -> Requirements.sysml"),
    "status qualified coverage on an attribute def": (
        edits(LEFT_BASE, (POLICY_COVERAGE, "        @ModelBindings::Status { build = ModelBindings::ImplementationState::implemented; }\n")),
        "proven status Policy Requirements.sysml -> Requirements.sysml"),
    "status qualified coverage on a clause": (
        edits(LEFT_BASE, (THIRD_COVERAGE, "        @Status { build = ImplementationState::target; }\n")),
        "proven status 'CL-001-03' Requirements.sysml -> Requirements.sysml"),
    "status qualified automation without identity": (
        edits(LEFT_BASE, (GRAPH_AUTOMATION, "        @Automation { run = AutomationState::implemented; }\n")),
        "proven status ResolvedArchitectureGraph Requirements.sysml -> Requirements.sysml"),
    "status executable without identity": (
        edits(LEFT_BASE, (GRAPH_EXECUTABLE, '        @TestedBy { test = "tools/sysml.py check; tools/sysml/tests/test_a.py"; }\n')),
        "proven status ResolvedArchitectureGraph Requirements.sysml -> Requirements.sysml"),
    "status free-text method": (
        edits(LEFT_BASE, (OTHER_METHOD, '        @Automation { method = "manual independent contract correspondence review"; }\n')),
        "proven status OtherGraph Requirements.sysml -> Requirements.sysml"),
}
# P2: the same conversions with a changed value, and a removal with no metadata, in LEFT_BASE:
# (head, the start of the line that names the attribute).
LEFT_UNPROVEN = {
    "a named requirement's state changed": (
        edits(LEFT_BASE, (NAMED_COVERAGE, "        @Status { build = ImplementationState::target; }\n")),
        "missing NamedClause::coverage R Requirements.sysml"),
    "a qualification naming another enumeration": (
        edits(LEFT_BASE, (NAMED_COVERAGE, "        @Status { build = ModelBindings::AutomationState::partial; }\n")),
        "missing NamedClause::coverage R Requirements.sysml"),
    "an attribute def's state changed": (
        edits(LEFT_BASE, (POLICY_COVERAGE, "        @Status { build = ImplementationState::partial; }\n")),
        "missing Policy::coverage R Requirements.sysml"),
    "an executable without identity changed": (
        edits(LEFT_BASE, (GRAPH_EXECUTABLE, '        @TestedBy { test = "tools/sysml.py check"; }\n')),
        "missing ResolvedArchitectureGraph::executable R Requirements.sysml"),
    "a free-text method changed": (
        edits(LEFT_BASE, (OTHER_METHOD, '        @Automation { method = "manual contract correspondence review"; }\n')),
        "missing OtherGraph::method R Requirements.sysml"),
    "a named requirement's coverage removed without its metadata": (
        edits(LEFT_BASE, (NAMED_COVERAGE, "")), "missing NamedClause::coverage R Requirements.sysml"),
}
# P2: a difference as today: (base, head) with exit 1 and no proven line.
UNPROVEN = {
    "another case's number": (BASE, edits(BASE, ("See TC-001-002 and", "See and"))),
    "TC001001": (BASE, edits(BASE, (" and TC001001.", "."))),
    "a clause list with one clause more": (edits(BASE, (ALSO[0], ALSO[1].format("CL-001-01, CL-001-02, CL-001-03"))),
                                           edits(BASE, (ALSO[0], ALSO[1].format("")))),
    "a clause list with one clause fewer": (edits(BASE, (ALSO[0], ALSO[1].format("CL-001-01"))),
                                            edits(BASE, (ALSO[0], ALSO[1].format("")))),
    "a clause list naming a TC": (edits(BASE, (ALSO[0], ALSO[1].format("CL-001-01, CL-001-02, TC-001-002"))),
                                  edits(BASE, (ALSO[0], ALSO[1].format("")))),
    "a cost wording with a wrong pair": (BASE, edits(BASE, (COST_LINE, "             no radio. */\n"),
                                                     (FIRST_AUTOMATION, STATION + FIRST_AUTOMATION))),
    "a cost wording with no TestLevel": (BASE, edits(BASE, (COST_LINE, "             no radio. */\n"))),
    "a cost wording with an extra pair": (BASE, edits(BASE, (COST_LINE, "             no radio. */\n"),
                                                      (FIRST_AUTOMATION, DEV + STATION + FIRST_AUTOMATION))),
    "an element wording in another element": (BASE, edits(BASE, ("doc /* Level 2 other model test. */",
                                                                 "doc /* other model test. */\n" + DEV))),
    "a line wording not at a line start": (BASE, edits(BASE, ("| 2 — Isolated automated tests | table |", "| | table |"),
                                                       ("        attribute automation : AutomationState = AutomationState::planned;\n"
                                                        "        objective { verify 'CL-001-01'; verify 'CL-001-02'; }\n",
                                                        DEV + "        attribute automation : AutomationState = "
                                                        "AutomationState::planned;\n"
                                                        "        objective { verify 'CL-001-01'; verify 'CL-001-02'; }\n"))),
    "a dependency whose case no longer verifies the clause": (BASE, edits(BASE, (
        "    dependency CL_001_02_verified_by_TC_001_001 from 'CL-001-02' to 'TC-001-001';\n", ""),
        ("            verify 'CL-001-02';\n        }\n", "        }\n"))),
    "a dependency to an FR": (BASE, edits(BASE, ("    dependency CL_001_01_to_FR_001 from 'CL-001-01' to 'FR-001';\n", ""))),
    "a status value changed": (BASE, edits(BASE, ("        attribute automation : AutomationState = AutomationState::planned;\n"
                                                  "        objective { verify 'CL-001-01'; verify 'CL-001-02'; }\n",
                                                  "        @Automation { run = AutomationState::partial; }\n"
                                                  "        objective { verify 'CL-001-01'; verify 'CL-001-02'; }\n"))),
    "an attribute removed without its metadata": (BASE, edits(BASE, (FIRST_EXECUTABLE, ""))),
    "one other word changed beside proven spans": (BASE, edits(BASE, ("#### TC-001-001 — First case", "First case"),
                                                               ("Steps: open and check.", "Steps: open and look."))),
    # Review of db2b018ab: whitespace alone is no proven removal.
    "whitespace only": (BASE, edits(BASE, ("Steps: open and check.", "Steps:  open and check."))),
    "two lines joined": (BASE, edits(BASE, ("CL-001-01, CL-001-02\n             | 2 —", "CL-001-01, CL-001-02 | 2 —"))),
    # An attribute the catalog does not read for a case, removed with no metadata.
    "an attribute the catalog does not read for the kind": (FOREIGN_BASE, BASE),
    # A bold wording at a line start with the wrong pair on the head.
    "a bold wording at a line start with a wrong pair": (BASE, edits(
        BASE, ("**Level: 3 — Live read-only tests.** Watch it.", "Watch it."),
        ("verify 'CL-001-03'; }\n", "verify 'CL-001-03'; }\n        @TestLevel { cost = 3; location = TestLocation::station; }\n"))),
}
# P3: all five rules in TC-001-001 at once, one of its two verified_by dependencies removed.
ALL = edits(BASE, ("#### TC-001-001 — First case", "First case"), ("Proves CL-001-01, CL-001-02. See", "See"),
            (COST_LINE, "             no radio. */\n"), (DEPENDENCY, ""),
            (FIRST_AUTOMATION + FIRST_METHOD, DEV + '        @Automation { run = AutomationState::implemented; method = "automated"; }\n'),
            (FIRST_EXECUTABLE, '        @TestedBy { test = "tests/a.test.cjs"; }\n'))
ALL_LINES = [
    "proven case-number 'TC-001-001' Requirements.sysml -> Requirements.sysml",
    "proven clause-list 'TC-001-001' Requirements.sysml -> Requirements.sysml",
    "proven cost 'TC-001-001' Requirements.sysml -> Requirements.sysml",
    "proven dependency CL_001_01_verified_by_TC_001_001 Requirements.sysml -> Requirements.sysml",
    "proven status 'TC-001-001' Requirements.sysml -> Requirements.sysml",
]


def run(*argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = tool.main(["--cache-dir", str(CACHE), *argv])
    return code, out.getvalue(), err.getvalue()


def proven_lines(lines: list[str]) -> list[str]:
    return [line for line in lines if line.startswith("proven ")]


class ProvenRemovalTests(unittest.TestCase):
    """P1 to P3 on one temporary repository, compared in one batch."""

    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        cls.repository = Repository(Path(cls.folder.name))
        commits = {}

        def sha(files):
            key = tuple(sorted(files.items()))
            if key not in commits:
                commits[key] = cls.repository.commit(files)
            return commits[key]

        cases = {name: (BASE, head) for name, (head, _line) in SINGLE.items()}
        cases["clause-list shorthand"] = SHORTHAND[:2]
        cases["cost bold wording mid-line"] = MID_BOLD[:2]
        cases.update(UNPROVEN)
        cases.update({name: (LEFT_BASE, head) for name, (head, _line) in {**LEFT, **LEFT_UNPROVEN}.items()})
        cases["all five"] = (BASE, ALL)
        names = list(cases)
        pairs = [(sha(base), sha(head)) for base, head in cases.values()]
        cls.base, cls.all = sha(BASE), sha(ALL)
        cls.patch = mock.patch.object(tool, "ROOT", cls.repository.root)
        cls.patch.start()
        results, _exports = tool.compare_revisions(pairs, CACHE)
        cls.results = dict(zip(names, results))

    @classmethod
    def tearDownClass(cls):
        cls.patch.stop()
        cls.folder.cleanup()

    def shown(self, name):
        return f"{name}:\n" + "\n".join(self.results[name][1])

    # P1: each rule alone, exit 0, its proven line and `; proven: 1`
    # Proves: CL-014-22; TC-DOC-020
    def test_p1_each_rule_alone_is_proven(self):
        expected = {name: line for name, (_head, line) in SINGLE.items()}
        expected["clause-list shorthand"] = SHORTHAND[2]
        expected["cost bold wording mid-line"] = MID_BOLD[2]
        expected.update({name: line for name, (_head, line) in LEFT.items()})
        for name, line in expected.items():
            with self.subTest(name):
                code, lines = self.results[name]
                self.assertEqual(code, 0, self.shown(name))
                self.assertEqual(proven_lines(lines), [line], self.shown(name))
                self.assertTrue(lines[-1].startswith("equivalent: ") and lines[-1].endswith("; proven: 1"), self.shown(name))

    # P2: a difference as today, exit 1 and no proven line
    # Proves: CL-014-22; TC-DOC-020
    def test_p2_an_unproven_removal_is_a_difference(self):
        for name in list(UNPROVEN) + list(LEFT_UNPROVEN):
            with self.subTest(name):
                code, lines = self.results[name]
                self.assertEqual(code, 1, self.shown(name))
                self.assertEqual(proven_lines(lines), [], self.shown(name))
                self.assertNotIn("; proven:", lines[-1], self.shown(name))
        with self.subTest("each as today: the element or entry named"):
            for name, prefix in (("TC001001", "changed 'TC-001-001' doc "),
                                 ("an element wording in another element", "changed OtherGraph "),
                                 ("a dependency to an FR", "missing CL_001_01_to_FR_001 R Requirements.sysml"),
                                 ("a dependency whose case no longer verifies the clause",
                                  "missing CL_001_02_verified_by_TC_001_001 R Requirements.sysml"),
                                 ("an attribute removed without its metadata",
                                  "missing 'TC-001-001'::executable R Requirements.sysml"),
                                 ("whitespace only", "changed 'TC-001-001' doc "),
                                 ("two lines joined", "changed 'TC-001-002' doc "),
                                 ("an attribute the catalog does not read for the kind",
                                  "missing 'TC-001-002'::implementation R Requirements.sysml"),
                                 ("a bold wording at a line start with a wrong pair", "changed 'TC-001-003' "),
                                 *((name, prefix) for name, (_head, prefix) in LEFT_UNPROVEN.items())):
                self.assertTrue(any(line.startswith(prefix) for line in self.results[name][1]), self.shown(name))

    # P3: all five rules in one case at once; and a marked commit doing this
    # Proves: CL-014-22; TC-DOC-020
    def test_p3_all_five_rules_at_once(self):
        code, lines = self.results["all five"]
        self.assertEqual(code, 0, self.shown("all five"))
        self.assertEqual(proven_lines(lines), ALL_LINES, self.shown("all five"))
        self.assertTrue(lines[-1].endswith("; proven: 5"), lines[-1])
        repository = self.repository
        repository.git("checkout", "-q", "-B", "master", self.base)
        repository.git("checkout", "-q", "-b", "p3")
        marked = repository.commit(ALL, "Convert TC-001-001\n\nModel-Move: pure")
        code, out, _err = run("equivalence", "--marked")
        self.assertEqual(code, 0, out)
        self.assertIn(f"checked {marked}", out.splitlines())
        self.assertIn(f"commit {marked}: equivalent", out.splitlines())
        self.assertIn("1 marked commits checked; all equivalent", out.splitlines())


class MappingFileTests(unittest.TestCase):
    # P4: the mapping file missing, not JSON, or an entry with cost 7: exit 2 naming the file
    # Proves: CL-014-22; TC-DOC-020
    def test_p4_a_missing_or_malformed_mapping_cannot_compare(self):
        real = json.loads(tool.COST_WORDINGS.read_text(encoding="utf-8"))
        seven = json.loads(json.dumps(real))
        seven["line"][0]["cost"] = 7
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "repo").mkdir()
            repository = Repository(Path(folder) / "repo")
            base = repository.commit(BASE)
            head = repository.commit(SINGLE["dependency"][0])
            mapping = Path(folder) / "wordings.json"
            for label, text in (("missing", None), ("not JSON", "{ line: [ }"), ("cost 7", json.dumps(seven))):
                with self.subTest(label):
                    if text is None:
                        mapping.unlink(missing_ok=True)
                    else:
                        mapping.write_text(text, encoding="utf-8")
                    with mock.patch.object(tool, "ROOT", repository.root), mock.patch.object(tool, "COST_WORDINGS", mapping), \
                            mock.patch.object(tool, "run_export", side_effect=AssertionError("exported")):
                        code, out, err = run("equivalence", base, head)
                    self.assertEqual((code, out), (2, ""))
                    self.assertTrue(err.startswith("SysML check failed: ") and str(mapping) in err, err)


def doc_texts(export: dict, side) -> list[tuple[dict, str]]:
    """(entry, doc text as `equivalence` reads it) of every doc of an export."""
    normal = tool.Normal(side, lambda key: key)
    return [(entry, normal.text(value, entry["file"])) for entry in export["entries"].values()
            for path, kind, _feature, value in entry["facts"] if kind == "text" and path.endswith("/Documentation[0]")]


class MappingGuardTests(unittest.TestCase):
    # P5: each wording of the mapping occurs on the model of the pinned base commit
    # Proves: CL-014-22; TC-DOC-020
    def test_p5_mapping_matches_the_pinned_model(self):
        wordings = tool.cost_wordings()
        with tempfile.TemporaryDirectory() as folder:
            commit = tool.commit_of(PINNED)
            tool.extract(commit, Path(folder) / "pinned", ["docs/sysml"])
            side = tool.Side("pinned", Path(folder) / "pinned", commit)
            export = tool.run_export(side, [], CACHE, Path(folder))
            side.export = export
        docs = doc_texts(export, side)
        lines = [(entry, line.strip()) for entry, text in docs for line in text.split("\n")]
        for wording, _cost, _place in wordings["line"]:
            with self.subTest(line=wording):
                self.assertTrue(any(line.startswith(wording) for _entry, line in lines), wording)
        for wording, _cost, _place in wordings["bold"]:
            # At a line start the Pilot's doc text has lost the first `*` of the comment line.
            with self.subTest(bold=wording):
                self.assertTrue(any(wording in text for _entry, text in docs)
                                or any(line.startswith(wording[1:]) for _entry, line in lines), wording)
        for file, name, wording, _cost, _place in wordings["element"]:
            segments = [f"'{part}'" if re.fullmatch(tool.IDENTITY, part) else part for part in name.split("::")]
            with self.subTest(element=f"{file} {name} {wording}"):
                own = [text for entry, text in docs if entry["file"] == file and entry["rel"].split("::")[-len(segments):] == segments]
                self.assertTrue(own, f"no element {name} in {file}")
                self.assertTrue(any(wording in text for text in own), wording)
        listed = [wording for wording, _cost, _place in wordings["line"]]
        for entry, line in lines:
            kind = next((value for path, sort, _feature, value in entry["facts"] if path == "" and sort == "kind"), None)
            if kind in tool.VERIFICATION_KINDS and re.match(r"[1-5] — ", line):
                with self.subTest(verification=f"{entry['file']} {entry['rel']}: {line[:60]}"):
                    self.assertTrue(any(line.startswith(wording) for wording in listed), line)


SCREEN, LOGBOOK = "docs/sysml/frontend/OperatingScreen.sysml", "docs/sysml/backend/log/Logbook.sysml"
SCREEN_EDITS = (
    ("        doc /* #### TC-007-002 — Read-only operating layout slice\n\n"
     "             Proves CL-010-05, CL-010-07, CL-010-08. Cost level 2: offline integration tests on\n",
     "        doc /* Read-only operating layout slice\n\n             offline integration tests on\n"),
    ("        attribute automation : AutomationState = AutomationState::implemented;\n        objective {\n"
     "            verify 'CL-010-05';\n            verify 'CL-010-07';\n            verify 'CL-010-08';\n        }\n"
     '        attribute executable : String = "tests/receive-integration.test.cjs; tests/ui-operating.test.cjs; '
     'tests/contact.test.cjs; tests/receive-page.test.cjs; server/src/receive_http_tests.rs";\n',
     "        @ModelBindings::Automation { run = AutomationState::implemented; }\n"
     "        @ModelBindings::TestLevel { cost = 2; location = ModelBindings::TestLocation::developmentPc; }\n"
     "        objective {\n"
     "            verify 'CL-010-05';\n            verify 'CL-010-07';\n            verify 'CL-010-08';\n        }\n"
     '        @ModelBindings::TestedBy { test = "tests/receive-integration.test.cjs; tests/ui-operating.test.cjs; '
     'tests/contact.test.cjs; tests/receive-page.test.cjs; server/src/receive_http_tests.rs"; }\n'),
    ("    dependency CL_010_05_verified_by_TC_007_002 from 'CL-010-05' to 'TC-007-002';\n", ""),
    ("    dependency CL_010_07_verified_by_TC_007_002 from 'CL-010-07' to 'TC-007-002';\n", ""),
    ("    dependency CL_010_08_verified_by_TC_007_002 from 'CL-010-08' to 'TC-007-002';\n", ""),
)
LOGBOOK_EDITS = (
    ("        doc /* TC-085-006 — Live\n             CL-085-01, CL-085-02\n             Setup:",
     "        doc /* Live\n             Setup:"),
    ("             5 — Live on the station with the operator's consent; HB9BLA. Not run by the\n",
     "             Not run by the\n"),
    ("        attribute automation : AutomationState = AutomationState::planned;\n        objective {\n"
     "            verify 'CL-085-01';\n            verify 'CL-085-02';\n",
     "        @ModelBindings::Automation { run = AutomationState::planned; }\n"
     "        @ModelBindings::TestLevel { cost = 5; location = ModelBindings::TestLocation::station; }\n"
     "        objective {\n            verify 'CL-085-01';\n            verify 'CL-085-02';\n"),
)
REAL_LINES = [
    "proven case-number 'TC-007-002' frontend/OperatingScreen.sysml -> frontend/OperatingScreen.sysml",
    "proven case-number 'TC-085-006' backend/log/Logbook.sysml -> backend/log/Logbook.sysml",
    "proven clause-list 'TC-007-002' frontend/OperatingScreen.sysml -> frontend/OperatingScreen.sysml",
    "proven clause-list 'TC-085-006' backend/log/Logbook.sysml -> backend/log/Logbook.sysml",
    "proven cost 'TC-007-002' frontend/OperatingScreen.sysml -> frontend/OperatingScreen.sysml",
    "proven cost 'TC-085-006' backend/log/Logbook.sysml -> backend/log/Logbook.sysml",
    "proven dependency CL_010_05_verified_by_TC_007_002 frontend/OperatingScreen.sysml -> frontend/OperatingScreen.sysml",
    "proven dependency CL_010_07_verified_by_TC_007_002 frontend/OperatingScreen.sysml -> frontend/OperatingScreen.sysml",
    "proven dependency CL_010_08_verified_by_TC_007_002 frontend/OperatingScreen.sysml -> frontend/OperatingScreen.sysml",
    "proven status 'TC-007-002' frontend/OperatingScreen.sysml -> frontend/OperatingScreen.sysml",
    "proven status 'TC-085-006' backend/log/Logbook.sysml -> backend/log/Logbook.sysml",
]


class RealModelTests(unittest.TestCase):
    # P6: TC-007-002 and TC-085-006 of P6_BASE converted by the five rules in a temporary repository
    # Proves: CL-014-22; TC-DOC-020
    def test_p6_real_cases_converted_are_equivalent(self):
        status = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"], capture_output=True, text=True).stdout
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        with tempfile.TemporaryDirectory() as folder:
            clone = Path(folder) / "head"
            subprocess.run(["git", "clone", "-q", "--shared", "--no-checkout", str(ROOT), str(clone)],
                           check=True, capture_output=True, env=env)
            repository = Repository.__new__(Repository)
            repository.root = clone
            base = tool.commit_of(P6_BASE)
            repository.git("checkout", "-q", "--detach", base)
            for path, changes in ((SCREEN, SCREEN_EDITS), (LOGBOOK, LOGBOOK_EDITS)):
                file = clone / path
                text = file.read_text(encoding="utf-8")
                for old, new in changes:
                    self.assertEqual(text.count(old), 1, (path, old[:80]))
                    text = text.replace(old, new)
                file.write_text(text, encoding="utf-8", newline="")
            repository.git("commit", "-q", "-a", "-m", "Convert TC-007-002 and TC-085-006")
            head = repository.git("rev-parse", "HEAD")
            with mock.patch.object(tool, "ROOT", clone):
                results, _exports = tool.compare_revisions([(base, head)], CACHE)
                code, lines = results[0]
                entries = tool.canonical_catalog(clone / "docs/sysml", clone)
                tool.binding_agreement(entries, clone)
            shutil.rmtree(clone, ignore_errors=True)
        self.assertEqual(code, 0, "\n".join(line for line in lines if not line.startswith(("unresolved", "moved")))[:6000])
        self.assertEqual(proven_lines(lines), REAL_LINES, "\n".join(proven_lines(lines)))
        self.assertTrue(lines[-1].startswith("equivalent: ") and lines[-1].endswith("; proven: 11"), lines[-1])
        self.assertEqual(entries["TC-007-002"]["levels"], [(2, "developmentPc")])
        self.assertEqual(entries["TC-085-006"]["levels"], [(5, "station")])
        self.assertEqual(subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"], capture_output=True, text=True).stdout, status)


if __name__ == "__main__":
    unittest.main()
