"""TC-DOC-008: the model is a tree of files below docs/sysml, named by key.

Isolated fixtures in a temporary folder; one test (the relocated real model) runs the
real pinned Pilot, and one builds a throwaway git repository for the gate's model bindings.
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

REQUIRED = {"FR-001", "CL-003-01", "TC-001-001"}
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
MARKER = "// Canonical authority: SysML\n"
# The whole catalog in the entry file, and the same catalog split over two folders.
FLAT = MARKER + "package PTop {\n" + ENUMS + FR + CLAUSE + CASE + OWNS + CHECKS + "}\n"
TOP = MARKER + "package PTop {\n" + ENUMS + FR + "}\n"
PART = "package PPart {\n" + CLAUSE + CASE + OWNS + CHECKS + "}\n"
PART_KEY = "backend/qso/Part.sysml"
SCOPE_WITH_PART = "package Scope { private import PPart::*; }"


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
        for name in tool.CANONICAL_MODELS:
            self.write(name, "package P" + name.split(".")[0] + " {}")
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

    # T2
    # Proves: CL-014-10; TC-DOC-008
    def test_required_file_is_found_exactly_once_at_any_depth(self):
        radio = (self.models / "RadioIO.sysml").read_text(encoding="utf-8")
        self.remove("RadioIO.sysml")
        with self.subTest("none"), self.refused(r"Canonical model files missing: RadioIO\.sysml$"):
            self.check()
        self.write("radio/RadioIO.sysml", radio)
        with self.subTest("one, in a folder"):
            self.assertEqual(set(self.check()), REQUIRED)
        self.write("RadioIO.sysml", radio)
        with self.subTest("two"), self.refused(r"RadioIO\.sysml: RadioIO\.sysml, radio/RadioIO\.sysml$"):
            self.check()

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
                self.assertEqual(self.check()["TC-001-001"]["refs"], ["FR-001", "CL-003-01"])
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
            self.write("Requirements.sysml", FLAT.replace("verify 'FR-001';", "verify PPart::'FR-999';"))
            with self.refused("verification target: TC-001-001"):
                self.check()

    # T5
    # Proves: CL-014-10; TC-DOC-008
    def test_clause_dependency_ends_through_package_names_are_read_and_checked(self):
        owns = "    dependency owns from PPart::'CL-003-01' to PTop::'FR-001';\n"
        checks = "    dependency checks from PPart::'CL-003-01' to A::B::'TC-001-001';\n"
        self.write("Requirements.sysml", FLAT.replace(OWNS, owns).replace(CHECKS, checks))
        self.assertEqual(set(self.check()), REQUIRED)
        for label, text in (("owner", FLAT.replace(OWNS, owns.replace("FR-001", "FR-999")).replace(CHECKS, checks)),
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
                    self.write("ProductScope.sysml", "package Scope { " + scope + " }")
                    self.assertEqual(set(self.check()), REQUIRED)
            for scope in ("", "// import FutureBackend;", "/* alias F for FutureBackend; FutureBackend::T */",
                          "private import FutureBackendX::*;", "import FutureBackendX;", "alias FutureBackend for Other;",
                          "import XFutureBackend;"):
                with self.subTest(key=key, refused=scope):
                    self.write("ProductScope.sysml", "package Scope { " + scope + " }")
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
        self.assertEqual(tool.LIBRARY_PACKAGES, {"ModelNotes"})

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
        # The same file name where the link would resolve from the model's root folder is not the target.
        (self.root / "tests/case.cjs").write_text("", encoding="utf-8")
        with self.subTest("target only beside the root"), self.refused(r"Dangling model documentation link: backend/qso/Part\.sysml"):
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
        self.write("radio/RadioIO.sysml", "package PRadioIO { /* moved */ }")
        self.remove("RadioIO.sysml")
        with self.subTest("tree"):
            self.assertEqual(len(self.written), 11)
            self.assertIn(PART_KEY, self.written)
            self.assertEqual(fingerprints(), expected())

    # T10
    # Proves: CL-014-10; TC-DOC-008
    def test_check_validates_every_file_once_entry_first_then_sorted_by_key(self):
        self.tree()
        self.write("radio/RadioIO.sysml", "package PRadioIO {}")
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
        case = {"automated": True, "verifies": ["FR-001", "CL-003-01"], "paths": ["tests/case.cjs"],
                "tests": [{"path": "tests/case.cjs", "name": "identity"}], "unresolved": []}
        with mock.patch.object(bindings, "ROOT", self.root), \
                mock.patch.object(bindings.sysml, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)):
            for rev, keys in (("HEAD~1", flat_keys), ("HEAD", tree_keys)):
                with self.subTest(rev=rev):
                    result = bindings.bindings(rev)
                    self.assertEqual(result["models"], ["docs/sysml/" + key for key in keys])
                    self.assertEqual(result["cases"], {"TC-001-001": case})
                    self.assertEqual(set(result["promises"]), {"FR-001", "CL-003-01"})
        self.assertIn(PART_KEY, tree_keys)
        self.assertTrue(all("/" not in key for key in flat_keys))


class RelocatedRealModelTests(unittest.TestCase):
    # T13: the real pinned Pilot on the real model.
    # Proves: CL-014-10; TC-DOC-008
    def test_real_model_with_one_file_in_a_folder_passes_check_with_the_same_identities(self):
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory) / "docs/sysml"
            flat = {path.relative_to(tool.MODELS).as_posix(): path for path in tool.MODELS.rglob("*.sysml")}
            self.assertIn("Udp.sysml", flat)
            self.assertTrue(all("/" not in key for key in flat), "this test relocates a file of a flat model")
            for key, path in flat.items():
                moved = copy / ("interfaces/Udp.sysml" if key == "Udp.sysml" else key)
                moved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, moved)
                # The model's relative documentation links keep their targets beside the copy.
                for link in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
                    link = urllib.parse.unquote(link.strip("<>").split("#", 1)[0])
                    source = (path.parent / link).resolve()
                    if link and not link.startswith(("https://", "http://")) and source.is_file():
                        target = (copy / link).resolve()
                        self.assertTrue(target.is_relative_to(Path(directory).resolve()), link)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copyfile(source, target)
            self.assertTrue((copy / "interfaces/Udp.sysml").is_file() and not (copy / "Udp.sysml").exists())
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
