"""TC-DOC-008: the model is a tree of files below docs/sysml, named by key.

A required package is found by its package, in a file of any name and folder. Isolated
fixtures in a temporary folder; one test (the relocated real model) runs the real pinned
Pilot, and two build a throwaway git repository for the gate's model bindings.
"""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import urllib.parse

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("tree_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

REQUIRED = {"FR-901", "CL-003-01", "TC-001-001"}
ENUMS = '''    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
'''
FR = '''    requirement 'FR-901' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
'''
CLAUSE = '''    requirement 'CL-003-01' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
'''
CASE = '''    verification 'TC-001-001' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'FR-901'; verify 'CL-003-01'; }
    }
'''
OWNS = "    dependency owns from 'CL-003-01' to 'FR-901';\n"
CHECKS = "    dependency checks from 'CL-003-01' to 'TC-001-001';\n"
MARKER = "// Canonical authority: SysML\n"
# The whole catalog in the entry file, and the same catalog split over two folders.
FLAT = MARKER + "package WstxRequirements {\n" + ENUMS + FR + CLAUSE + CASE + OWNS + CHECKS + "}\n"
TOP = MARKER + "package WstxRequirements {\n" + ENUMS + FR + "}\n"
PART = "package PPart {\n" + CLAUSE + CASE + OWNS + CHECKS + "}\n"
PART_KEY = "backend/qso/Part.sysml"
SCOPE_WITH_PART = "package WstxProductScope { private import PPart::*; }"
# The fixture's model files and the required package each declares, written by hand from
# the contract's list of required packages.
REQUIRED_FILES = {
    "Requirements.sysml": "WstxRequirements", "Architecture.sysml": "WstxArchitecture",
    "Profiles.sysml": "WstxProfiles", "RecordingReceive.sysml": "WstxRecordingReceive",
    "StationDecode.sysml": "WstxOfflineDecode", "RadioIO.sysml": "WstxRadioIO",
    "OperatingLayout.sysml": "WstxOperatingLayout", "OperatingReceive.sysml": "WstxOperatingReceive",
    "StationProtocol.sysml": "WstxStationProtocol", "ProductScope.sysml": "WstxProductScope",
}
RADIO_MISSING = r"Canonical model packages missing: WstxRadioIO$"


class ModelTreeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        self.models = self.root / "docs/sysml"
        self.fsd = self.root / "docs/FSD.md"
        self.written = {}
        for name, package in REQUIRED_FILES.items():
            self.write(name, "package " + package + " {}")
        self.write("Requirements.sysml", FLAT)

    def write(self, key, text):
        path = self.models / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        self.written[key] = text
        return path

    def remove(self, key):
        (self.models / key).unlink()
        del self.written[key]

    def tree(self, part=PART):
        """The catalog split: the FR in the root entry file, clause and case two folders down."""
        self.write("Requirements.sysml", TOP)
        self.write("ProductScope.sysml", SCOPE_WITH_PART)
        self.write(PART_KEY, part)

    def check(self):
        return tool.canonical_catalog(self.models, self.root, required=REQUIRED)

    def refused(self, message):
        return self.assertRaisesRegex(ValueError, message)

    def command(self, *argv, validate=None):
        """Run a command of the tool on the fixture; returns (exit code, stdout, stderr)."""
        real_catalog = tool.canonical_catalog
        output, errors = io.StringIO(), io.StringIO()
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), \
                mock.patch.object(tool, "FSD", self.fsd), \
                mock.patch.object(tool, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)), \
                mock.patch.object(tool, "validate", validate or mock.Mock(side_effect=AssertionError("validator invoked"))), \
                mock.patch.object(tool, "architecture_integrity", return_value={"connections": 0}), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(list(argv))
        return status, output.getvalue(), errors.getvalue()

    # T1
    # Proves: CL-014-10; TC-DOC-008
    def test_identities_in_a_subfolder_file_are_cataloged_and_a_duplicate_across_folders_refused(self):
        self.tree()
        self.assertEqual(set(self.check()), REQUIRED)
        self.write("other/More.sysml", "package PPart {\n" + CLAUSE + "}\n")
        with self.refused("Duplicate canonical identity: CL-003-01"):
            self.check()

    def elsewhere(self):
        """The ten required packages in files of other names, half of them at the root and
        half two folders down. The entry file keeps its name and the marker and holds an
        additional package. Returns {package: key}."""
        for key in list(self.written):
            self.remove(key)
        keys = {package: ("" if index % 2 else "area/part/") + "File" + str(index) + ".sysml"
                for index, package in enumerate(sorted(REQUIRED_FILES.values()))}
        for package, key in keys.items():
            self.write(key, "package " + package + " {}")
        self.write(keys["WstxRequirements"], FLAT[len(MARKER):])
        self.write(keys["WstxProductScope"], "package WstxProductScope { private import Entry::*; }")
        self.write("Requirements.sysml", MARKER + "package Entry {}")
        return keys

    def without_radio_package(self):
        """The fixture with no file of package WstxRadioIO, and no other fault."""
        self.write("RadioIO.sysml", "package Moved {}")
        self.write("ProductScope.sysml", "package WstxProductScope { private import Moved::*; }")

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                        "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "--no-verify", "-m", message)

    # Required packages T1: none and one
    # Proves: CL-014-10; TC-DOC-008
    def test_required_package_is_found_by_package_in_a_file_of_any_name_and_folder(self):
        keys = self.elsewhere()
        with self.subTest("ten packages, no required file name but the entry file"):
            self.assertEqual(len(keys), 10)
            self.assertEqual(set(self.written) & set(REQUIRED_FILES), {"Requirements.sysml"})
            self.assertEqual(sorted("/" in key for key in keys.values()), [False] * 5 + [True] * 5)
            self.assertEqual(set(self.check()), REQUIRED)
            self.assertEqual(tool.authority(self.models, self.fsd), "sysml")
        for package, key in keys.items():
            with self.subTest(removed=package):
                text = self.written[key]
                self.remove(key)
                try:
                    with self.refused("Canonical model packages missing: " + package + "$"):
                        self.check()
                finally:
                    self.write(key, text)
        radio = keys["WstxRadioIO"]
        self.remove(radio)
        # A name that is not the package of its file does not count.
        for label, text in (("in a line comment", "// package WstxRadioIO {}\n"),
                            ("in a block comment", "/* package WstxRadioIO {\n} */\n"),
                            ("a longer name", "package WstxRadioIOX {}"),
                            ("nested in another package", "package Outer { package WstxRadioIO {} }"),
                            ("the second package of the file", "package First {}\npackage WstxRadioIO {}")):
            with self.subTest(label):
                self.write(radio, text)
                with self.refused(RADIO_MISSING):
                    self.check()
        self.remove(radio)
        self.remove(keys["WstxProfiles"])
        with self.subTest("two removed"), self.refused(r"Canonical model packages missing: WstxProfiles, WstxRadioIO$"):
            self.check()

    # Required packages T2: two
    # Proves: CL-014-10; TC-DOC-008
    def test_required_package_in_two_files_is_refused_and_a_file_name_may_repeat(self):
        self.write("radio/Other.sysml", "package WstxRadioIO {}")
        with self.subTest("one package, two files"), self.refused(
                r"Duplicate canonical model package: WstxRadioIO: RadioIO\.sysml, radio/Other\.sysml$"):
            self.check()
        self.remove("radio/Other.sysml")
        self.write("radio/RadioIO.sysml", "package RadioCapture {}")
        self.write("ProductScope.sysml", "package WstxProductScope { private import RadioCapture::*; }")
        with self.subTest("one file name, two packages"):
            self.assertEqual(set(self.check()), REQUIRED)

    # Required packages T3: the file of a required package split into function files
    # Proves: CL-014-10; TC-DOC-008
    def test_required_file_split_into_function_files_keeps_the_identities(self):
        content = CLAUSE + CASE + OWNS + CHECKS + "}\n"
        self.write("Requirements.sysml", TOP)
        self.write("RadioIO.sysml", "package WstxRadioIO {\n" + content)
        before = set(self.check())
        self.assertEqual(before, REQUIRED)
        self.remove("RadioIO.sysml")
        self.write("backend/radio/Cat.sysml", "package WstxRadioIO {}")
        self.write("backend/radio/Capture.sysml", "package WstxRadioCapture {\n" + content)
        with self.subTest("without the scope reference"), self.refused(
                r"lacks a ProductScope reference: backend/radio/Capture\.sysml$"):
            self.check()
        self.write("ProductScope.sysml", "package WstxProductScope { private import WstxRadioCapture::*; }")
        with self.subTest("with the scope reference"):
            self.assertEqual(set(self.check()), before)
        self.write("backend/radio/Cat.sysml", "package WstxRadioCat {}")
        with self.subTest("the required package renamed too"), self.refused(RADIO_MISSING):
            self.check()

    # Required packages T4: the ProductScope text is the file of the scope package
    # Proves: CL-014-10; TC-DOC-008
    def test_productscope_text_is_the_file_whose_package_is_the_scope_package(self):
        self.remove("ProductScope.sysml")
        self.write("Future.sysml", "package FutureBackend {}")
        self.write("nav/Scope.sysml", "package WstxProductScope { private import FutureBackend::*; }")
        with self.subTest("the scope package under another file name, in a folder"):
            self.assertEqual(set(self.check()), REQUIRED)
        self.write("nav/Scope.sysml", "package WstxProductScope { private import Decoy::*; }")
        self.write("ProductScope.sysml", "package Decoy { private import FutureBackend::*; }")
        with self.subTest("the reference only in a file named ProductScope.sysml"), self.refused(
                r"lacks a ProductScope reference: Future\.sysml$"):
            self.check()

    # Required packages T5: a file name gives no exemption
    # Proves: CL-014-10; TC-DOC-008
    def test_file_of_a_required_name_with_another_package_is_an_additional_package(self):
        self.write("RadioIO.sysml", "package Other {}")
        self.write("radio/Cat.sysml", "package WstxRadioIO {}")
        with self.refused(r"lacks a ProductScope reference: RadioIO\.sysml$"):
            self.check()

    # Required packages T5, a guard of existing behaviour: no package, and the library packages
    # Proves: CL-014-10; TC-DOC-008
    def test_file_without_a_package_needs_the_reference_and_a_library_package_none(self):
        self.write("shared/Notes.sysml", "package ModelNotes { metadata def NotStated; }")
        self.write("shared/Bindings.sysml", "package ModelBindings { metadata def Status; }")
        with self.subTest("library packages"):
            self.assertEqual(set(self.check()), REQUIRED)
        for key in ("Loose.sysml", "notes/Loose.sysml"):
            with self.subTest(without_package=key):
                self.write(key, "// package Hidden {}\nattribute def Loose;\n")
                with self.refused("lacks a ProductScope reference: " + re.escape(key) + "$"):
                    self.check()
                self.remove(key)

    # Required packages T6: the commands on a model without a required package
    # Proves: CL-014-10; TC-DOC-008
    def test_check_traces_and_fingerprints_refuse_a_model_without_a_required_package(self):
        self.without_radio_package()
        for name in ("check", "traces", "fingerprints"):
            with self.subTest(command=name):
                # The fixture's validator fails the test when it is invoked.
                self.assertEqual(self.command(name),
                                 (2, "", "SysML check failed: Canonical model packages missing: WstxRadioIO\n"))

    # Required packages T6, a guard of existing behaviour: markers runs no catalog check
    # Proves: CL-014-10; TC-DOC-008
    def test_markers_lists_a_model_without_a_required_package(self):
        self.without_radio_package()
        self.write("shared/ModelNotes.sysml", "package ModelNotes { metadata def NotStated { attribute what : String; } }")
        self.write("RadioIO.sysml", 'package Moved {\n    @NotStated { what = "the level"; }\n}\n')
        self.assertEqual(self.command("markers"), (0, "RadioIO.sysml:2: NotStated: the level\n1 markers: 1 NotStated\n", ""))

    # Required packages T6: the gate's model bindings on moved and renamed files
    # Proves: CL-014-10; TC-DOC-008
    def test_gate_model_bindings_follow_moved_and_renamed_required_files(self):
        spec = importlib.util.spec_from_file_location("required_model_bindings", ROOT / ".harness/model_bindings.py")
        bindings = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bindings)
        bound = 'AutomationState::partial;\n        attribute executable : String = "tests/case.cjs";'
        (self.root / "tests/case.cjs").write_text("// Proves: TC-001-001\ntest('identity',()=>{});\n", encoding="utf-8")
        self.write("Requirements.sysml", FLAT.replace("AutomationState::planned;", bound))
        self.git("init", "-q")
        self.commit("flat")
        flat_keys = sorted(self.written)
        # Every file of a required package but the entry file, moved and renamed.
        for index, key in enumerate(key for key in flat_keys if key != "Requirements.sysml"):
            text = self.written[key]
            self.remove(key)
            self.write(("moved/deep/" if index % 2 else "moved/") + "M" + str(index) + ".sysml", text)
        self.commit("moved and renamed")
        moved_keys = sorted(self.written)
        radio = next(key for key, text in self.written.items() if text == "package WstxRadioIO {}")
        self.remove(radio)
        self.commit("without the package")
        case = {"automated": True, "verifies": ["FR-901", "CL-003-01"], "paths": ["tests/case.cjs"],
                "tests": [{"path": "tests/case.cjs", "name": "identity"}], "unresolved": []}
        real_catalog = bindings.sysml.canonical_catalog
        with mock.patch.object(bindings, "ROOT", self.root), \
                mock.patch.object(bindings.sysml, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)):
            flat = bindings.bindings("HEAD~2")
            with self.subTest("revision 1, flat"):
                self.assertEqual(flat["models"], ["docs/sysml/" + key for key in flat_keys])
                self.assertEqual(flat["cases"], {"TC-001-001": case})
                self.assertEqual(set(flat["promises"]), {"FR-901", "CL-003-01"})
            with self.subTest("revision 2, moved and renamed"):
                moved = bindings.bindings("HEAD~1")
                self.assertEqual(moved["models"], ["docs/sysml/" + key for key in moved_keys])
                self.assertEqual((moved["cases"], moved["promises"]), (flat["cases"], flat["promises"]))
            with self.subTest("revision 3, without the package"):
                output, errors = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    status = bindings.main(["--rev", "HEAD"])
                self.assertEqual((status, output.getvalue(), errors.getvalue()),
                                 (2, "", "model bindings: Canonical model packages missing: WstxRadioIO\n"))
        self.assertEqual(set(moved_keys) & set(flat_keys), {"Requirements.sysml"})
        self.assertEqual(len(moved_keys), 10)

    # T3, a guard of existing behaviour
    # Proves: CL-014-10; TC-DOC-008
    def test_entry_file_is_required_directly_in_the_model_folder(self):
        self.assertEqual(tool.authority(self.models, self.fsd), "sysml")
        self.remove("Requirements.sysml")
        self.write("top/Requirements.sysml", FLAT)
        with self.refused("No declared functional authority"):
            tool.authority(self.models, self.fsd)
        for name in ("check", "traces", "fingerprints"):
            with self.subTest(command=name):
                status, _output, errors = self.command(name)
                self.assertEqual(status, 2)
                self.assertIn("No declared functional authority", errors)

    # T4
    # Proves: CL-014-10; TC-DOC-008
    def test_verify_through_package_names_is_read_and_checked_as_an_unqualified_one(self):
        for qualifier in ("PPart::", "A::B::"):
            with self.subTest(accepted=qualifier):
                self.write("Requirements.sysml", FLAT.replace("verify 'CL-003-01';", "verify " + qualifier + "'CL-003-01';"))
                self.assertEqual(self.check()["TC-001-001"]["refs"], ["FR-901", "CL-003-01"])
        second = '''    verification 'TC-001-002' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify PPart::'CL-003-01'; }
    }
}
'''
        with self.subTest("without the reciprocal dependency"):
            self.write("Requirements.sysml", FLAT.rsplit("}", 1)[0] + second)
            with self.refused("Nonreciprocal canonical verification links: TC-001-002"):
                self.check()
        with self.subTest("undefined target"):
            self.write("Requirements.sysml", FLAT.replace("verify 'FR-901';", "verify PPart::'FR-999';"))
            with self.refused("verification target: TC-001-001"):
                self.check()

    # T5
    # Proves: CL-014-10; TC-DOC-008
    def test_clause_dependency_ends_through_package_names_are_read_and_checked(self):
        owns = "    dependency owns from PPart::'CL-003-01' to WstxRequirements::'FR-901';\n"
        checks = "    dependency checks from PPart::'CL-003-01' to A::B::'TC-001-001';\n"
        self.write("Requirements.sysml", FLAT.replace(OWNS, owns).replace(CHECKS, checks))
        self.assertEqual(set(self.check()), REQUIRED)
        for label, text in (("owner", FLAT.replace(OWNS, owns.replace("FR-901", "FR-999")).replace(CHECKS, checks)),
                            ("case", FLAT.replace(OWNS, owns).replace(CHECKS, checks.replace("TC-001-001", "TC-001-999")))):
            with self.subTest(undefined=label):
                self.write("Requirements.sysml", text)
                with self.refused("Invalid canonical clause dependency: CL-003-01 -> "):
                    self.check()

    # T6
    # Proves: CL-014-10; TC-DOC-008
    def test_additional_package_needs_a_productscope_reference_by_name_import_or_alias(self):
        # The same forms hold for a file at the root and in a folder; the message names the key.
        for key in ("Future.sysml", "interfaces/Future.sysml"):
            self.write(key, "package FutureBackend {}")
            for scope in ("private import FutureBackend::*;", "attribute a : FutureBackend::T;",
                          "import FutureBackend;", "private import FutureBackend ;", "alias F for FutureBackend;"):
                with self.subTest(key=key, accepted=scope):
                    self.write("ProductScope.sysml", "package WstxProductScope { " + scope + " }")
                    self.assertEqual(set(self.check()), REQUIRED)
            for scope in ("", "// import FutureBackend;", "/* alias F for FutureBackend; FutureBackend::T */",
                          "private import FutureBackendX::*;", "import FutureBackendX;", "alias FutureBackend for Other;",
                          "import XFutureBackend;"):
                with self.subTest(key=key, refused=scope):
                    self.write("ProductScope.sysml", "package WstxProductScope { " + scope + " }")
                    with self.refused("Additional canonical package lacks a ProductScope reference: " + re.escape(key) + "$"):
                        self.check()
            self.remove(key)

    # T7
    # Proves: CL-014-10; TC-DOC-008
    def test_library_package_needs_no_productscope_reference(self):
        for key in ("ModelNotes.sysml", "shared/ModelNotes.sysml", "shared/Notes.sysml"):
            with self.subTest(accepted=key):
                self.write(key, "package ModelNotes { metadata def NotStated; }")
                self.assertEqual(set(self.check()), REQUIRED)
                self.remove(key)
        for key, package in (("ModelNotes.sysml", "Other"), ("shared/ModelNotes.sysml", "Other"),
                             ("Unlisted.sysml", "Unlisted"), ("ModelNotes.sysml", "ModelNotesX")):
            with self.subTest(refused=key, package=package):
                self.write(key, "package " + package + " {}")
                with self.refused("lacks a ProductScope reference: " + re.escape(key) + "$"):
                    self.check()
                self.remove(key)
        self.assertEqual(tool.LIBRARY_PACKAGES, {"ModelNotes", "ModelBindings"})

    # T8
    # Proves: CL-014-10; TC-DOC-008
    def test_documentation_link_resolves_from_the_files_own_folder_and_messages_name_the_key(self):
        # Three folders up from docs/sysml/backend/qso is docs, so the target is docs/tests/case.cjs.
        linked = PART.replace("package PPart {", "package PPart {\n    doc /* [t](../../../tests/case.cjs) */")
        target = self.root / "docs/tests/case.cjs"
        target.parent.mkdir()
        self.tree(linked)
        with self.subTest("missing target"), self.refused(
                r"Dangling model documentation link: backend/qso/Part\.sysml: \.\./\.\./\.\./tests/case\.cjs$"):
            self.check()
        target.write_text("", encoding="utf-8")
        with self.subTest("existing target"):
            self.assertEqual(set(self.check()), REQUIRED)
        self.tree(PART + "// Canonical FSD slices SHA256: stale\n")
        with self.subTest("retired FSD"), self.refused(r"retired FSD dependency: backend/qso/Part\.sysml$"):
            self.check()

    # T9
    # Proves: CL-014-10; TC-DOC-008
    def test_fingerprints_name_every_file_by_key_with_the_hash_of_its_text(self):
        def fingerprints():
            status, output, errors = self.command("fingerprints")
            self.assertEqual(status, 0, errors)
            return json.loads(output, object_pairs_hook=list)

        def expected():
            return [(key, hashlib.sha256(self.written[key].encode("utf-8")).hexdigest()) for key in sorted(self.written)]

        with self.subTest("flat"):
            self.assertEqual(fingerprints(), expected())
            self.assertTrue(all("/" not in key for key, _hash in fingerprints()))
        self.tree()
        self.write("radio/RadioIO.sysml", "package WstxRadioIO { /* moved */ }")
        self.remove("RadioIO.sysml")
        with self.subTest("tree"):
            self.assertEqual(len(self.written), 11)
            self.assertIn(PART_KEY, self.written)
            self.assertEqual(fingerprints(), expected())

    # T10
    # Proves: CL-014-10; TC-DOC-008
    def test_check_validates_every_file_once_entry_first_then_sorted_by_key(self):
        self.tree()
        self.write("radio/RadioIO.sysml", "package WstxRadioIO {}")
        self.remove("RadioIO.sysml")
        validate = mock.Mock(return_value=subprocess.CompletedProcess([], 0, "semantic fixture", ""))
        status, _output, errors = self.command("check", validate=validate)
        self.assertEqual(status, 0, errors)
        others = sorted(key for key in self.written if key != "Requirements.sysml")
        self.assertEqual(len(others), 10)
        self.assertEqual(validate.call_args.args[0],
                         [self.models / "Requirements.sysml", *(self.models / key for key in others)])

    # T11
    # Proves: CL-014-10; TC-DOC-008
    def test_gate_model_bindings_read_and_list_the_tree_of_a_revision(self):
        spec = importlib.util.spec_from_file_location("tree_model_bindings", ROOT / ".harness/model_bindings.py")
        bindings = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bindings)

        def git(*args):
            subprocess.run(["git", "-C", str(self.root), "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                            "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)

        bound = 'AutomationState::partial;\n        attribute executable : String = "tests/case.cjs";'
        (self.root / "tests/case.cjs").write_text("// Proves: TC-001-001\ntest('identity',()=>{});\n", encoding="utf-8")
        self.write("Requirements.sysml", FLAT.replace("AutomationState::planned;", bound))
        git("init", "-q")
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "flat")
        flat_keys = sorted(self.written)
        self.tree(PART.replace("AutomationState::planned;", bound))
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "tree")
        tree_keys = sorted(self.written)
        real_catalog = bindings.sysml.canonical_catalog
        case = {"automated": True, "verifies": ["FR-901", "CL-003-01"], "paths": ["tests/case.cjs"],
                "tests": [{"path": "tests/case.cjs", "name": "identity"}], "unresolved": []}
        with mock.patch.object(bindings, "ROOT", self.root), \
                mock.patch.object(bindings.sysml, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)):
            for rev, keys in (("HEAD~1", flat_keys), ("HEAD", tree_keys)):
                with self.subTest(rev=rev):
                    result = bindings.bindings(rev)
                    self.assertEqual(result["models"], ["docs/sysml/" + key for key in keys])
                    self.assertEqual(result["cases"], {"TC-001-001": case})
                    self.assertEqual(set(result["promises"]), {"FR-901", "CL-003-01"})
        self.assertIn(PART_KEY, tree_keys)
        self.assertTrue(all("/" not in key for key in flat_keys))


