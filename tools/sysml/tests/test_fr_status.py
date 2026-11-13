"""CL-014-19 and CL-014-05 (#183 T1, S9a): an FR's status is computed from its clauses, and a
clause derived from its FR by a derivation connection is owned by it.

Isolated fixtures in a temporary folder; every expected line is counted by hand from the
clause states below. One test runs the real pinned Pilot on the derivation form.
"""
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import re
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("fr_status_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
MARKER = "// Canonical authority: SysML\n"
ENUMS = '''    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
'''
# Per FR the states of its clauses: the first clause is owned by a dependency, the second by
# a derivation. FR-901 to FR-906 state no status and no binding; FR-907 and FR-908 state one.
CLAUSES = {
    "FR-901": ("implemented", "implemented"),
    "FR-902": ("partial", "partial"),
    "FR-903": ("implemented", "target"),
    "FR-904": ("implemented", "partial"),
    "FR-905": ("target", "target"),
    "FR-906": (),
    "FR-907": ("implemented",),
    "FR-908": (),
}
STATED = {"FR-907": "target", "FR-908": "target"}
# Counted by hand from CLAUSES and STATED (#53 item 6: implemented when all clauses are,
# target when all are or there is none, partial otherwise).
STATUS = '''FR-901 implemented: 2 clauses, 2 implemented, 0 partial, 0 target
FR-902 partial: 2 clauses, 0 implemented, 2 partial, 0 target
FR-903 partial: 2 clauses, 1 implemented, 0 partial, 1 target
FR-904 partial: 2 clauses, 1 implemented, 1 partial, 0 target
FR-905 target: 2 clauses, 0 implemented, 0 partial, 2 target
FR-906 target: 0 clauses, 0 implemented, 0 partial, 0 target
FR-907 implemented: 1 clauses, 1 implemented, 0 partial, 0 target; stated target
FR-908 target: 0 clauses, 0 implemented, 0 partial, 0 target
8 FRs: 2 implemented, 3 partial, 3 target
'''


def clause_id(fr, index):
    return f"CL-{fr[3:]}-0{index + 1}"


def requirement(identity, state=None):
    body = f"        attribute coverage : ImplementationState = ImplementationState::{state};\n" if state else ""
    if state in ("partial", "implemented"):
        body += '        attribute implementation : String = "server/module.rs";\n'
    return f"    requirement '{identity}' {{\n{body}    }}\n"


def derivation(original, derived):
    return f"    #derivation connection {{\n        end #original ::> '{original}';\n        end #derive ::> '{derived}';\n    }}\n"


def catalog():
    """The synthetic catalog of CLAUSES: one case verifies every clause; a clause owned by a
    dependency has the reciprocal dependency to the case, a derived one has none."""
    text, links, verified = MARKER + "package WstxRequirements {\n" + ENUMS, "", []
    for fr, states in CLAUSES.items():
        text += requirement(fr, STATED.get(fr))
        for index, state in enumerate(states):
            clause = clause_id(fr, index)
            text += requirement(clause, state)
            verified.append(clause)
            if index == 0:
                links += f"    dependency owns from '{clause}' to '{fr}';\n    dependency checks from '{clause}' to 'TC-001-001';\n"
            else:
                links += derivation(fr, clause)
    text += ("    verification 'TC-001-001' {\n        attribute automation : AutomationState = AutomationState::planned;\n"
             "        objective { " + " ".join(f"verify '{clause}';" for clause in verified) + " }\n    }\n")
    return text + links + "}\n"


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        (self.root / "server/module.rs").write_text("pub fn step() {}\n", encoding="utf-8")
        self.models = self.root / "docs/sysml"
        self.write("Architecture.sysml", "package WstxArchitecture {}\n")

    def write(self, key, text):
        path = self.models / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="")

    def check(self):
        return tool.canonical_catalog(self.models, self.root, required=set())

    def refused(self, message):
        return self.assertRaisesRegex(ValueError, message)

    def main(self, command):
        """Run one command on the fixture, with the Pilot and every process forbidden."""
        real_catalog = tool.canonical_catalog
        output, errors = io.StringIO(), io.StringIO()
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), \
                mock.patch.object(tool, "FSD", self.root / "docs/FSD.md"), \
                mock.patch.object(tool, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=set())), \
                mock.patch.object(tool, "validate", side_effect=AssertionError("validator invoked")), \
                mock.patch.object(tool.subprocess, "run", side_effect=AssertionError("process started")), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main([command])
        return status, output.getvalue(), errors.getvalue()


