"""TC-DOC-013: a verification case retires into the detail tests of its part (CL-014-15).

Isolated fixtures in a temporary folder; every expected message, line and listing is
written by hand from the fixture lines below. One test runs the real pinned Pilot, and two
build a throwaway git repository for the gate's model bindings.
"""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("case_retirement_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
REQUIRED = {"FR-001", "CL-003-01", "TC-001-001"}
# The baseline of a model from which TC-001-002 was removed and retired.
RETIRED = REQUIRED | {"TC-001-002"}
MARKER = "// Canonical authority: SysML\n"
REQUIRED_FILES = {"Requirements.sysml": "WstxRequirements", "Architecture.sysml": "WstxArchitecture"}
ENUMS = '''    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
'''
FR = '''    requirement 'FR-001' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
'''
CLAUSE = '''    requirement 'CL-003-01' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
'''
CASE = '''    verification 'TC-001-001' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'FR-001'; verify 'CL-003-01'; }
    }
'''
OWNS = "    dependency owns from 'CL-003-01' to 'FR-001';\n"
CHECKS = "    dependency checks from 'CL-003-01' to 'TC-001-001';\n"
ENTRY = MARKER + "package WstxRequirements {\n" + ENUMS + FR + CLAUSE + CASE + OWNS + CHECKS + "}\n"
FUNCTION_KEY = "StationDecode.sysml"
PART_KEY = "backend/qso/Part.sysml"
ENGINE_TESTS = "server/engine_tests.rs"
# The def text of the form, as the issue states it.
RETIRED_CASE_DEF = "metadata def RetiredCase { attribute identity : String; attribute test : String; }"


def retire(identity, test=ENGINE_TESTS, name="@RetiredCase"):
    return f'{name} {{ identity = "{identity}"; test = "{test}"; }}'


def function(*lines, tests=ENGINE_TESTS):
    """StationDecode.sysml: line 1 the package, 2 the function, 3 its @DetailTests, and
    from line 4 on the given lines, one each."""
    return ("package WstxOfflineDecode {\n    action def Engine {\n"
            f'        @DetailTests {{ tests = "{tests}"; covers = "the inside of the engine"; }}\n'
            + "".join("        " + line + "\n" for line in lines) + "    }\n}\n")


def part(*lines, tests="tests/part.cjs"):
    """backend/qso/Part.sysml: the same shape as `function`, in the package PPart."""
    return ("package PPart {\n    action def Part {\n"
            f'        @DetailTests {{ tests = "{tests}"; covers = "the inside of the part"; }}\n'
            + "".join("        " + line + "\n" for line in lines) + "    }\n}\n")


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        self.models = self.root / "docs/sysml"
        for name, package in REQUIRED_FILES.items():
            self.write(name, "package " + package + " {}\n")
        self.write("Requirements.sysml", ENTRY)
        self.source(ENGINE_TESTS, "#[test]\nfn engine() {}\n")
        self.source("tests/part.cjs", "test('part',()=>{});\n")

    def write(self, key, text):
        path = self.models / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="")

    def source(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def check(self, required=RETIRED):
        return tool.canonical_catalog(self.models, self.root, required=required)

    def refused(self, message):
        return self.assertRaisesRegex(ValueError, message)

    def main(self, command, required=RETIRED):
        """Run one command of the tool on the fixture, with the Pilot forbidden; returns
        (exit code, stdout, stderr)."""
        real_catalog = tool.canonical_catalog
        output, errors = io.StringIO(), io.StringIO()
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), \
                mock.patch.object(tool, "FSD", self.root / "docs/FSD.md"), \
                mock.patch.object(tool, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=required)), \
                mock.patch.object(tool, "validate", side_effect=AssertionError("validator invoked")), \
                mock.patch.object(tool.subprocess, "run", side_effect=AssertionError("process started")), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main([command])
        return status, output.getvalue(), errors.getvalue()