class RelocatedRealModelTests(unittest.TestCase):
    # Required packages T7: the real pinned Pilot on the real model.
    # Proves: CL-014-10; TC-DOC-008
    def test_real_model_with_a_required_package_moved_and_renamed_passes_check_with_the_same_identities(self):
        # The real model as it stands, flat or already in folders: {key: path}, and per key the
        # relative documentation links that reach an existing file, as (link, real target).
        real = {path.relative_to(tool.MODELS).as_posix(): path for path in sorted(tool.MODELS.rglob("*.sysml"))}
        links = {}
        for key, path in real.items():
            found = (urllib.parse.unquote(link.strip("<>").split("#", 1)[0])
                     for link in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")))
            links[key] = [(link, (path.parent / link).resolve()) for link in found
                          if link and not link.startswith(("https://", "http://")) and (path.parent / link).resolve().is_file()]
        model_paths = {path.resolve() for path in real.values()}
        linked = {target for found in links.values() for _link, target in found}
        # Relocate the first file other than the entry file, at any depth, whose package is a
        # required one. A link between two model files holds only while both keep their folders,
        # so a file with such a link at either end is passed over.
        def package(path):
            code = re.sub(r"/\*[\s\S]*?\*/|//[^\r\n]*", " ", path.read_text(encoding="utf-8"))
            found = re.search(r"\bpackage\s+(\w+)\s*\{", code)
            return found[1] if found else None

        movable = [key for key, path in real.items()
                   if key != "Requirements.sysml" and package(path) in REQUIRED_FILES.values() and path.resolve() not in linked
                   and not any(target in model_paths for _link, target in links[key])]
        self.assertTrue(movable, "no model file of a required package, other than the entry file and without "
                                 "a relative link to or from another model file, can be relocated")
        relocated_key = "relocated-by-test/Renamed.sysml"
        self.assertNotEqual(Path(relocated_key).name, Path(movable[0]).name)
        self.assertNotIn(relocated_key, real)
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory) / "docs/sysml"
            for key, path in real.items():
                moved = copy / (relocated_key if key == movable[0] else key)
                moved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, moved)
                # Each link keeps a target where it resolves from the linking file's folder in the copy.
                for link, source in links[key]:
                    if source in model_paths:
                        continue
                    target = (moved.parent / link).resolve()
                    self.assertTrue(target.is_relative_to(Path(directory).resolve()), key + ": " + link)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, target)
            self.assertTrue((copy / relocated_key).is_file() and not (copy / movable[0]).exists())
            self.assertEqual(set(tool.canonical_catalog(copy, tool.ROOT)), set(tool.canonical_catalog(tool.MODELS, tool.ROOT)))

            def check(models):
                output, errors = io.StringIO(), io.StringIO()
                with mock.patch.object(tool, "MODELS", models), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    status = tool.main(["check"])
                self.assertEqual(status, 0, output.getvalue() + errors.getvalue())
                return [line for line in output.getvalue().splitlines() if "identities" in line or line.startswith("Architecture integrity passed")]

            relocated = check(copy)
            self.assertEqual(len(relocated), 2, relocated)
            self.assertEqual(relocated, check(tool.MODELS))


if __name__ == "__main__":
    unittest.main()