class ComputedStatusTests(Fixture):
    # T1: the status of each FR from the states of its clauses, by dependency and by derivation
    # Proves: CL-014-19; TC-DOC-017
    def test_status_prints_each_fr_computed_from_its_clauses(self):
        self.write("Requirements.sysml", catalog())
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(self.main("status"), (0, STATUS, ""))
        with self.subTest("nothing written"):
            self.assertEqual({path: hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in self.root.rglob("*") if path.is_file()}, before)

    # T1: an FR states no status and no binding; its entry carries the computed status
    # Proves: CL-014-19; TC-DOC-017
    def test_fr_without_a_stated_status_or_binding_is_accepted_with_the_computed_status(self):
        self.write("Requirements.sysml", catalog())
        entries = self.check()
        unstated = [fr for fr in CLAUSES if fr not in STATED]
        self.assertEqual([re.search(r"requirement '" + fr + r"' \{\n    \}", catalog()) is not None for fr in unstated],
                         [True] * len(unstated))
        self.assertEqual({fr: (entries[fr]["stated"], entries[fr]["status"], entries[fr]["bindings"]) for fr in CLAUSES}, {
            "FR-901": (None, "implemented", []), "FR-902": (None, "partial", []), "FR-903": (None, "partial", []),
            "FR-904": (None, "partial", []), "FR-905": (None, "target", []), "FR-906": (None, "target", []),
            "FR-907": ("target", "implemented", []), "FR-908": ("target", "target", []),
        })
        with self.subTest("both forms of ownership count"):
            self.assertEqual(entries["FR-904"]["clauses"], ["CL-904-01", "CL-904-02"])

    # T1: a broken catalog
    # Proves: CL-014-19; TC-DOC-017
    def test_status_on_a_broken_catalog_exits_2_with_the_catalog_message(self):
        self.write("Requirements.sysml", catalog().replace(derivation("FR-901", "CL-901-02"), ""))
        self.assertEqual(self.main("status"),
                         (2, "", "SysML check failed: Canonical clause lacks requirement ownership: CL-901-02\n"))
        self.write("Requirements.sysml", catalog().removeprefix(MARKER))
        status, output, errors = self.main("status")
        self.assertEqual((status, output), (2, ""))
        self.assertIn("No declared functional authority", errors)


# S9a: one FR, one case; the clause CL-901-01 owned by derivation or dependency.
FR_ONLY = requirement("FR-901")
CLAUSE = requirement("CL-901-01", "target")
CASE = '''    verification 'TC-001-001' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'CL-901-01'; }
    }
'''
OWNS = "    dependency owns from 'CL-901-01' to 'FR-901';\n"
CHECKS = "    dependency checks from 'CL-901-01' to 'TC-001-001';\n"
DERIVED = derivation("FR-901", "CL-901-01")


def model(*parts):
    return MARKER + "package WstxRequirements {\n" + ENUMS + FR_ONLY + CLAUSE + "".join(parts) + "}\n"


