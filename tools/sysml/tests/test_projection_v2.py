"""Projection-v2 mutations: declared metadata, traceability and slice freshness."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("projection_v2_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

SOURCE = """<!-- sysml-projection: 2 -->
## 1. Contract
| FR-001 | Setup | Preserve identity. |
| CL-005-02 | FR-001 | Save identity. | TC-001-001 |
| CL-005-03 | FR-001 | Keep independent identity. | TC-001-001 |
### 1.1 Details
The authoritative numerical limit is 42.
## 2. Verification
#### TC-001-001 — Identity
**Clauses:** CL-005-02/03. **Promise:** FR-001.
Observe independently prepared identities.
## 3. Projection metadata
| Model identity | Declared state |
|---|---|
| `FR-001` | partial |
| `CL-005-02` | implemented |
| `CL-005-03` | target |
| `TC-001-001` | partial |

| Manual companion | FSD sections |
|---|---|
| `RecordingReceive.sysml` | 1, 2 |
"""


class ProjectionV2Tests(unittest.TestCase):
    def test_states_are_declared_not_inferred_from_identity(self):
        output = tool.render(SOURCE)
        self.assertIn("ImplementationState::partial", output)
        self.assertIn("AutomationState::partial", output)
        changed = tool.render(SOURCE.replace("`CL-005-03` | target", "`CL-005-03` | partial"))
        self.assertNotEqual(output, changed)
        self.assertIn("verify 'CL-005-03';", output)

    def test_missing_duplicate_unknown_and_invalid_metadata_fail(self):
        for changed in (
            SOURCE.replace("| `FR-001` | partial |\n", ""),
            SOURCE.replace("| `FR-001` | partial |", "| `FR-001` | partial |\n| `FR-001` | target |"),
            SOURCE.replace("`FR-001` | partial", "`FR-999` | partial"),
            SOURCE.replace("`FR-001` | partial", "`FR-001` | passed"),
            SOURCE.replace("`TC-001-001` | partial", "`TC-001-001` | target"),
            SOURCE.replace("<!-- sysml-projection: 2 -->", "<!-- sysml-projection: 3 -->"),
        ):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                tool.render(changed)

    def test_full_slash_comma_and_range_references(self):
        self.assertEqual(tool.references("CL-005-02/03,04; FR-008/FR-009; TC-001-001..003"),
                         ["CL-005-02", "CL-005-03", "CL-005-04", "FR-008", "FR-009", "TC-001-001", "TC-001-002", "TC-001-003"])
        for bad in ("CL-005-02/3", "CL-05-02", "TC-001-01", "CL-005-02/03x", "CL-005-02,3", "TC-001-003..001", "CL-005-02..02"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                tool.references(bad)

    def test_lost_shorthand_unknown_and_nonreciprocal_relations_fail(self):
        for changed in (
            SOURCE.replace("CL-005-02/03.", "CL-005-02/99."),
            SOURCE.replace("identity. | TC-001-001", "identity. | TC-001-999", 1),
            SOURCE.replace("CL-005-02/03.", "CL-005-02."),
            SOURCE.replace("independent identity. | TC-001-001", "independent identity. | source review"),
        ):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                tool.catalog(changed)

    def test_incidental_backticked_reference_table_is_not_metadata(self):
        source = SOURCE + "\n| Stable case | Executable |\n|---|---|\n| `TC-001-001` | fixture.rs |\n"
        self.assertEqual(set(tool.catalog(source)), set(tool.catalog(SOURCE)))

    def test_fingerprint_tracks_selected_subtrees_only(self):
        expected = tool.section_digest(SOURCE, ["1", "2"])
        self.assertEqual(expected, tool.section_digest(SOURCE + "\nUnrelated metadata text.", ["1", "2"]))
        self.assertNotEqual(expected, tool.section_digest(SOURCE.replace("42", "43"), ["1", "2"]))
        self.assertEqual(expected, tool.section_digest(SOURCE, ["2", "1"]))
        for sections in (["1", "1.1"], ["1", "1"], ["99"]):
            with self.subTest(sections=sections), self.assertRaises(ValueError):
                tool.section_digest(SOURCE, sections)
        with self.assertRaisesRegex(ValueError, "Duplicate numbered"):
            tool.section_digest(SOURCE + "\n## 1. Duplicate\n", ["1"])

    def test_recording_and_every_actual_companion_require_exact_slice_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fingerprint = tool.companion_fingerprints(SOURCE)["RecordingReceive.sysml"]
            model = root / "RecordingReceive.sysml"
            model.write_text("// Canonical FSD slices SHA256: " + fingerprint + "\npackage Recording {}", encoding="utf-8")
            tool.check_companions(SOURCE, root)
            with self.assertRaisesRegex(ValueError, "source slices changed"):
                tool.check_companions(SOURCE.replace("42", "43"), root)
            (root / "Profiles.sysml").write_text("package Profiles {}", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "declaration/file mismatch"):
                tool.check_companions(SOURCE, root)
            (root / "Profiles.sysml").unlink()
            model.write_text("package Recording {}", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "source slices changed"):
                tool.check_companions(SOURCE, root)

    def test_actual_pilot_accepts_declared_partial_projection(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "Requirements.sysml"
            model.write_text(tool.render(SOURCE), encoding="utf-8")
            result = tool.validate([model], Path.home() / ".cache/wsjtx-rust/sysml-tools")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_legacy_projection_remains_byte_identical(self):
        # Frozen pre-change output digest from d8b3eb19b's renderer.
        source = ("| FR-001 | Setup | Retain the station identity. |\n"
                  "| CL-003-01 | FR-001 | Display its identity. | TC-001-001 |\n"
                  "#### TC-001-001 - Identity\n**Promise:** FR-001.\n"
                  "Send a status query and expect its own identity.\n")
        self.assertFalse(tool.projection_v2(source))
        self.assertEqual(tool.digest(tool.render(source)), "5d0dee88d304d7232a6e48243017a3e1022b0e28f56cf4c69a819588e8d23996")



if __name__ == "__main__":
    unittest.main()