class RetirementFormTests(Fixture):
    # T1, accepted
    # Proves: CL-014-15; TC-DOC-013
    def test_retired_case_beside_the_detail_tests_that_name_its_file_counts_as_present(self):
        accepted = {
            "one": (function(retire("TC-001-002")), RETIRED),
            "package names": (function(retire("TC-001-002", name="@ModelBindings::RetiredCase")), RETIRED),
            "two in one body": (function(retire("TC-001-002"), retire("TC-001-003")), RETIRED | {"TC-001-003"}),
            "one path of two, as written": (function(retire("TC-001-002", "tests/part.cjs"),
                                                     tests=ENGINE_TESTS + "; tests/part.cjs"), RETIRED),
            "in a comment beside one": (function(retire("TC-001-002"), "// " + retire("TC-001-002"),
                                                 "/* " + retire("FR-001"), "   " + retire("CL-003-01") + " */"), RETIRED),
        }
        for label, (text, required) in accepted.items():
            with self.subTest(label):
                self.write(FUNCTION_KEY, text)
                self.assertEqual(set(self.check(required)), REQUIRED)
        # The def itself is no retirement, however `metadata` and `def` are spaced.
        for label, spacing in (("two spaces", "  "), ("a tab", "\t"), ("a new line and indent", "\n        ")):
            with self.subTest("the def beside a retirement", spacing=label):
                self.write("ModelBindings.sysml", "package ModelBindings {\n    private import ScalarValues::*;\n    "
                           + RETIRED_CASE_DEF.replace("metadata def", "metadata" + spacing + "def") + "\n}\n")
                self.write(FUNCTION_KEY, function(retire("TC-001-002")))
                self.assertEqual(set(self.check()), REQUIRED)
        (self.models / "ModelBindings.sysml").unlink()
        with self.subTest("in a file of a subfolder"):
            self.write(FUNCTION_KEY, "package WstxOfflineDecode {}\n")
            self.write(PART_KEY, part(retire("TC-001-002", "tests/part.cjs")))
            self.assertEqual(set(self.check()), REQUIRED)
        with self.subTest("traces counts the declared identities only"):
            self.assertEqual(self.main("traces"), (0, "Canonical source/model trace checks passed: 3 identities; "
                                                      "no semantic validation or behavior execution.\n", ""))
        (self.models / PART_KEY).unlink()
        with self.subTest("only in a comment"), self.refused("Missing stable canonical identities: TC-001-002$"):
            self.write(FUNCTION_KEY, function("// " + retire("TC-001-002")))
            self.check()

    # T1, the retired identity under the existing rules, with the baseline requiring it
    # Proves: CL-014-15; TC-DOC-013
    def test_retired_identity_named_by_a_tag_a_test_name_or_a_dependency_is_refused(self):
        self.write(FUNCTION_KEY, function(retire("TC-001-002")))
        with self.subTest("Proves tag"), self.refused(
                r"Source Proves tag names undefined model identities: server/engine_tests\.rs: TC-001-002$"):
            self.source(ENGINE_TESTS, "// Proves: TC-001-002\n#[test]\nfn engine() {}\n")
            self.check()
        self.source(ENGINE_TESTS, "#[test]\nfn engine() {}\n")
        with self.subTest("JavaScript test name"), self.refused(
                r"Proves tag outside the verification binding: TC-001-002: tests/part\.cjs::TC-001-002 engine$"):
            self.source("tests/part.cjs", "test('TC-001-002 engine',()=>{});\n")
            tool.binding_agreement(self.check(), self.root)
        self.source("tests/part.cjs", "test('part',()=>{});\n")
        with self.subTest("clause dependency"), self.refused("Invalid canonical clause dependency: CL-003-01 -> TC-001-002$"):
            self.write("Requirements.sysml", ENTRY.replace(CHECKS, CHECKS + "    dependency checksToo from 'CL-003-01' to 'TC-001-002';\n"))
            self.check()
        with self.subTest("the clause's only case retired"), self.refused("Canonical clause lacks a declared verification case: CL-003-01$"):
            self.write("Requirements.sysml", ENTRY.replace(CASE, "").replace(CHECKS, ""))
            self.write(FUNCTION_KEY, function(retire("TC-001-001")))
            self.check({"FR-001", "CL-003-01", "TC-001-001"})

    # T1, refused, each with its message, key and line
    # Proves: CL-014-15; TC-DOC-013
    def test_retirement_in_another_spelling_or_place_is_refused_by_key_and_line(self):
        key = re.escape(FUNCTION_KEY)
        only = {"FR-009": retire("FR-009"), "CL-003-09": retire("CL-003-09")}
        for identity, line in only.items():
            with self.subTest(only=identity), self.refused("Only a verification case retires: " + identity + ": " + key + "$"):
                self.write(FUNCTION_KEY, function(line))
                self.check()
        invalid = {
            "malformed identity": retire("TC-01-002"),
            "documentation identity": retire("TC-DOC-001"),
            "lower case identity": retire("tc-001-002"),
            "identity with a space": retire(" TC-001-002"),
            "missing test": '@RetiredCase { identity = "TC-001-002"; }',
            "missing identity": f'@RetiredCase {{ test = "{ENGINE_TESTS}"; }}',
            "no body": "@RetiredCase;",
            "empty body": "@RetiredCase {}",
            "repeated identity": f'@RetiredCase {{ identity = "TC-001-002"; identity = "TC-001-002"; test = "{ENGINE_TESTS}"; }}',
            "repeated test": f'@RetiredCase {{ identity = "TC-001-002"; test = "{ENGINE_TESTS}"; test = "{ENGINE_TESTS}"; }}',
            "other feature": f'@RetiredCase {{ identity = "TC-001-002"; test = "{ENGINE_TESTS}"; reason = "inside"; }}',
            "redefinition": f'@RetiredCase {{ :>> identity = "TC-001-002"; test = "{ENGINE_TESTS}"; }}',
            "identity of two literals": f'@RetiredCase {{ identity = "TC-001-" + "002"; test = "{ENGINE_TESTS}"; }}',
            "test not a literal": f'@RetiredCase {{ identity = "TC-001-002"; test = {ENGINE_TESTS}; }}',
            "test with a semicolon": retire("TC-001-002", ENGINE_TESTS + "; tests/part.cjs"),
            "test with a symbol": retire("TC-001-002", ENGINE_TESTS + "::engine"),
        }
        for label, line in invalid.items():
            with self.subTest(invalid=label), self.refused("Invalid retired case: " + key + ":4$"):
                self.write(FUNCTION_KEY, function(line, tests=ENGINE_TESTS + "; tests/part.cjs"))
                self.check()
        with self.subTest("the second of two, on its own line"), self.refused("Invalid retired case: " + key + ":6$"):
            self.write(FUNCTION_KEY, function(retire("TC-001-002"), "", retire("TC-01-003")))
            self.check()
        keyword = {
            "named, the word metadata on line 5": (["// its engine test took it over", "metadata retired :",
                                                    "    ModelBindings::RetiredCase { identity = \"TC-001-002\"; "
                                                    f'test = "{ENGINE_TESTS}"; }}'], 5),
            "unnamed": (["metadata RetiredCase " + retire("TC-001-002", name="")], 4),
        }
        for label, (lines, number) in keyword.items():
            with self.subTest(keyword=label), self.refused("Invalid retired case: " + key + f":{number}$"):
                self.write(FUNCTION_KEY, function(*lines))
                self.check()
        outside = "Retired case outside the detail tests: TC-001-002: " + re.escape(ENGINE_TESTS) + ": " + key + "$"
        places = {
            "named only by another body of the file": "package WstxOfflineDecode {\n    action def Engine {\n"
                f'        @DetailTests {{ tests = "{ENGINE_TESTS}"; covers = "the engine"; }}\n    }}\n'
                f"    action def Other {{\n        {retire('TC-001-002')}\n    }}\n}}\n",
            "a body with no detail tests": f"package WstxOfflineDecode {{\n    action def Lone {{\n        {retire('TC-001-002')}\n    }}\n}}\n",
            "named only by a body nested in it": "package WstxOfflineDecode {\n    action def Engine {\n"
                f'        part inner {{ @DetailTests {{ tests = "{ENGINE_TESTS}"; covers = "inner"; }} }}\n'
                f"        {retire('TC-001-002')}\n    }}\n}}\n",
            "another file of the same body": function(retire("TC-001-002"), tests="tests/part.cjs"),
        }
        for label, text in places.items():
            with self.subTest(outside=label), self.refused(outside):
                self.write(FUNCTION_KEY, text)
                self.check()
        for label, written in (("another spelling of the path", "./" + ENGINE_TESTS), ("a leading space", " " + ENGINE_TESTS)):
            with self.subTest("not as written", path=label), self.refused(
                    "Retired case outside the detail tests: TC-001-002: " + re.escape(written) + ": " + key + "$"):
                self.write(FUNCTION_KEY, function(retire("TC-001-002", written)))
                self.check()

    # T1, refused after all model files are read
    # Proves: CL-014-15; TC-DOC-013
    def test_identity_retired_twice_or_declared_again_is_refused_with_its_keys(self):
        with self.subTest("twice in one file"), self.refused("Duplicate retired case: TC-001-002: " + re.escape(FUNCTION_KEY) + "$"):
            self.write(FUNCTION_KEY, function(retire("TC-001-002"), retire("TC-001-002")))
            self.check()
        with self.subTest("in two files, keys sorted"), self.refused(
                "Duplicate retired case: TC-001-002: " + re.escape(FUNCTION_KEY + ", " + PART_KEY) + "$"):
            self.write(FUNCTION_KEY, function(retire("TC-001-002")))
            self.write(PART_KEY, part(retire("TC-001-002", "tests/part.cjs")))
            self.check()
        with self.subTest("declared again, named by the key of the declaration"), self.refused(
                "Retired case declared again: TC-001-002: " + re.escape(PART_KEY) + "$"):
            self.write(PART_KEY, "package PPart {\n    verification 'TC-001-002' {\n"
                       "        attribute automation : AutomationState = AutomationState::planned;\n    }\n}\n")
            self.check()

    # T1, guards: the existing rules and messages, green on the parent
    # Proves: CL-014-15; TC-DOC-013
    def test_existing_refusals_keep_their_messages_beside_a_retirement(self):
        key = re.escape(FUNCTION_KEY)
        (self.root / "tools").mkdir()
        self.source("tools/x.rs", "")
        with self.subTest("a missing file through the detail tests check"), self.refused(
                "Missing or out-of-scope implementation/test binding: " + key + r": server/src/gone\.rs$"):
            self.write(FUNCTION_KEY, function(retire("TC-001-002", "server/src/gone.rs"), tests="server/src/gone.rs"))
            self.check()
        with self.subTest("a file outside the roots through the detail tests check"), self.refused(
                "Binding outside declared source inputs: " + key + r": tools/x\.rs; update HOW input coverage before admitting a new root$"):
            self.write(FUNCTION_KEY, function(retire("TC-001-002", "tools/x.rs"), tests="tools/x.rs"))
            self.check()
        with self.subTest("removed with no retirement"), self.refused("Missing stable canonical identities: TC-001-002$"):
            self.write(FUNCTION_KEY, function())
            self.check()
        self.write(FUNCTION_KEY, function(retire("TC-001-002")))
        with self.subTest("Proves tag"), self.refused(
                r"Source Proves tag names undefined model identities: server/engine_tests\.rs: TC-001-002$"):
            self.source(ENGINE_TESTS, "// Proves: TC-001-002\n#[test]\nfn engine() {}\n")
            self.check(REQUIRED)
        self.source(ENGINE_TESTS, "#[test]\nfn engine() {}\n")
        with self.subTest("JavaScript test name"), self.refused(
                r"Proves tag outside the verification binding: TC-001-002: tests/part\.cjs::TC-001-002 engine$"):
            self.source("tests/part.cjs", "test('TC-001-002 engine',()=>{});\n")
            tool.binding_agreement(self.check(REQUIRED), self.root)
        with self.subTest("clause dependency"), self.refused("Invalid canonical clause dependency: CL-003-01 -> TC-001-002$"):
            self.write("Requirements.sysml", ENTRY.replace(CHECKS, CHECKS + "    dependency checksToo from 'CL-003-01' to 'TC-001-002';\n"))
            self.check(REQUIRED)
        with self.subTest("the clause's only case retired"), self.refused("Canonical clause lacks a declared verification case: CL-003-01$"):
            self.write("Requirements.sysml", ENTRY.replace(CASE, "").replace(CHECKS, ""))
            self.write(FUNCTION_KEY, function(retire("TC-001-001")))
            self.check({"FR-001", "CL-003-01"})