class DerivationOwnershipTests(Fixture):
    # S9a, accepted: owned by the derivation and verified by the case, no dependency
    # Proves: CL-014-05; TC-DOC-002
    def test_derived_clause_is_owned_and_verified_without_a_dependency(self):
        forms = {
            "as written": DERIVED,
            "package names": DERIVED.replace("#derivation", "#RequirementDerivation::derivation")
                                    .replace("'FR-901'", "WstxRequirements::'FR-901'")
                                    .replace("#derive ::>", "#RequirementDerivation::derive ::>"),
            "named, on one line": "    #derivation connection owning : Derivation { end #original ::> 'FR-901'; end #derive ::> 'CL-901-01'; }\n",
        }
        for label, text in forms.items():
            with self.subTest(label):
                self.write("Requirements.sysml", model(CASE, text))
                entries = self.check()
                self.assertEqual((entries["FR-901"]["clauses"], entries["TC-001-001"]["refs"]), (["CL-901-01"], ["CL-901-01"]))
        with self.subTest("both dependencies, no derivation: as today"):
            self.write("Requirements.sysml", model(CASE, OWNS, CHECKS))
            self.assertEqual(self.check()["FR-901"]["clauses"], ["CL-901-01"])
        with self.subTest("a case verifying a derived clause and a clause owned by dependency"):
            second = requirement("CL-901-02", "target")
            self.write("Requirements.sysml", model(second, CASE.replace("verify 'CL-901-01';", "verify 'CL-901-01'; verify 'CL-901-02';"),
                                                   DERIVED, OWNS.replace("CL-901-01", "CL-901-02"),
                                                   CHECKS.replace("CL-901-01", "CL-901-02")))
            self.assertEqual(self.check()["FR-901"]["clauses"], ["CL-901-01", "CL-901-02"])

    # S9a, refused, each with its message
    # Proves: CL-014-05; TC-DOC-002
    def test_clause_without_an_owner_or_a_verifying_case_is_refused(self):
        refused = {
            "neither derivation nor dependency to an FR": (model(CASE, CHECKS), "Canonical clause lacks requirement ownership: CL-901-01$"),
            "derived, no verifying case": (model(CASE.replace("verify 'CL-901-01';", "verify 'FR-901';"), DERIVED),
                                           "Canonical clauses lack verification links: CL-901-01$"),
            "the FR dependency, no dependency to its case": (model(CASE, OWNS), "Canonical clause lacks a declared verification case: CL-901-01$"),
            "a case verifying a clause owned by dependency without the reciprocal one":
                (model(requirement("CL-901-02", "target"), CASE.replace("verify 'CL-901-01';", "verify 'CL-901-01'; verify 'CL-901-02';"),
                       DERIVED, OWNS.replace("CL-901-01", "CL-901-02"), "    dependency checks from 'CL-901-02' to 'TC-001-002';\n",
                       CASE.replace("TC-001-001", "TC-001-002").replace("'CL-901-01'", "'CL-901-02'")),
                 "Nonreciprocal canonical verification links: TC-001-001$"),
            "derived from an FR that does not exist": (model(CASE, derivation("FR-999", "CL-901-01")),
                                                       "Invalid canonical clause dependency: CL-901-01 -> FR-999$"),
            "deriving an FR": (model(CASE, DERIVED, derivation("FR-901", "FR-901")),
                               "Invalid canonical clause dependency: FR-901 -> FR-901$"),
        }
        for label, (text, message) in refused.items():
            with self.subTest(label), self.refused(message):
                self.write("Requirements.sysml", text)
                self.check()
        # Line 14 is the line of the connection: the marker, the package, two enums, the
        # two-line FR, the three-line clause and the four-line case come first.
        malformed = {
            "no derive end": "    #derivation connection { end #original ::> 'FR-901'; }\n",
            "two originals": "    #derivation connection { end #original ::> 'FR-901'; end #original ::> 'FR-901'; end #derive ::> 'CL-901-01'; }\n",
            "another statement": "    #derivation connection { end #original ::> 'FR-901'; end #derive ::> 'CL-901-01'; doc /* x */ }\n",
            "an unquoted end": "    #derivation connection { end #original ::> FR; end #derive ::> 'CL-901-01'; }\n",
        }
        for label, text in malformed.items():
            with self.subTest(malformed=label), self.refused(r"Invalid canonical derivation: Requirements\.sysml:14$"):
                self.write("Requirements.sysml", model(CASE, text))
                self.check()


class DerivationOnThePilotTests(unittest.TestCase):
    # S9a: the derivation form of the model library is legal in the pinned Pilot, as the tool reads it.
    # Proves: CL-014-05; TC-DOC-002
    def test_real_pilot_resolves_the_derivation_form_the_catalog_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            models = root / "docs/sysml"
            models.mkdir(parents=True)
            for name in tool.SOURCE_BINDING_ROOTS:
                (root / name).mkdir()
            text = model(CASE, DERIVED).replace("package WstxRequirements {\n",
                                                "package WstxRequirements {\n    private import RequirementDerivation::*;\n")
            (models / "Requirements.sysml").write_text(text, encoding="utf-8")
            (models / "Architecture.sysml").write_text("package WstxArchitecture {}\n", encoding="utf-8")
            self.assertEqual(tool.canonical_catalog(models, root, required=set())["FR-901"]["clauses"], ["CL-901-01"])
            result = tool.validate([models / "Requirements.sysml", models / "Architecture.sysml"], CACHE)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed.", result.stdout)


if __name__ == "__main__":
    unittest.main()
