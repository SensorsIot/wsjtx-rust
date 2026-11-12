"""TC-DOC-009: status and bindings as attributes or as ModelBindings metadata, stated once.

Isolated fixtures in a temporary folder. Two tests run the real pinned Pilot (the new
forms on a small model, and the real model rewritten to metadata), and one builds a
throwaway git repository for the gate's model bindings.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import urllib.parse

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("stated_once_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
REQUIRED = {"FR-001", "CL-003-01", "TC-001-001"}
MARKER = "// Canonical authority: SysML\n"
# The fixture's model files and the required package each declares, written by hand.
REQUIRED_FILES = {
    "Requirements.sysml": "WstxRequirements", "Architecture.sysml": "WstxArchitecture",
    "Profiles.sysml": "WstxProfiles", "RecordingReceive.sysml": "WstxRecordingReceive",
    "StationDecode.sysml": "WstxOfflineDecode", "RadioIO.sysml": "WstxRadioIO",
    "OperatingLayout.sysml": "WstxOperatingLayout", "OperatingReceive.sysml": "WstxOperatingReceive",
    "StationProtocol.sysml": "WstxStationProtocol", "ProductScope.sysml": "WstxProductScope",
}
ENUMS = '''    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
'''
FR = '''    requirement 'FR-001' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
'''
OWNS = "    dependency owns from 'CL-003-01' to 'FR-001';\n"
CHECKS = "    dependency checks from 'CL-003-01' to 'TC-001-001';\n"
PART_KEY = "backend/qso/Part.sysml"
PART_KEY_PATTERN = re.escape(PART_KEY) + "$"
TAGGED = "// Proves: TC-001-001\ntest('identity',()=>{});\n"
# The definitions the first conversion slice adds to the model (issues #115 and #131).
MODEL_BINDINGS = '''package ModelBindings {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    metadata def Status { attribute build : ImplementationState; }
    metadata def Automation { attribute run : AutomationState; attribute method : String[0..1]; }
    metadata def ImplementedIn { attribute module : String; }
    metadata def TestedBy { attribute test : String; }
    metadata def DetailTests { attribute tests : String; attribute covers : String; }
    metadata def RetiredCase { attribute identity : String; attribute test : String; }
}
'''


def coverage(state):
    return f"        attribute coverage : ImplementationState = ImplementationState::{state};\n"


def status(state):
    return f"        @Status {{ build = ImplementationState::{state}; }}\n"


def automation(state):
    return f"        attribute automation : AutomationState = AutomationState::{state};\n"


def run(state):
    return f"        @Automation {{ run = AutomationState::{state}; }}\n"


def implementation(paths):
    return f'        attribute implementation : String = "{paths}";\n'


def implemented_in(paths):
    return f'        @ImplementedIn {{ module = "{paths}"; }}\n'


def executable(paths):
    return f'        attribute executable : String = "{paths}";\n'


def tested_by(paths):
    return f'        @TestedBy {{ test = "{paths}"; }}\n'


def clause(body):
    return "    requirement 'CL-003-01' {\n" + body + "    }\n"


def case(body, typed=""):
    return ("    verification 'TC-001-001'" + typed + " {\n" + body
            + "        objective { verify 'FR-001'; verify 'CL-003-01'; }\n    }\n")


def flat(clause_body, case_body, typed="", extra=""):
    """The whole catalog in the entry file."""
    return (MARKER + "package WstxRequirements {\n" + ENUMS + FR + extra + clause(clause_body)
            + case(case_body, typed) + OWNS + CHECKS + "}\n")


def part(clause_body, case_body, typed="", extra=""):
    """Clause and case two folders down; the requirement stays in the entry file."""
    return "package PPart {\n" + extra + clause(clause_body) + case(case_body, typed) + OWNS + CHECKS + "}\n"


class StatedOnceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        self.models = self.root / "docs/sysml"
        for name, package in REQUIRED_FILES.items():
            self.write(name, "package " + package + " {}")
        self.source("server/contact.rs", "pub fn step() {}\n")
        self.source("client/app.js", "export {};\n")
        self.source("tests/case.cjs", TAGGED)
        self.source("tests/untagged.cjs", "test('by hand',()=>{});\n")

    def write(self, key, text):
        path = self.models / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def source(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def flat(self, *args, **kwargs):
        self.write("Requirements.sysml", flat(*args, **kwargs))
        return self.check()

    def tree(self, *args, top="", **kwargs):
        self.write("Requirements.sysml", MARKER + "package WstxRequirements {\n" + ENUMS + FR + top + "}\n")
        self.write("ProductScope.sysml", "package WstxProductScope { private import PPart::*; }")
        self.write(PART_KEY, part(*args, **kwargs))
        return self.check()

    def check(self):
        return tool.canonical_catalog(self.models, self.root, required=REQUIRED)

    def refused(self, message):
        return self.assertRaisesRegex(ValueError, message)

    # T1
    # Proves: CL-014-11; TC-DOC-009
    def test_status_as_metadata_is_read_as_the_attribute_is_and_stated_once(self):
        for built, automated in (("target", "planned"), ("partial", "partial"), ("implemented", "implemented")):
            with self.subTest(states=(built, automated)):
                bound = (implementation("server/contact.rs"), executable("tests/case.cjs"))
                attributes = self.flat(coverage(built) + bound[0], automation(automated) + bound[1])
                metadata = self.flat(status(built) + bound[0], run(automated) + bound[1])
                self.assertEqual(metadata, attributes)
                self.assertEqual((metadata["CL-003-01"]["state"], metadata["TC-001-001"]["state"]), (built, automated))
        with self.subTest("package names on the metadata and on the value"):
            qualified = "        @ModelBindings::Status { build = WstxRequirements::ImplementationState::partial; }\n"
            entries = self.flat(qualified + implementation("server/contact.rs"),
                                "        @ModelBindings::Automation { run = WstxRequirements::AutomationState::planned; }\n")
            self.assertEqual((entries["CL-003-01"]["state"], entries["TC-001-001"]["state"]), ("partial", "planned"))
        clause_faults = {
            "both forms": coverage("target") + status("target"),
            "metadata twice": status("target") + status("target"),
            "no state of the project": "        @Status { build = ImplementationState::built; }\n",
            "the verification metadata on a requirement": run("planned"),
            "none": "",
        }
        for label, body in clause_faults.items():
            with self.subTest(clause=label), self.refused("Missing or invalid declared model state: CL-003-01$"):
                self.flat(body, automation("planned"))
        case_faults = {"both forms": automation("planned") + run("planned"), "metadata twice": run("planned") + run("partial"),
                       "the requirement metadata on a case": status("target"), "none": ""}
        for label, body in case_faults.items():
            with self.subTest(case=label), self.refused("Missing or invalid declared model state: TC-001-001$"):
                self.flat(coverage("target"), body)

    # T2
    # Proves: CL-014-11; TC-DOC-009
    def test_bindings_as_metadata_keep_the_grammar_checks_and_messages_of_the_attributes(self):
        (self.root / "tools").mkdir()
        self.source("tools/outside.rs", "")
        delivered, automated = status("implemented"), run("implemented")
        with self.subTest("accepted"):
            entries = self.flat(delivered + implemented_in("server/contact.rs; client/app.js"), automated + tested_by("tests/case.cjs"))
            self.assertEqual(entries["CL-003-01"]["bindings"], ["server/contact.rs", "client/app.js"])
            self.assertEqual(entries["TC-001-001"]["bindings"], ["tests/case.cjs"])
            self.assertEqual(entries, self.flat(coverage("implemented") + implementation("server/contact.rs; client/app.js"),
                                                automation("implemented") + executable("tests/case.cjs")))
        with self.subTest("a named test of the file"):
            self.assertEqual(self.flat(coverage("target"), automated + tested_by("tests/untagged.cjs::by hand"))["TC-001-001"]["bindings"],
                             ["tests/untagged.cjs::by hand"])
        good_clause, good_case = delivered + implemented_in("server/contact.rs"), automated + tested_by("tests/case.cjs")
        refusals = (
            (delivered + implemented_in("server/missing.rs"), good_case,
             r"Missing or out-of-scope implementation/test binding: CL-003-01: server/missing\.rs$"),
            (delivered + implemented_in("../server/contact.rs"), good_case,
             r"Missing or out-of-scope implementation/test binding: CL-003-01: \.\./server/contact\.rs$"),
            (delivered + implemented_in("tools/outside.rs"), good_case,
             r"Binding outside declared source inputs: CL-003-01: tools/outside\.rs;"),
            (delivered, good_case, "Delivered declaration lacks implementation/test binding: CL-003-01$"),
            (good_clause, automated + tested_by("tests/missing.cjs"),
             r"Missing or out-of-scope implementation/test binding: TC-001-001: tests/missing\.cjs$"),
            (good_clause, automated + tested_by("tests/untagged.cjs"),
             r"No Proves tag or named-test identity for TC-001-001: tests/untagged\.cjs$"),
            (good_clause, automated + tested_by("tests/case.cjs::absent"),
             r"Missing executable test symbol: TC-001-001: tests/case\.cjs::absent$"),
            (good_clause, automated, "Delivered declaration lacks implementation/test binding: TC-001-001$"),
        )
        for clause_body, case_body, message in refusals:
            with self.subTest(refused=message), self.refused(message):
                self.flat(clause_body, case_body)
        with self.subTest("manual admits the untagged file"):
            manual = '        @Automation { run = AutomationState::implemented; method = "manual"; }\n'
            entries = self.flat(good_clause, manual + tested_by("tests/untagged.cjs"))
            self.assertTrue(entries["TC-001-001"]["manual"])
            self.assertEqual(entries, self.flat(good_clause, automation("implemented") + '        attribute method : String = "manual";\n'
                                                + executable("tests/untagged.cjs")))
        method = '        attribute method : String = "manual";\n'
        invalid = {
            "clause bound in both forms": (delivered + implementation("server/contact.rs") + implemented_in("server/contact.rs"), good_case, "CL-003-01"),
            "clause bound twice": (delivered + implemented_in("server/contact.rs") + implemented_in("client/app.js"), good_case, "CL-003-01"),
            "clause bound by two literals": (delivered + '        @ImplementedIn { module = "server/" + "contact.rs"; }\n', good_case, "CL-003-01"),
            "case bound in both forms": (good_clause, automated + executable("tests/case.cjs") + tested_by("tests/case.cjs"), "TC-001-001"),
            "case bound by two literals": (good_clause, automated + '        @TestedBy { test = "tests/" + "case.cjs"; }\n', "TC-001-001"),
            "method in both forms": (good_clause, method + '        @Automation { run = AutomationState::implemented; method = "manual"; }\n'
                                     + tested_by("tests/case.cjs"), "TC-001-001"),
            "another method": (good_clause, '        @Automation { run = AutomationState::implemented; method = "by hand"; }\n'
                               + tested_by("tests/case.cjs"), "TC-001-001"),
            "method by two literals": (good_clause, '        @Automation { run = AutomationState::implemented; method = "man" + "ual"; }\n'
                                       + tested_by("tests/case.cjs"), "TC-001-001"),
        }
        for label, (clause_body, case_body, identifier) in invalid.items():
            with self.subTest(invalid=label), self.refused("Invalid verification/implementation metadata: " + identifier + "$"):
                self.flat(clause_body, case_body)

    # T3
    # Proves: CL-014-11; TC-DOC-009
    def test_delivered_clause_without_binding_takes_the_one_function_binding_of_its_file(self):
        def function(name, paths):
            return "    action def " + name + " {\n" + implemented_in(paths) + "    }\n"

        one = function("Engine", "server/contact.rs")
        two = one + function("Other", "client/app.js")
        planned = automation("planned")
        lacks = "Delivered declaration lacks implementation/test binding: CL-003-01$"
        with self.subTest("one"):
            self.assertEqual(self.tree(status("implemented"), planned, extra=one)["CL-003-01"]["bindings"], ["server/contact.rs"])
            self.assertEqual(self.tree(coverage("partial"), planned, extra=one)["CL-003-01"]["bindings"], ["server/contact.rs"])
        with self.subTest("none"), self.refused(lacks):
            self.tree(status("implemented"), planned)
        with self.subTest("two"), self.refused("Ambiguous function binding: CL-003-01: " + PART_KEY_PATTERN):
            self.tree(status("implemented"), planned, extra=two)
        for label, own in (("metadata", implemented_in("client/app.js")), ("attribute", implementation("client/app.js"))):
            with self.subTest("the clause's own binding beside two", form=label):
                self.assertEqual(self.tree(status("implemented") + own, planned, extra=two)["CL-003-01"]["bindings"], ["client/app.js"])
            with self.subTest("the clause's own binding beside one", form=label):
                self.assertEqual(self.tree(status("implemented") + own, planned, extra=one)["CL-003-01"]["bindings"], ["client/app.js"])
        # A binding the clause names itself in a spelling that is not read is never replaced
        # by the function's.
        unread = {
            "attribute of two literals": (coverage("implemented"), '        attribute implementation : String = "client/" + "app.js";\n'),
            "redefinition in the metadata": (status("implemented"), '        @ImplementedIn { :>> module = "client/app.js"; }\n'),
            "another feature in the metadata": (status("implemented"), '        @ImplementedIn { modul = "client/app.js"; }\n'),
            "the metadata keyword": (status("implemented"), '        metadata ImplementedIn { module = "client/app.js"; }\n'),
            "the metadata keyword with a name": (status("implemented"), '        metadata own : ModelBindings::ImplementedIn { module = "client/app.js"; }\n'),
            "redefinition in the attribute": (coverage("implemented"), '        attribute :>> implementation = "client/app.js";\n'),
        }
        for label, (state, own) in unread.items():
            with self.subTest("the clause's own unread binding beside one", spelling=label), self.refused(
                    "Invalid verification/implementation metadata: CL-003-01$"):
                self.tree(state + own, planned, extra=one)
            with self.subTest("the clause's own unread binding beside none", spelling=label), self.refused(lacks):
                self.tree(state + own, planned)
        with self.subTest("only in another file"), self.refused(lacks):
            self.tree(status("implemented"), planned, top=one)
        for label, hidden in (("line comment", "    // " + implemented_in("server/contact.rs").strip() + "\n"),
                              ("block comment", "    /* " + implemented_in("server/contact.rs").strip() + " */\n")):
            with self.subTest("only in a comment", comment=label), self.refused(lacks):
                self.tree(status("implemented"), planned, extra=hidden)
        with self.subTest("only in the body of another declaration"), self.refused(lacks):
            self.tree(status("implemented"), planned + implemented_in("server/contact.rs"))
        with self.subTest("a target clause with none"):
            entries = self.tree(status("target"), planned)
            self.assertEqual((entries["CL-003-01"]["state"], entries["CL-003-01"]["bindings"]), ("target", []))
        with self.subTest("a function binding to a missing file"), self.refused(
                "Missing or out-of-scope implementation/test binding: " + re.escape(PART_KEY) + r": server/missing\.rs$"):
            self.tree(status("implemented"), planned, extra=function("Engine", "server/missing.rs"))
        with self.subTest("a function binding of two literals"), self.refused(
                "Invalid verification/implementation metadata: " + PART_KEY_PATTERN):
            self.tree(status("target"), planned, extra='    action def Engine { @ImplementedIn { module = "server/" + "contact.rs"; } }\n')

    # T4
    # Proves: CL-014-11; TC-DOC-009
    def test_case_typed_by_a_definition_of_its_file_takes_its_automation_and_method(self):
        def definition(body, name="EngineCase", header=""):
            return "    verification def " + name + header + " {\n" + body + "    }\n"

        typed = " : EngineCase"
        target = coverage("target")
        manual_method = '        attribute method : String = "manual";\n'
        for label, stated in (("attribute", automation("implemented")), ("metadata", run("implemented"))):
            with self.subTest("state taken", definition=label):
                entries = self.flat(target, tested_by("tests/case.cjs"), typed, definition(stated))
                self.assertEqual(entries["TC-001-001"], {"kind": "verification", "state": "implemented", "refs": ["FR-001", "CL-003-01"],
                                                         "bindings": ["tests/case.cjs"], "manual": False})
            with self.subTest("the case's own state wins over an implemented definition", definition=label):
                for own in (automation("planned"), run("planned")):
                    self.assertEqual(self.flat(target, own, typed, definition(stated))["TC-001-001"]["state"], "planned")
        for label, stated in (("attribute", automation("planned")), ("metadata", run("planned"))):
            for own in (automation("partial"), run("partial")):
                with self.subTest("the case's own state wins over a planned definition", definition=label), \
                        self.refused("Delivered declaration lacks implementation/test binding: TC-001-001$"):
                    self.flat(target, own, typed, definition(stated))
        manual_definitions = {
            "attribute": automation("implemented") + manual_method,
            "metadata": '        @Automation { run = AutomationState::implemented; method = "manual"; }\n',
        }
        for label, stated in manual_definitions.items():
            with self.subTest("method taken", definition=label):
                entries = self.flat(target, tested_by("tests/untagged.cjs"), typed, definition(stated))
                self.assertEqual((entries["TC-001-001"]["state"], entries["TC-001-001"]["manual"]), ("implemented", True))
            with self.subTest("the case's own method wins", definition=label), self.refused(
                    r"No Proves tag or named-test identity for TC-001-001: tests/untagged\.cjs$"):
                self.flat(target, '        @Automation { method = "automated"; }\n' + tested_by("tests/untagged.cjs"), typed, definition(stated))
        missing = "Missing or invalid declared model state: TC-001-001$"
        # A state or method the case names itself in a spelling that is not read is never
        # replaced by the definition's.
        unread_states = {
            "attribute with a qualified state": "        attribute automation : AutomationState = WstxRequirements::AutomationState::planned;\n",
            "redefinition in the metadata": "        @Automation { :>> run = AutomationState::planned; }\n",
            "the metadata keyword": "        metadata Automation { run = AutomationState::planned; }\n",
            "the metadata keyword with a name": "        metadata own : ModelBindings::Automation { run = AutomationState::planned; }\n",
            "redefinition in the attribute": "        attribute :>> automation = AutomationState::planned;\n",
        }
        for label, own in unread_states.items():
            with self.subTest("the case's own unread state", spelling=label), self.refused(missing):
                self.flat(target, own + tested_by("tests/case.cjs"), typed, definition(run("implemented")))
        for label, own in (("attribute of two literals", '        attribute method : String = "auto" + "mated";\n'),
                           ("redefinition in the attribute", '        attribute :>> method = "automated";\n')):
            with self.subTest("the case's own unread method", spelling=label), self.refused(
                    "Invalid verification/implementation metadata: TC-001-001$"):
                self.flat(target, own + tested_by("tests/untagged.cjs"), typed, definition(manual_definitions["metadata"]))
        with self.subTest("the case's own unread method in the metadata keyword"), self.refused(missing):
            self.flat(target, '        metadata Automation { method = "automated"; }\n' + tested_by("tests/untagged.cjs"), typed,
                      definition(manual_definitions["metadata"]))
        for label, own in (("empty", "        @Automation {}\n"), ("method only", '        @Automation { method = "automated"; }\n')):
            with self.subTest("the state is still taken beside the case's own metadata", own=label):
                self.assertEqual(self.flat(target, own + tested_by("tests/case.cjs"), typed, definition(run("implemented")))["TC-001-001"]["state"],
                                 "implemented")
        with self.subTest("definition in another file"), self.refused(missing):
            self.tree(target, "", typed, top=definition(run("implemented")))
        with self.subTest("definition in another file, named through its package"), self.refused(missing):
            self.tree(target, "", " : WstxRequirements::EngineCase", top=definition(run("implemented")))
        with self.subTest("definition of the file named through its package"), self.refused(missing):
            self.flat(target, "", " : WstxRequirements::EngineCase", definition(run("implemented")))
        with self.subTest("automation only on the definition's supertype"), self.refused(missing):
            self.flat(target, "", typed, definition(run("implemented"), name="Base") + definition("", header=" :> Base"))
        with self.subTest("definition without automation"), self.refused(missing):
            self.flat(target, "", typed, definition(""))
        with self.subTest("definition states automation twice"), self.refused(missing):
            self.flat(target, "", typed, definition(run("implemented") + automation("implemented")))
        for label, bound in (("metadata", tested_by("tests/case.cjs")), ("attribute", executable("tests/case.cjs"))):
            with self.subTest("a test bound on the definition", form=label), self.refused(
                    r"Verification definition carries a test binding: EngineCase: Requirements\.sysml$"):
                self.flat(target, tested_by("tests/case.cjs"), typed, definition(run("implemented") + bound))
        with self.subTest("a test bound on a definition in a folder, typed by no case"), self.refused(
                "Verification definition carries a test binding: EngineCase: " + PART_KEY_PATTERN):
            self.tree(target, automation("planned"), extra=definition(tested_by("tests/case.cjs")))

    # T5
    # Proves: CL-014-11; TC-DOC-009
    def test_detail_tests_name_existing_files_under_the_source_roots_and_need_no_tag(self):
        def detail(paths):
            return ('    part def Engine {\n        @DetailTests { tests = "' + paths + '"; covers = "the engine; on a virtual clock"; }\n    }\n')

        (self.root / "tools").mkdir()
        self.source("tools/outside.rs", "")
        with self.subTest("existing untagged files"):
            self.assertEqual(set(self.tree(coverage("target"), automation("planned"), extra=detail("tests/untagged.cjs; server/contact.rs"))), REQUIRED)
        with self.subTest("missing file"), self.refused(
                "Missing or out-of-scope implementation/test binding: " + re.escape(PART_KEY) + r": tests/missing\.cjs$"):
            self.tree(coverage("target"), automation("planned"), extra=detail("tests/untagged.cjs; tests/missing.cjs"))
        with self.subTest("outside the roots"), self.refused(
                "Binding outside declared source inputs: " + re.escape(PART_KEY) + r": tools/outside\.rs;"):
            self.tree(coverage("target"), automation("planned"), extra=detail("tools/outside.rs"))

    # T6
    # Proves: CL-014-11; TC-DOC-009
    def test_declaration_with_an_identity_in_a_form_the_catalog_does_not_read_is_refused(self):
        good = flat(coverage("target"), automation("planned"))
        forms = {
            "verification 'TC-001-001' :> Base {": ("    verification 'TC-001-001' {", "TC-001-001"),
            "verification <'TC-001-001'> engineCase {": ("    verification 'TC-001-001' {", "TC-001-001"),
            "requirement 'CL-003-01' : Base {": ("    requirement 'CL-003-01' {", "CL-003-01"),
        }
        for form, (header, identifier) in forms.items():
            self.assertIn(header, good)
            with self.subTest(form=form, key="Requirements.sysml"), self.refused(
                    "Unreadable canonical declaration: " + identifier + r": Requirements\.sysml$"):
                self.write("Requirements.sysml", good.replace(header, "    " + form))
                self.check()
            with self.subTest(form=form, key=PART_KEY), self.refused(
                    "Unreadable canonical declaration: " + identifier + ": " + PART_KEY_PATTERN):
                self.write("Requirements.sysml", MARKER + "package WstxRequirements {\n" + ENUMS + FR + "}\n")
                self.write("ProductScope.sysml", "package WstxProductScope { private import PPart::*; }")
                self.write(PART_KEY, part(coverage("target"), automation("planned")).replace(header, "    " + form))
                self.check()
            (self.models / PART_KEY).unlink()
            self.write("ProductScope.sysml", "package WstxProductScope {}")
            for label, comment in (("line", "    // " + form + " }\n"), ("block", "    /* " + form + "\n       } */\n")):
                with self.subTest(form=form, comment=label):
                    self.write("Requirements.sysml", good.replace(OWNS, comment + OWNS))
                    self.assertEqual(set(self.check()), REQUIRED)

    # T7
    # Proves: CL-014-11; TC-DOC-009
    def test_gate_model_bindings_of_the_metadata_forms_equal_those_of_the_attribute_forms(self):
        spec = importlib.util.spec_from_file_location("stated_once_model_bindings", ROOT / ".harness/model_bindings.py")
        bindings = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bindings)

        def git(*args):
            subprocess.run(["git", "-C", str(self.root), "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                            "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)

        self.source("tests/second.cjs", "// Proves: TC-001-002\ntest('second',()=>{});\n")
        second_links = "    dependency checksToo from 'CL-003-01' to 'TC-001-002';\n"
        attributes = (MARKER + "package WstxRequirements {\n" + ENUMS + FR
                      + clause(coverage("implemented") + implementation("server/contact.rs"))
                      + case(automation("implemented") + '        attribute method : String = "manual";\n' + executable("tests/untagged.cjs"))
                      + "    verification 'TC-001-002' {\n" + automation("partial") + executable("tests/second.cjs")
                      + "        objective { verify 'CL-003-01'; }\n    }\n" + OWNS + CHECKS + second_links + "}\n")
        metadata = (MARKER + "package WstxRequirements {\n" + ENUMS + FR
                    + "    action def Engine {\n" + implemented_in("server/contact.rs")
                    + '        @DetailTests { tests = "tests/case.cjs"; covers = "the inside"; }\n    }\n'
                    + clause(status("implemented"))
                    + '    verification def ManualCase {\n        @Automation { run = AutomationState::implemented; method = "manual"; }\n    }\n'
                    + case(tested_by("tests/untagged.cjs"), " : ManualCase")
                    + "    verification 'TC-001-002' {\n" + run("partial") + tested_by("tests/second.cjs")
                    + "        objective { verify 'CL-003-01'; }\n    }\n" + OWNS + CHECKS + second_links + "}\n")
        self.write("Requirements.sysml", attributes)
        git("init", "-q")
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "attribute forms")
        self.write("Requirements.sysml", metadata)
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "metadata forms")
        # Written by hand from the fixture: the manual case binds no test by tag, the clause's
        # module is its own in the first commit and its function's in the second.
        cases = {
            "TC-001-001": {"automated": False, "verifies": ["FR-001", "CL-003-01"], "paths": ["tests/untagged.cjs"],
                           "tests": [], "unresolved": ["tests/untagged.cjs"]},
            "TC-001-002": {"automated": True, "verifies": ["CL-003-01"], "paths": ["tests/second.cjs"],
                           "tests": [{"path": "tests/second.cjs", "name": "second"}], "unresolved": []},
        }
        promises = {"FR-001": {"implementation": []}, "CL-003-01": {"implementation": ["server/contact.rs"]}}
        real_catalog = bindings.sysml.canonical_catalog
        results = {}
        with mock.patch.object(bindings, "ROOT", self.root), \
                mock.patch.object(bindings.sysml, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)):
            for rev in ("HEAD~1", "HEAD"):
                with self.subTest(rev=rev):
                    results[rev] = bindings.bindings(rev)
                    self.assertEqual(results[rev]["cases"], cases)
                    self.assertEqual(results[rev]["promises"], promises)
        self.assertEqual(results.get("HEAD"), results.get("HEAD~1"))

    # T8
    # Proves: CL-014-11; TC-DOC-009
    def test_model_bindings_package_is_a_library_package(self):
        self.write("Requirements.sysml", flat(coverage("target"), automation("planned")))
        for key in ("ModelBindings.sysml", "shared/ModelBindings.sysml"):
            with self.subTest(accepted=key):
                self.write(key, "package ModelBindings { metadata def Status; }")
                self.assertEqual(set(self.check()), REQUIRED)
                (self.models / key).unlink()
        with self.subTest("another package in a file of that name"), self.refused(r"lacks a ProductScope reference: ModelBindings\.sysml$"):
            self.write("ModelBindings.sysml", "package ModelBindingsX {}")
            self.check()
        self.assertEqual(tool.LIBRARY_PACKAGES, {"ModelNotes", "ModelBindings"})


# A small model in the new forms that the real Pilot resolves: the forms of the issue, and in
# WireFunction the package-qualified annotation beside a local definition named Status.
PILOT_REQUIREMENTS = MARKER + '''package WstxRequirements {
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
    requirement 'FR-001' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
}
'''
PILOT_ENGINE = '''package EngineFunction {
    private import ScalarValues::*;
    private import ModelBindings::*;
    private import WstxRequirements::*;
    part def QsoAndLogging;
    action def StandardContact {
        @ImplementedIn { module = "server/src/contact.rs"; }
        @DetailTests { tests = "server/src/contact_tests.rs"; covers = "the engine on a virtual clock"; }
    }
    requirement 'CL-003-01' {
        subject qso : QsoAndLogging;
        @Status { build = ImplementationState::implemented; }
    }
    verification def EngineCase {
        subject qso : QsoAndLogging;
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no RF";
        @Automation { run = AutomationState::implemented; }
    }
    verification 'TC-001-001' : EngineCase {
        objective { verify 'CL-003-01'; verify WstxRequirements::'FR-001'; verify WireFunction::'CL-003-02'; }
        @TestedBy { test = "server/src/contact_tests.rs"; }
    }
    verification def ReviewCase {
        subject qso : QsoAndLogging;
        @Automation { run = AutomationState::partial; method = "manual"; }
    }
    verification 'TC-001-002' : ReviewCase {
        objective { verify 'CL-003-01'; }
        @TestedBy { test = "server/src/review_notes.rs"; }
    }
    dependency owns from 'CL-003-01' to WstxRequirements::'FR-001';
    dependency checks from 'CL-003-01' to 'TC-001-001';
    dependency reviews from 'CL-003-01' to 'TC-001-002';
}
'''
PILOT_WIRE = '''package WireFunction {
    part def Station;
    item def Status;
    requirement 'CL-003-02' {
        subject station : Station;
        @ModelBindings::Status { build = WstxRequirements::ImplementationState::partial; }
        @ModelBindings::ImplementedIn { module = "server/src/wire.rs"; }
    }
    dependency owns from 'CL-003-02' to WstxRequirements::'FR-001';
    dependency checks from 'CL-003-02' to EngineFunction::'TC-001-001';
}
'''
PILOT_SCOPE = "package WstxProductScope { private import EngineFunction::*; private import WireFunction::*; }\n"


class NewFormsOnThePilotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.models = self.root / "docs/sysml"
        texts = {name: "package " + package + " {}\n" for name, package in REQUIRED_FILES.items()}
        texts.update({"Requirements.sysml": PILOT_REQUIREMENTS, "ProductScope.sysml": PILOT_SCOPE,
                      "ModelBindings.sysml": MODEL_BINDINGS, "backend/qso/Engine.sysml": PILOT_ENGINE,
                      "interfaces/Wire.sysml": PILOT_WIRE})
        for key, text in texts.items():
            path = self.models / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        (self.root / "server/src").mkdir()
        for name, text in (("contact.rs", ""), ("wire.rs", ""), ("review_notes.rs", ""),
                           ("contact_tests.rs", "// Proves: TC-001-001\n#[test]\nfn engine() {}\n")):
            (self.root / "server/src" / name).write_text(text, encoding="utf-8")

    # T9, a guard of existing behaviour: the Pilot is not changed, it proves the definitions.
    # Proves: CL-014-11; TC-DOC-009
    def test_real_pilot_resolves_the_model_bindings_definitions_and_the_new_forms(self):
        paths = [self.models / "Requirements.sysml",
                 *sorted(path for path in self.models.rglob("*.sysml") if path.name != "Requirements.sysml")]
        result = tool.validate(paths, CACHE)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed.", result.stdout)

    # T9, the same text read by the catalog
    # Proves: CL-014-11; TC-DOC-009
    def test_catalog_reads_the_text_the_pilot_resolves(self):
        entries = tool.canonical_catalog(self.models, self.root, required=REQUIRED)
        expected = {
            "FR-001": ("target", [], False),
            "CL-003-01": ("implemented", ["server/src/contact.rs"], False),
            "CL-003-02": ("partial", ["server/src/wire.rs"], False),
            "TC-001-001": ("implemented", ["server/src/contact_tests.rs"], False),
            "TC-001-002": ("partial", ["server/src/review_notes.rs"], True),
        }
        self.assertEqual({identifier: (entry["state"], entry["bindings"], entry["manual"]) for identifier, entry in entries.items()}, expected)


# The attribute forms of a declaration, as the model on master writes them.
COVERAGE_ATTRIBUTE = re.compile(r"\battribute\s+coverage\s*:\s*ImplementationState\s*=\s*(ImplementationState::\w+)\s*;")
AUTOMATION_ATTRIBUTE = re.compile(r"\battribute\s+automation\s*:\s*AutomationState\s*=\s*(AutomationState::\w+)\s*;")
IMPLEMENTATION_ATTRIBUTE = re.compile(r'\battribute\s+implementation\s*:\s*String\s*=\s*("[^"\r\n]*")\s*;')
EXECUTABLE_ATTRIBUTE = re.compile(r'\battribute\s+executable\s*:\s*String\s*=\s*("[^"\r\n]*")\s*;')
METHOD_ATTRIBUTE = re.compile(r'[ \t]*\battribute\s+method\s*:\s*String\s*=\s*("[^"\r\n]*")\s*;[ \t]*\r?\n?')
LEXEME = re.compile(r'/\*[\s\S]*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[^/"\']+|.')
IDENTITY_HEADER = re.compile(r"\b(requirement|verification)(?:\s+def)?\s+'(?:FR-\d{3}|CL-\d{3}-\d{2}|TC-\d{3}-\d{3})'\s*\{")


def to_metadata(text):
    """`text` with every status, binding and method attribute of a declaration rewritten to
    ModelBindings metadata; returns (text, number of attributes rewritten)."""
    # Comments and strings blanked at the same offsets, so that braces are counted in code only.
    code = "".join(re.sub(r"[^\r\n]", " ", token.group()) if token.group()[0] in '/"' and len(token.group()) > 1 else token.group()
                   for token in LEXEME.finditer(text))
    rewritten = 0
    for header in reversed(list(IDENTITY_HEADER.finditer(code))):
        depth, end = 1, header.end()
        while depth:
            depth += {"{": 1, "}": -1}.get(code[end], 0)
            end += 1
        body = text[header.end():end - 1]
        if header[1] == "requirement":
            body, states = COVERAGE_ATTRIBUTE.subn(r"@ModelBindings::Status { build = \1; }", body)
            body, bound = IMPLEMENTATION_ATTRIBUTE.subn(lambda found: "@ModelBindings::ImplementedIn { module = " + found[1] + "; }", body)
            rewritten += states + bound
        else:
            method = METHOD_ATTRIBUTE.search(body)
            if method and AUTOMATION_ATTRIBUTE.search(body):
                body = METHOD_ATTRIBUTE.sub("", body, count=1)
                rewritten += 1
            stated_method = " method = " + method[1] + ";" if method else ""
            body, states = AUTOMATION_ATTRIBUTE.subn(lambda found: "@ModelBindings::Automation { run = " + found[1] + ";" + stated_method + " }", body)
            body, bound = EXECUTABLE_ATTRIBUTE.subn(lambda found: "@ModelBindings::TestedBy { test = " + found[1] + "; }", body)
            rewritten += states + bound
        text = text[:header.end()] + body + text[end - 1:]
    return text, rewritten


class RealModelAsMetadataTests(unittest.TestCase):
    # T10: the real pinned Pilot on the real model, rewritten to the metadata forms.
    # Proves: CL-014-11; TC-DOC-009
    def test_real_model_rewritten_to_metadata_passes_check_with_the_same_catalog(self):
        real = {path.relative_to(tool.MODELS).as_posix(): path for path in sorted(tool.MODELS.rglob("*.sysml"))}
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory) / "docs/sysml"
            total = 0
            for key, path in real.items():
                source = path.read_text(encoding="utf-8")
                text, count = to_metadata(source)
                total += count
                target = copy / key
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text, encoding="utf-8", newline="")
                # Each relative documentation link keeps its target beside the copy.
                for link in re.findall(r"\]\(([^)]+)\)", source):
                    link = urllib.parse.unquote(link.strip("<>").split("#", 1)[0])
                    linked = (path.parent / link).resolve()
                    if link and not link.startswith(("https://", "http://")) and linked.is_file():
                        beside = (target.parent / link).resolve()
                        self.assertTrue(beside.is_relative_to(Path(directory).resolve()), key + ": " + link)
                        if not beside.exists():
                            beside.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copyfile(linked, beside)
            if not any(re.search(r"\bpackage\s+ModelBindings\b", path.read_text(encoding="utf-8")) for path in real.values()):
                (copy / "ModelBindings.sysml").write_text(MODEL_BINDINGS, encoding="utf-8")
            # While the model on master holds attribute forms, the copy must differ from it.
            attributes_in_real = sum(len(pattern.findall(path.read_text(encoding="utf-8"))) for path in real.values()
                                     for pattern in (COVERAGE_ATTRIBUTE, AUTOMATION_ATTRIBUTE))
            self.assertTrue(total or not attributes_in_real, "the real model holds attribute forms and none was rewritten")
            for key in real:
                declared = (copy / key).read_text(encoding="utf-8")
                self.assertEqual(to_metadata(declared)[1], 0, key)
            self.assertEqual(tool.canonical_catalog(copy, tool.ROOT), tool.canonical_catalog(tool.MODELS, tool.ROOT))

            def check(models):
                output, errors = io.StringIO(), io.StringIO()
                with mock.patch.object(tool, "MODELS", models), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    status = tool.main(["check"])
                self.assertEqual(status, 0, output.getvalue() + errors.getvalue())
                return [line for line in output.getvalue().splitlines() if "identities" in line or line.startswith("Architecture integrity passed")]

            rewritten = check(copy)
            self.assertEqual(len(rewritten), 2, rewritten)
            self.assertEqual(rewritten, check(tool.MODELS))


if __name__ == "__main__":
    unittest.main()