# StationDecode.sysml with three retirements in two files; TC-001-004 stands first in its file.
LISTED = '''TC-001-002: server/engine_tests.rs: StationDecode.sysml:5
TC-001-003: tests/part.cjs: backend/qso/Part.sysml:4
TC-001-004: server/engine_tests.rs: StationDecode.sysml:4
3 retired cases
'''


class RetiredListingTests(Fixture):
    def hashes(self):
        return {path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(self.root.rglob("*")) if path.is_file()}

    # T2
    # Proves: CL-014-15; TC-DOC-013
    def test_retired_lists_each_retirement_by_identity_with_test_key_and_line(self):
        required = RETIRED | {"TC-001-003", "TC-001-004"}
        with self.subTest("no retirement"):
            self.assertEqual(self.main("retired", REQUIRED), (0, "0 retired cases\n", ""))
        self.write(FUNCTION_KEY, function(retire("TC-001-004"), retire("TC-001-002")))
        self.write(PART_KEY, part(retire("TC-001-003", "tests/part.cjs")))
        before = self.hashes()
        with self.subTest("three in two files"):
            self.assertEqual(self.main("retired", required), (0, LISTED, ""))
        with self.subTest("a broken catalog"):
            status, output, errors = self.main("retired", required | {"TC-001-005"})
            self.assertEqual((status, output), (2, ""))
            self.assertIn("Missing stable canonical identities: TC-001-005\n", errors)
        with self.subTest("an invalid retirement"):
            self.write(PART_KEY, part(retire("TC-01-003", "tests/part.cjs")))
            status, output, errors = self.main("retired", required)
            self.assertEqual((status, output), (2, ""))
            self.assertIn("Invalid retired case: backend/qso/Part.sysml:4\n", errors)
            self.write(PART_KEY, part(retire("TC-001-003", "tests/part.cjs")))
        with self.subTest("nothing written"):
            self.assertEqual(self.hashes(), before)
        with self.subTest("no authority"):
            self.write("Requirements.sysml", ENTRY.removeprefix(MARKER))
            status, output, errors = self.main("retired", required)
            self.assertEqual((status, output), (2, ""))
            self.assertIn("No declared functional authority", errors)


