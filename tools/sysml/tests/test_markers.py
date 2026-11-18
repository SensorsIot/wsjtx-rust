"""TR-20: `markers` lists the WstxModelNotes markers of the model by file key and line.

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

spec = importlib.util.spec_from_file_location("markers_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

NOTES_KEY = "shared/ModelNotes.sysml"
NOTES = '''package WstxModelNotes {
    private import ScalarValues::*;
    doc /* What the model leaves unsaid. metadata def InADoc { } */
    metadata def NotStated { attribute what : String; }
    metadata def Conflict { attribute what : String; }
    metadata def LeftOpen { attribute what : String; }
    metadata def FollowsSource { attribute reference : String; }
    metadata def Debugging { }
    metadata def CodeDiffers { attribute what : String; }
    metadata def DiffersFromSource { attribute what : String; }
}
'''
BINDINGS_KEY = "shared/ModelBindings.sysml"
BINDINGS = '''package WstxModelBindings {
    private import ScalarValues::*;
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    metadata def Status { attribute build : ImplementationState; }
    metadata def ImplementedIn { attribute module : String; }
}
'''
# One fixture line per list entry: the line number of a marker is its index plus one. The
# model lacks the required packages, so the catalog refuses it.
ENTRY = "\n".join([
    "// Canonical authority: SysML",                                                        # 1
    "package WstxRequirements {",                                                           # 2
    "    requirement 'CL-003-01' {",                                                        # 3
    "        @Status { build = ImplementationState::target; }",                             # 4
    '        @NotStated { what = "how the level " +',                                       # 5
    '            "is obtained; by whom"; }',                                                # 6
    "    }",                                                                                # 7
    "    part def Tank {",                                                                  # 8
    '        doc /* @Conflict { what = "in a doc"; }',                                      # 9
    "             @NotStated; */",                                                          # 10
    "        @LeftOpen;",                                                                   # 11
    '        attribute note : String = "@NotStated { what = 1; }";',                        # 12
    "    }",                                                                                # 13
    "    metadata limit : Conflict about Tank, WstxRequirements::Other {",                  # 14
    '        what = "95 here, \\"about 90\\" there";',                                      # 15
    "    }",                                                                                # 16
    "}",                                                                                    # 17
]) + "\n"
ZETA = "\n".join([
    "package WstxZeta {",                                                                   # 1
    "    action def Late {",                                                                # 2
    '        @WstxModelNotes::DiffersFromSource { what = "never on"; } @FollowsSource { reference = "WSJT-X 3.3.0"; }',  # 3
    "    }",                                                                                # 4
    "}",                                                                                    # 5
]) + "\n"
PART_KEY = "backend/qso/Part.sysml"
PART = "\n".join([
    "package WstxQsoPart {",                                                                # 1
    "    action def Run {",                                                                 # 2
    '        @WstxModelNotes::NotStated { what = "the first"; }',                           # 3
    "    }",                                                                                # 4
    "    metadata twoEnds : WstxModelNotes::Conflict about Run,",                           # 5
    "        WstxRequirements::Tank {",                                                     # 6
    '        what = "one says a; " +',                                                      # 7
    '            "the other says b";',                                                      # 8
    "    }",                                                                                # 9
    "    metadata def Local { attribute what : String; }",                                  # 10
    '    @Local { what = "not a kind of WstxModelNotes"; }',                                # 11
    "    part def Store {",                                                                 # 12
    '        @ImplementedIn { module = "server/src/qso/store.rs"; }',                       # 13
    '        @CodeDiffers { what = "the store " + "keeps one file"; }',                     # 14
    "        @Debugging;",                                                                  # 15
    "    }",                                                                                # 16
    "}",                                                                                    # 17
]) + "\n"
# Keys in plain order: an upper-case letter sorts before a lower-case one.
ALL = '''Requirements.sysml:5: NotStated: how the level is obtained; by whom
Requirements.sysml:11: LeftOpen:
Requirements.sysml:14: Conflict about Tank, WstxRequirements::Other: 95 here, "about 90" there
Zeta.sysml:3: DiffersFromSource: never on
Zeta.sysml:3: FollowsSource: WSJT-X 3.3.0
backend/qso/Part.sysml:3: NotStated: the first
backend/qso/Part.sysml:5: Conflict about Run, WstxRequirements::Tank: one says a; the other says b
backend/qso/Part.sysml:14: CodeDiffers: the store keeps one file
backend/qso/Part.sysml:15: Debugging:
9 markers: 1 CodeDiffers, 2 Conflict, 1 Debugging, 1 DiffersFromSource, 1 FollowsSource, 1 LeftOpen, 2 NotStated
'''
NOT_STATED = '''Requirements.sysml:5: NotStated: how the level is obtained; by whom
backend/qso/Part.sysml:3: NotStated: the first
2 markers: 2 NotStated
'''
TWO_KINDS = '''Requirements.sysml:5: NotStated: how the level is obtained; by whom
Requirements.sysml:11: LeftOpen:
backend/qso/Part.sysml:3: NotStated: the first
3 markers: 1 LeftOpen, 2 NotStated
'''
WITH_A_NEW_KIND = '''Extra.sysml:2: Deferred: the antenna; the mast stands
Requirements.sysml:5: NotStated: how the level is obtained; by whom
Requirements.sysml:11: LeftOpen:
Requirements.sysml:14: Conflict about Tank, WstxRequirements::Other: 95 here, "about 90" there
Zeta.sysml:3: DiffersFromSource: never on
Zeta.sysml:3: FollowsSource: WSJT-X 3.3.0
backend/qso/Part.sysml:3: NotStated: the first
backend/qso/Part.sysml:5: Conflict about Run, WstxRequirements::Tank: one says a; the other says b
backend/qso/Part.sysml:14: CodeDiffers: the store keeps one file
backend/qso/Part.sysml:15: Debugging:
10 markers: 1 CodeDiffers, 2 Conflict, 1 Debugging, 1 Deferred, 1 DiffersFromSource, 1 FollowsSource, 1 LeftOpen, 2 NotStated
'''
# A value of three literals joined by `+`, meeting at `; ` and at a space, over two lines.
JOINED_KEY = "backend/antenna/Mast.sysml"
JOINED = "\n".join([
    "package WstxAntennaMastPart {",                                                        # 1
    "    part def Mast {",                                                                  # 2
    '        @NotStated { what = "the height; " + "the guy wires "',                        # 3
    '            + "and their anchors"; }',                                                 # 4
    "    }",                                                                                # 5
    "}",                                                                                    # 6
]) + "\n"
JOINED_LISTING = '''Requirements.sysml:5: NotStated: how the level is obtained; by whom
backend/antenna/Mast.sysml:3: NotStated: the height; the guy wires and their anchors
backend/qso/Part.sysml:3: NotStated: the first
3 markers: 3 NotStated
'''


class MarkerListingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.models = self.root / "docs/sysml"
        for key, text in (("Architecture.sysml", "package WstxArchitecture {}\n"), ("Requirements.sysml", ENTRY),
                          ("Zeta.sysml", ZETA), (PART_KEY, PART), (NOTES_KEY, NOTES), (BINDINGS_KEY, BINDINGS)):
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

    def test_markers_lists_every_marker_by_key_and_line_with_counts_by_kind(self):
        """TV-085 (TR-20): every marker of a WstxModelNotes kind is listed by key and line, then the
        counts by kind; a binding, a doc and a string are not markers."""
        before = self.hashes()
        with self.subTest("the model is one the catalog refuses"), self.assertRaises(ValueError):
            tool.canonical_catalog(self.models, self.root)
        with self.subTest("every kind"):
            self.assertEqual(self.markers(), (0, ALL, ""))
        with self.subTest("one kind"):
            self.assertEqual(self.markers("NotStated"), (0, NOT_STATED, ""))
        with self.subTest("two kinds, counts in name order"):
            self.assertEqual(self.markers("NotStated", "LeftOpen"), (0, TWO_KINDS, ""))
        with self.subTest("nothing written"):
            self.assertEqual(self.hashes(), before)
        with self.subTest("a new kind is listed without a tool change"):
            self.write(NOTES_KEY, NOTES.replace("    metadata def LeftOpen", "    metadata def Deferred { attribute what : String; "
                                                "attribute until : String; }\n    metadata def LeftOpen"))
            self.write("Extra.sysml", 'package WstxExtra {\n    @Deferred { what = "the antenna"; until = "the mast stands"; }\n}\n')
            self.assertEqual(self.markers(), (0, WITH_A_NEW_KIND, ""))
            self.assertEqual(self.markers("Deferred"), (0, "Extra.sysml:2: Deferred: the antenna; the mast stands\n"
                                                           "1 markers: 1 Deferred\n", ""))
        with self.subTest("kinds without a use are counted as none"):
            for key in ("Zeta.sysml", "Extra.sysml", PART_KEY):
                (self.models / key).unlink()
            self.write("Requirements.sysml", "// Canonical authority: SysML\npackage WstxRequirements {}\n")
            self.assertEqual(self.markers(), (0, "0 markers: 0 CodeDiffers, 0 Conflict, 0 Debugging, 0 Deferred, "
                                                 "0 DiffersFromSource, 0 FollowsSource, 0 LeftOpen, 0 NotStated\n", ""))

    def test_markers_lists_a_joined_value_as_one_text(self):
        """TV-086 (TR-20): a marker value of literals joined by `+` is listed as one text."""
        self.write(JOINED_KEY, JOINED)
        self.assertEqual(self.markers("NotStated"), (0, JOINED_LISTING, ""))

    def test_markers_refuses_a_kind_that_is_not_a_wstxmodelnotes_kind(self):
        """TV-087 (TR-20): a kind that no WstxModelNotes `metadata def` declares is refused and nothing is listed."""
        before = self.hashes()
        for unknown in ("Status", "ImplementedIn", "Local", "Deferred", "InADoc", "notstated"):
            with self.subTest(unknown=unknown):
                status, output, errors = self.markers("NotStated", unknown)
                self.assertEqual((status, output), (2, ""))
                self.assertIn("Unknown marker kind: " + unknown + "\n", errors)
        self.assertEqual(self.hashes(), before)

    def test_markers_without_a_wstxmodelnotes_file_lists_none(self):
        """TV-088 (TR-20): without a file of package WstxModelNotes there is no kind and no marker."""
        (self.models / NOTES_KEY).unlink()
        with self.subTest("no WstxModelNotes file"):
            self.assertEqual(self.markers(), (0, "0 markers\n", ""))
        with self.subTest("a file of that name with another package"):
            self.write(NOTES_KEY, NOTES.replace("package WstxModelNotes", "package WstxOtherNotes"))
            self.assertEqual(self.markers(), (0, "0 markers\n", ""))
            status, output, errors = self.markers("NotStated")
            self.assertEqual((status, output), (2, ""))
            self.assertIn("Unknown marker kind: NotStated\n", errors)

    def test_markers_needs_the_authority_marker(self):
        """TV-089 (TR-20): `markers` refuses a model without the authority marker and writes nothing."""
        self.write("Requirements.sysml", ENTRY.split("\n", 1)[1])
        before = self.hashes()
        status, output, errors = self.markers()
        self.assertEqual((status, output), (2, ""))
        self.assertIn("No declared functional authority", errors)
        self.assertEqual(self.hashes(), before)


if __name__ == "__main__":
    unittest.main()
