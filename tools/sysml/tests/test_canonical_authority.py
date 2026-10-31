"""TC-DOC-007: isolated authority, archive independence and canonical trace refusals."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("canonical_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
REQUIRED = {"FR-001", "CL-003-01", "TC-001-001"}
MODEL = '''// Canonical authority: SysML
package WstxRequirements {
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
    requirement 'FR-001' {
        doc /* Independently observable station identity. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'CL-003-01' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    verification 'TC-001-001' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'FR-001'; verify 'CL-003-01'; }
    }
    dependency owns from 'CL-003-01' to 'FR-001';
    dependency checks from 'CL-003-01' to 'TC-001-001';
}
'''


class CanonicalAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        self.models = self.root / "docs/sysml"
        self.models.mkdir(parents=True)
        self.fsd = self.root / "docs/FSD.md"
        for name in tool.CANONICAL_MODELS:
            (self.models / name).write_text("package P" + name.split(".")[0] + " {}", encoding="utf-8")
        self.requirements = self.models / "Requirements.sysml"
        self.requirements.write_text(MODEL, encoding="utf-8")

    def check(self):
        return tool.canonical_catalog(self.models, self.root, required=REQUIRED)

    def test_exclusive_authority_and_invalid_marker(self):
        self.assertEqual(tool.authority(self.models, self.fsd), "sysml")
        self.fsd.write_text("Unrelated current Markdown", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Two functional authorities"):
            tool.authority(self.models, self.fsd)
        self.requirements.write_text(MODEL.replace(tool.CANONICAL_MARKER, "// legacy"), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Retired Markdown FSD is not a functional authority"):
            tool.authority(self.models, self.fsd)
        self.fsd.unlink()
        with self.assertRaisesRegex(ValueError, "No declared functional authority"):
            tool.authority(self.models, self.fsd)
        self.requirements.unlink()
        with self.assertRaisesRegex(ValueError, "No declared functional authority"):
            tool.authority(self.models, self.fsd)
        self.fsd.write_text("Active FSD without any model", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Retired Markdown FSD"):
            tool.authority(self.models, self.fsd)
        self.fsd.unlink()
        self.requirements.write_text(MODEL, encoding="utf-8")
        for changed in (MODEL + tool.CANONICAL_MARKER, MODEL.replace("authority: SysML", "authority: Markdown")):
            self.requirements.write_text(changed, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Invalid or duplicate"):
                tool.authority(self.models, self.fsd)

    # TC-DOC-002: a mutated identity, state or link, or a missing artifact, is refused by name.
    def test_missing_file_duplicate_id_missing_id_and_wrong_state_refused(self):
        self.assertEqual(set(self.check()), REQUIRED)
        for changed, message in (
            (MODEL.replace("'FR-001' {", "'FR-999' {"), "Missing stable"),
            (MODEL + "requirement 'FR-001' {}", "Duplicate canonical"),
            (MODEL.replace("ImplementationState::target", "ImplementationState::passed", 1), "declared model state"),
        ):
            with self.subTest(message=message):
                self.requirements.write_text(changed, encoding="utf-8")
                with self.assertRaisesRegex(ValueError, message):
                    self.check()
        self.requirements.write_text(MODEL, encoding="utf-8")
        (self.models / "RadioIO.sysml").unlink()
        with self.assertRaisesRegex(ValueError, "Canonical model files missing"):
            self.check()

    def test_undefined_nonreciprocal_and_absent_clause_verification_refused(self):
        for changed, message in (
            (MODEL.replace("verify 'FR-001'", "verify 'FR-999'"), "verification target"),
            (MODEL.replace("verify 'CL-003-01';", ""), "Nonreciprocal"),
            (MODEL.replace("dependency checks from 'CL-003-01' to 'TC-001-001';", ""), "declared verification case"),
            (MODEL.replace("dependency owns from 'CL-003-01' to 'FR-001';", ""), "requirement ownership"),
        ):
            with self.subTest(message=message):
                self.requirements.write_text(changed, encoding="utf-8")
                with self.assertRaisesRegex(ValueError, message):
                    self.check()

    def test_actual_test_binding_is_required_for_delivered_case(self):
        source = self.root / "tests/case.cjs"
        partial = MODEL.replace("AutomationState::planned;", 'AutomationState::partial;\nattribute executable : String = "tests/case.cjs";')
        self.requirements.write_text(partial, encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Missing or out-of-scope"):
            self.check()
        source.write_text("// A comment mentioning TC-001-001 is not an executable binding", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "No Proves tag or named-test"):
            self.check()
        for content in ("// Proves: CL-003-01; TC-001-001\ntest('identity',()=>{});", "test('TC-001-001: identity',()=>{});"):
            source.write_text(content, encoding="utf-8")
            self.check()
        self.requirements.write_text(partial.replace("tests/case.cjs", "../escape.cjs"), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "out-of-scope"):
            self.check()

    def test_explicit_manual_and_rust_symbol_bindings(self):
        source = self.root / "server/probe.rs"
        source.write_text("#[test]\nfn known_observation() {}", encoding="utf-8")
        partial = MODEL.replace("AutomationState::planned;", 'AutomationState::partial;\nattribute executable : String = "server/probe.rs::known_observation";')
        self.requirements.write_text(partial, encoding="utf-8")
        self.check()
        self.requirements.write_text(partial.replace("known_observation", "missing"), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Missing executable test symbol"):
            self.check()
        self.requirements.write_text(partial.replace('server/probe.rs::known_observation', 'server/probe.rs').replace('attribute executable', 'attribute method : String = "manual";\nattribute executable'), encoding="utf-8")
        self.check()

    def test_retired_dependency_and_bad_relative_links_refused(self):
        for extra, message in (("// Canonical FSD slices SHA256: stale", "retired FSD"), ("doc /* FSD12.6 remains authoritative */", "retired FSD"), ("doc /* [tests](../tests/missing.cjs) */", "Dangling model")):
            self.requirements.write_text(MODEL + extra, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, message):
                self.check()

    def test_new_package_requires_scope_reference_and_is_scanned(self):
        extra = self.models / "FutureBackend.sysml"
        extra.write_text("package FutureBackend {}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "lacks a ProductScope reference"):
            self.check()
        (self.models / "ProductScope.sysml").write_text("package Scope { private import FutureBackend::*; }", encoding="utf-8")
        self.check()
        extra.write_text("package FutureBackend { requirement 'FR-001' { attribute coverage : ImplementationState = ImplementationState::target; } }", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Duplicate canonical"):
            self.check()

    # TC-DOC-001: canonical tooling reads the model directly and never rewrites it.
    def test_check_never_reads_archive_and_retired_sync_never_rewrites_model(self):
        archive = self.root / "docs/archive/FSD.md"
        archive.parent.mkdir()
        real_catalog, real_read = tool.canonical_catalog, Path.read_text

        def read(path, *args, **kwargs):
            if "archive" in path.parts:
                raise AssertionError("Canonical tooling attempted to read an archived specification")
            return real_read(path, *args, **kwargs)

        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), mock.patch.object(tool, "FSD", self.fsd), mock.patch.object(tool, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)), mock.patch.object(tool, "validate", return_value=subprocess.CompletedProcess([], 0, "semantic fixture", "")) as validate, mock.patch.object(tool, "architecture_integrity", return_value={"connections": 69}), mock.patch.object(Path, "read_text", read):
            for state in ("missing", "edited"):
                if state == "edited":
                    archive.write_text("Contradictory historical Markdown", encoding="utf-8")
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(tool.main(["check"]), 0)
                self.assertEqual(len(validate.call_args.args[0]), 10)
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as refused:
                tool.main(["sync"])
            self.assertEqual(refused.exception.code, 2)
            self.assertEqual(self.requirements.read_text(encoding="utf-8"), MODEL)
            self.fsd.write_text("Reinstated active Markdown", encoding="utf-8")
            for command in ("check", "fingerprints"):
                with contextlib.redirect_stderr(io.StringIO()) as errors:
                    self.assertEqual(tool.main([command]), 2)
                self.assertIn("Two functional authorities", errors.getvalue())

    def test_fast_traces_refuse_deleted_source_without_invoking_java(self):
        self.requirements.write_text(MODEL.replace("AutomationState::planned;", 'AutomationState::partial;\nattribute executable : String = "tests/case.cjs";'), encoding="utf-8")
        source = self.root / "tests/case.cjs"
        source.write_text("test('TC-001-001: identity',()=>{});", encoding="utf-8")
        real_catalog = tool.canonical_catalog
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), mock.patch.object(tool, "FSD", self.fsd), mock.patch.object(tool, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)), mock.patch.object(tool, "validate", side_effect=AssertionError("Fast traces invoked Java")), mock.patch.object(tool, "tool_paths", side_effect=AssertionError("Fast traces resolved Java")):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(tool.main(["traces"]), 0)
            self.assertIn("no semantic validation or behavior execution", output.getvalue())
            source.unlink()
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(tool.main(["traces"]), 2)
            self.assertIn("Missing or out-of-scope", errors.getvalue())
            source.write_text("// Removed the case identity\ntest('unrelated',()=>{});", encoding="utf-8")
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(tool.main(["traces"]), 2)
            self.assertIn("No Proves tag or named-test identity", errors.getvalue())
            self.requirements.write_text("package Legacy {}", encoding="utf-8")
            self.fsd.write_text("Existing legacy authority", encoding="utf-8")
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(tool.main(["traces"]), 2)
            self.assertIn("Retired Markdown FSD is not a functional authority", errors.getvalue())

    def test_binding_outside_fingerprinted_roots_requires_how_coverage_update(self):
        probe = self.root / "tools/probe.rs"
        probe.parent.mkdir()
        probe.write_text("fn existing_probe() {}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "outside declared source inputs"):
            tool.source_binding("FR-001", "tools/probe.rs", self.root)

    def test_source_proves_requires_defined_numeric_ids_and_expands_aliases(self):
        source = self.root / "tests/proves.cjs"
        source.write_text("// Proves: FR-001; CL-003-01/01; TC-001-001/001; TC-DOC-001; TC-FIXTURE-001", encoding="utf-8")
        self.check()
        source.write_text("// Proves: TC-001-001/002", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "undefined model identities.*TC-001-002"):
            self.check()

    # TC-DOC-007: reference shorthand expands exactly; malformed shorthand is refused.
    def test_full_slash_comma_and_range_references(self):
        self.assertEqual(tool.references("CL-005-02/03,04; FR-008/FR-009; TC-001-001..003"),
                         ["CL-005-02", "CL-005-03", "CL-005-04", "FR-008", "FR-009", "TC-001-001", "TC-001-002", "TC-001-003"])
        for bad in ("CL-005-02/3", "CL-05-02", "TC-001-01", "CL-005-02/03x", "CL-005-02,3", "TC-001-003..001", "CL-005-02..02"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                tool.references(bad)


if __name__ == "__main__":
    unittest.main()