class GateBindingsTests(Fixture):
    def bindings_of(self, retiring_required):
        """The gate's bindings of two commits: HEAD~1 without TC-001-002 and its retirement,
        read with the baseline REQUIRED; HEAD retiring it, read with `retiring_required`."""
        spec = importlib.util.spec_from_file_location("case_retirement_model_bindings", ROOT / ".harness/model_bindings.py")
        bindings = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bindings)

        def git(*args):
            subprocess.run(["git", "-C", str(self.root), "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                            "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)

        self.write(FUNCTION_KEY, function())
        git("init", "-q")
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "without the case")
        self.write(FUNCTION_KEY, function(retire("TC-001-002")))
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "the case retired")
        real_catalog = bindings.sysml.canonical_catalog
        results = {}
        for rev, required in (("HEAD~1", REQUIRED), ("HEAD", retiring_required)):
            with mock.patch.object(bindings, "ROOT", self.root), mock.patch.object(
                    bindings.sysml, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=required)):
                results[rev] = bindings.bindings(rev)
        return results

    def assert_same_without_the_case(self, results):
        text = json.dumps(results["HEAD"])
        self.assertNotIn("TC-001-002", text)
        self.assertNotIn(ENGINE_TESTS, text)
        self.assertEqual(sorted(results["HEAD"]["cases"]), ["TC-001-001"])
        self.assertEqual(results["HEAD"], results["HEAD~1"])

    # T3, red on the parent: the baseline requires the retired identity
    # Proves: CL-014-15; TC-DOC-013
    def test_gate_bindings_of_a_retiring_revision_equal_those_without_the_case(self):
        self.assert_same_without_the_case(self.bindings_of(RETIRED))

    # T3, guard: the baseline does not require it, green on the parent
    # Proves: CL-014-15; TC-DOC-013
    def test_gate_bindings_ignore_a_retirement_the_baseline_does_not_need(self):
        self.assert_same_without_the_case(self.bindings_of(REQUIRED))


