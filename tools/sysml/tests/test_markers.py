"""TC-DOC-010: `markers` lists the ModelNotes markers of the model by file key and line.

Isolated fixtures in a temporary folder; the expected listings are written by hand, the
line numbers counted in the fixture lines below.
"""
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("markers_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

NOTES_KEY = "shared/ModelNotes.sysml"
NOTES = '''/* Shared metadata: what the model leaves unsaid. metadata def InAComment { } */
package ModelNotes {
    private import ScalarValues::*;
    metadata def NotStated { attribute what : String; }
    metadata def Conflict { attribute what : String; }
    // metadata def AlsoInAComment { attribute what : String; }
    metadata def LeftOpen { attribute what : String; }
    metadata def FollowsSource { attribute reference : String; }
    metadata def DiffersFromSource { attribute what : String; }
}
'''
# One fixture line per list entry: the line number of a marker is its index plus one. The
# clause has no owner and no case and states its status twice, so the catalog refuses the model.
ENTRY = "\n".join([
    "// Canonical authority: SysML",                                                        # 1
    "package PTop {",                                                                       # 2
    "    enum def ImplementationState { enum target; enum partial; enum implemented; }",    # 3
    "    requirement 'CL-003-01' {",                                                        # 4
    "        attribute coverage : ImplementationState = ImplementationState::target;",      # 5
    "        @Status { build = ImplementationState::target; }",                             # 6
    '        @NotStated { what = "how the level " +',                                       # 7
    '            "is obtained; by whom"; }',                                                # 8
    "    }",                                                                                # 9
    "    part def Tank {",                                                                  # 10
    '        // @Conflict { what = "in a line comment"; }',                                 # 11
    '        /* @LeftOpen { what = "in a block comment"; }',                                # 12
    "           @NotStated; */",                                                            # 13
    "        @LeftOpen;",                                                                   # 14
    '        attribute note : String = "@NotStated { what = 1; }";',                        # 15
    "    }",                                                                                # 16
    "    metadata limit : Conflict about Tank, PTop::Other {",                              # 17
    '        what = "95 here, \\"about 90\\" there";',                                      # 18
    "    }",                                                                                # 19
    "}",                                                                                    # 20
]) + "\n"
ZETA = "\n".join([
    "package PZeta {",                                                                      # 1
    "    action def Late {",                                                                # 2
    '        @ModelNotes::DiffersFromSource { what = "never on"; } @FollowsSource { reference = "WSJT-X 3.3.0"; }',  # 3
    "    }",                                                                                # 4
    "}",                                                                                    # 5
]) + "\n"
PART_KEY = "backend/qso/Part.sysml"
PART = "\n".join([
    "package PPart {",                                                                      # 1
    "    action def Run {",                                                                 # 2
    '        @ModelNotes::NotStated { what = "the first"; }',                               # 3
    "    }",                                                                                # 4
    "    metadata twoEnds : ModelNotes::Conflict about Run,",                               # 5
    "        PTop::Tank {",                                                                 # 6
    '        what = "one says a; " +',                                                      # 7
    '            "the other says b";',                                                      # 8
    "    }",                                                                                # 9
    "    metadata def Local { attribute what : String; }",                                  # 10
    '    @Local { what = "not a kind of ModelNotes"; }',                                    # 11
    "}",                                                                                    # 12
]) + "\n"
# Keys in plain order: an upper-case letter sorts before a lower-case one.
ALL = '''Requirements.sysml:7: NotStated: how the level is obtained; by whom
Requirements.sysml:14: LeftOpen:
Requirements.sysml:17: Conflict about Tank, PTop::Other: 95 here, "about 90" there
Zeta.sysml:3: DiffersFromSource: never on
Zeta.sysml:3: FollowsSource: WSJT-X 3.3.0
backend/qso/Part.sysml:3: NotStated: the first
backend/qso/Part.sysml:5: Conflict about Run, PTop::Tank: one says a; the other says b
7 markers: 2 Conflict, 1 DiffersFromSource, 1 FollowsSource, 1 LeftOpen, 2 NotStated
'''
NOT_STATED = '''Requirements.sysml:7: NotStated: how the level is obtained; by whom
backend/qso/Part.sysml:3: NotStated: the first
2 markers: 2 NotStated
'''
TWO_KINDS = '''Requirements.sysml:7: NotStated: how the level is obtained; by whom
Requirements.sysml:14: LeftOpen:
backend/qso/Part.sysml:3: NotStated: the first
3 markers: 1 LeftOpen, 2 NotStated
'''
WITH_A_SIXTH_KIND = '''Extra.sysml:2: Deferred: until the antenna is chosen; issue 9
''' + ALL.replace("7 markers: 2 Conflict, 1 DiffersFromSource", "8 markers: 2 Conflict, 1 Deferred, 1 DiffersFromSource")


class MarkerListingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.models = self.root / "docs/sysml"
        # The file of the other required package, written by hand; the entry file follows below.
        self.write("Architecture.sysml", "package WstxArchitecture {}\n")
        for key, text in (("Requirements.sysml", ENTRY), ("Zeta.sysml", ZETA), (PART_KEY, PART), (NOTES_KEY, NOTES)):
            self.write(key, text)

    def write(self, key, text):
        path = self.models / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="")

    def hashes(self):
        return {path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(self.root.rglob("*")) if path.is_file()}

    def markers(self, *kinds):
        """Run `markers` on the fixture, with the catalog and the validator forbidden;
        returns (exit code, stdout, stderr)."""
        output, errors = io.StringIO(), io.StringIO()
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), \
                mock.patch.object(tool, "FSD", self.root / "docs/FSD.md"), \
                mock.patch.object(tool, "canonical_catalog", side_effect=AssertionError("catalog checked")), \
                mock.patch.object(tool, "validate", side_effect=AssertionError("validator invoked")), \
                mock.patch.object(tool.subprocess, "run", side_effect=AssertionError("process started")), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["markers", *kinds])
        return status, output.getvalue(), errors.getvalue()

    # T11
    # Proves: CL-014-12; TC-DOC-010
    def test_markers_lists_every_marker_by_key_and_line_with_counts_by_kind(self):
        before = self.hashes()
        with self.subTest("the model is one the catalog refuses"), self.assertRaises(ValueError):
            tool.canonical_catalog(self.models, self.root)
        with self.subTest("every kind"):
            self.assertEqual(self.markers(), (0, ALL, ""))
        with self.subTest("one kind"):
            self.assertEqual(self.markers("NotStated"), (0, NOT_STATED, ""))
        with self.subTest("two kinds, counts in name order"):
            self.assertEqual(self.markers("NotStated", "LeftOpen"), (0, TWO_KINDS, ""))
        for unknown in ("Status", "Local", "Deferred", "InAComment", "AlsoInAComment", "notstated"):
            with self.subTest(unknown=unknown):
                status, output, errors = self.markers("NotStated", unknown)
                self.assertEqual((status, output), (2, ""))
                self.assertIn("Unknown marker kind: " + unknown + "\n", errors)
        with self.subTest("nothing written"):
            self.assertEqual(self.hashes(), before)
        with self.subTest("a sixth kind is listed without a tool change"):
            self.write(NOTES_KEY, NOTES.replace("    metadata def LeftOpen", "    metadata def Deferred { attribute what : String; "
                                                "attribute until : String; }\n    metadata def LeftOpen"))
            self.write("Extra.sysml", 'package PExtra {\n    @Deferred { what = "until the antenna is chosen"; until = "issue 9"; }\n}\n')
            self.assertEqual(self.markers(), (0, WITH_A_SIXTH_KIND, ""))
            self.assertEqual(self.markers("Deferred"), (0, "Extra.sysml:2: Deferred: until the antenna is chosen; issue 9\n1 markers: 1 Deferred\n", ""))
        with self.subTest("kinds without a use are counted as none"):
            for key in ("Zeta.sysml", "Extra.sysml", PART_KEY):
                (self.models / key).unlink()
            self.write("Requirements.sysml", "// Canonical authority: SysML\npackage PTop {}\n")
            self.assertEqual(self.markers(), (0, "0 markers: 0 Conflict, 0 Deferred, 0 DiffersFromSource, 0 FollowsSource, "
                                                 "0 LeftOpen, 0 NotStated\n", ""))

    # T11
    # Proves: CL-014-12; TC-DOC-010
    def test_markers_without_a_modelnotes_file_lists_none_and_needs_the_authority(self):
        (self.models / NOTES_KEY).unlink()
        with self.subTest("no ModelNotes file"):
            self.assertEqual(self.markers(), (0, "0 markers\n", ""))
        with self.subTest("a file of that name with another package"):
            self.write("ModelNotes.sysml", NOTES.replace("package ModelNotes", "package OtherNotes"))
            self.assertEqual(self.markers(), (0, "0 markers\n", ""))
            status, output, errors = self.markers("NotStated")
            self.assertEqual((status, output), (2, ""))
            self.assertIn("Unknown marker kind: NotStated\n", errors)
        with self.subTest("no authority marker"):
            self.write(NOTES_KEY, NOTES)
            self.write("Requirements.sysml", ENTRY.split("\n", 1)[1])
            before = self.hashes()
            status, output, errors = self.markers()
            self.assertEqual((status, output), (2, ""))
            self.assertIn("No declared functional authority", errors)
            self.assertEqual(self.hashes(), before)


if __name__ == "__main__":
    unittest.main()