PILOT_MODEL_BINDINGS = '''package ModelBindings {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    metadata def Status { attribute build : ImplementationState; }
    metadata def Automation { attribute run : AutomationState; attribute method : String[0..1]; }
    metadata def ImplementedIn { attribute module : String; }
    metadata def TestedBy { attribute test : String; }
    metadata def DetailTests { attribute tests : String; attribute covers : String; }
    ''' + RETIRED_CASE_DEF + '''
}
'''
PILOT_ENGINE = '''package EngineFunction {
    private import ModelBindings::*;
    action def StandardContact {
        @ImplementedIn { module = "server/src/contact.rs"; }
        @DetailTests { tests = "server/src/contact_tests.rs"; covers = "the engine on a virtual clock"; }
        @RetiredCase { identity = "TC-001-002"; test = "server/src/contact_tests.rs"; }
        @ModelBindings::RetiredCase { identity = "TC-001-003"; test = "server/src/contact_tests.rs"; }
    }
}
'''


class RetirementOnThePilotTests(unittest.TestCase):
    # T4, a guard of the def text: the Pilot does not depend on the tool.
    # Proves: CL-014-15; TC-DOC-013
    def test_real_pilot_resolves_the_retired_case_def_and_refuses_a_misspelt_feature(self):
        with tempfile.TemporaryDirectory() as directory:
            models = Path(directory) / "docs/sysml"
            texts = {name: "package " + package + " {}\n" for name, package in REQUIRED_FILES.items()}
            texts.update({"Requirements.sysml": MARKER + "package WstxRequirements {\n" + ENUMS + FR + "}\n",
                          "ModelBindings.sysml": PILOT_MODEL_BINDINGS, "backend/qso/Engine.sysml": PILOT_ENGINE})
            for key, text in texts.items():
                path = models / key
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            paths = [models / "Requirements.sysml", *sorted(path for path in models.rglob("*.sysml") if path.name != "Requirements.sysml")]
            passed = "OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed."
            result = tool.validate(paths, CACHE)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(passed, result.stdout)
            engine = models / "backend/qso/Engine.sysml"
            self.assertIn('{ identity = "TC-001-002";', PILOT_ENGINE)
            engine.write_text(PILOT_ENGINE.replace('{ identity = "TC-001-002";', '{ identiy = "TC-001-002";'), encoding="utf-8")
            result = tool.validate(paths, CACHE)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn(passed, result.stdout)


# R1 of #183: a case whose checks went to other contract cases retires as superseded.
# TC-001-002 (TC-A) is superseded by TC-001-003 and TC-001-004 (TC-B, TC-C), declared beside
# TC-001-001 in the entry file.
EXTENDED_DEF = ("metadata def RetiredCase { attribute identity : String; attribute test : String[0..1]; "
                "attribute supersededBy : String[0..1]; }")
SUPERSEDING = '''    verification 'TC-001-003' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'FR-001'; }
    }
    verification 'TC-001-004' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'FR-001'; }
    }
'''
WITH_SUPERSEDING = ENTRY.replace(OWNS, SUPERSEDING + OWNS)
SUPERSEDED_KEY = PART_KEY


def superseded(identity="TC-001-002", value='"TC-001-003; TC-001-004"', name="@RetiredCase"):
    return f"{name} {{ identity = \"{identity}\"; supersededBy = {value}; }}"


def package_level(*lines):
    """backend/qso/Part.sysml: line 1 the package, from line 2 on the given lines, one each."""
    return "package PPart {\n" + "".join("    " + line + "\n" for line in lines) + "}\n"


class SupersededRetirementTests(Fixture):
    def setUp(self):
        super().setUp()
        self.write("Requirements.sysml", WITH_SUPERSEDING)
        self.write("shared/ModelBindings.sysml", "package ModelBindings {\n    private import ScalarValues::*;\n    "
                   + EXTENDED_DEF + "\n}\n")
        self.declared = REQUIRED | {"TC-001-003", "TC-001-004"}

    # R1, accepted: at package level of a subfolder file and directly in a definition body
    # Proves: CL-014-15; TC-DOC-013
    def test_superseded_case_counts_as_present_and_is_listed_with_its_cases(self):
        accepted = {
            "package level": package_level(superseded()),
            "package names, no spaces": package_level(superseded(value='"TC-001-003;TC-001-004"',
                                                                 name="@ModelBindings::RetiredCase")),
            "directly in a definition body": package_level("part def Holder {", "    " + superseded(), "}"),
        }
        for label, text in accepted.items():
            with self.subTest(label):
                self.write(SUPERSEDED_KEY, text)
                self.assertEqual(set(self.check()), self.declared)
        self.write(SUPERSEDED_KEY, package_level(superseded()))
        with self.subTest("traces counts the declared identities only"):
            self.assertEqual(self.main("traces"), (0, "Canonical source/model trace checks passed: 5 identities; "
                                                      "no semantic validation or behavior execution.\n", ""))
        with self.subTest("retired lists it with its cases"):
            self.assertEqual(self.main("retired"), (0, "TC-001-002: superseded by TC-001-003, TC-001-004: "
                                                       "backend/qso/Part.sysml:2\n1 retired cases\n", ""))
        with self.subTest("beside a retirement into the detail tests, sorted by identity"):
            self.write(FUNCTION_KEY, function(retire("TC-001-005")))
            self.assertEqual(self.main("retired", RETIRED | {"TC-001-005"}),
                             (0, "TC-001-002: superseded by TC-001-003, TC-001-004: backend/qso/Part.sysml:2\n"
                                 "TC-001-005: server/engine_tests.rs: StationDecode.sysml:4\n2 retired cases\n", ""))

    # R1, refused, each with its message
    # Proves: CL-014-15; TC-DOC-013
    def test_superseded_retirement_in_another_spelling_or_naming_no_active_case_is_refused(self):
        invalid = {
            "naming itself": superseded(value='"TC-001-003; TC-001-002"'),
            "both test and supersededBy": f'@RetiredCase {{ identity = "TC-001-002"; test = "{ENGINE_TESTS}"; '
                                          'supersededBy = "TC-001-003"; }',
            "neither": '@RetiredCase { identity = "TC-001-002"; }',
            "two literals, a sequence": superseded(value='("TC-001-003", "TC-001-004")'),
            "two literals, joined": superseded(value='"TC-001-003" + "; TC-001-004"'),
            "a malformed identity": superseded(value='"TC-001-003; TC-01-004"'),
            "a repeated identity": superseded(value='"TC-001-003; TC-001-003"'),
            "an empty entry": superseded(value='"TC-001-003;"'),
            "empty": superseded(value='""'),
            "supersededBy twice": '@RetiredCase { identity = "TC-001-002"; supersededBy = "TC-001-003"; '
                                  'supersededBy = "TC-001-004"; }',
        }
        for label, line in invalid.items():
            with self.subTest(invalid=label), self.refused("Invalid retired case: " + re.escape(SUPERSEDED_KEY) + ":2$"):
                self.write(SUPERSEDED_KEY, package_level(line))
                self.check()
        missing = "Superseding case missing or retired: TC-001-002: TC-001-004: " + re.escape(SUPERSEDED_KEY) + "$"
        without_c = ENTRY.replace(OWNS, SUPERSEDING.split("    verification 'TC-001-004'")[0] + OWNS)
        with self.subTest("TC-C missing"), self.refused(missing):
            self.write("Requirements.sysml", without_c)
            self.write(SUPERSEDED_KEY, package_level(superseded()))
            self.check()
        with self.subTest("TC-C itself retired"), self.refused(missing):
            self.write("Requirements.sysml", without_c)
            self.write(SUPERSEDED_KEY, package_level(superseded(), superseded("TC-001-004", '"TC-001-001"')))
            self.check(RETIRED | {"TC-001-004"})
        self.write("Requirements.sysml", WITH_SUPERSEDING)
        self.write(SUPERSEDED_KEY, package_level(superseded()))
        with self.subTest("a Proves tag naming TC-A"), self.refused(
                r"Source Proves tag names undefined model identities: server/engine_tests\.rs: TC-001-002$"):
            self.source(ENGINE_TESTS, "// Proves: TC-001-002\n#[test]\nfn engine() {}\n")
            self.check()


PILOT_SUPERSEDED = '''package EngineFunction {
    private import ModelBindings::*;
    @RetiredCase { identity = "TC-001-002"; supersededBy = "TC-001-003; TC-001-004"; }
    action def StandardContact {
        @DetailTests { tests = "server/src/contact_tests.rs"; covers = "the engine on a virtual clock"; }
        @RetiredCase { identity = "TC-001-005"; test = "server/src/contact_tests.rs"; }
    }
}
'''


class SupersededOnThePilotTests(unittest.TestCase):
    # R1: the pinned Pilot accepts the extended definition with both forms and refuses a
    # misspelt feature; the tool does not take part.
    # Proves: CL-014-15; TC-DOC-013
    def test_real_pilot_resolves_the_extended_def_and_refuses_a_misspelt_feature(self):
        with tempfile.TemporaryDirectory() as directory:
            models = Path(directory) / "docs/sysml"
            texts = {name: "package " + package + " {}\n" for name, package in REQUIRED_FILES.items()}
            texts.update({"Requirements.sysml": MARKER + "package WstxRequirements {\n" + ENUMS + FR + "}\n",
                          "shared/ModelBindings.sysml": PILOT_MODEL_BINDINGS.replace(RETIRED_CASE_DEF, EXTENDED_DEF),
                          "backend/qso/Engine.sysml": PILOT_SUPERSEDED})
            for key, text in texts.items():
                path = models / key
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            paths = [models / "Requirements.sysml", *sorted(path for path in models.rglob("*.sysml") if path.name != "Requirements.sysml")]
            passed = "OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed."
            self.assertIn(EXTENDED_DEF, texts["shared/ModelBindings.sysml"])
            result = tool.validate(paths, CACHE)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(passed, result.stdout)
            (models / "backend/qso/Engine.sysml").write_text(PILOT_SUPERSEDED.replace("supersededBy =", "supersededby ="),
                                                             encoding="utf-8")
            result = tool.validate(paths, CACHE)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn(passed, result.stdout)


if __name__ == "__main__":
    unittest.main()
