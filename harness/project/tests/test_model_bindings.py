"""harness/project/model_bindings.py: what the harness gates read of a requirement and a case.

A requirement's digest is what it promises (its build metadata left out), its satisfier the part
its subject names (an FR's, the part of its Shack satisfy); a case is left to Accept only on real
equipment. Fixture model files in a temporary folder; no git, no station.
"""
import importlib.util
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("model_bindings", ROOT / "harness" / "project" / "model_bindings.py")
mb = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mb)

CLAUSE = """\
package WstxPort {{
    part def PortService;
    requirement 'CL-901-01' {{
        doc /* The port MUST be chosen by the operator. */
        subject service : PortService;
        {build}
    }}
}}
"""
SHACK = """\
package WstxShack {
    part def Station {
        part ports : PortService;
        satisfy 'FR-901' by ports;
    }
}
"""


class ModelBindingsTest(unittest.TestCase):
    def model(self, clause_build="", text=None, shack=True):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        body = text or CLAUSE.format(build=clause_build)
        (root / "Port.sysml").write_text(textwrap.dedent(body), encoding="utf-8")
        if shack:
            (root / "Shack.sysml").write_text(SHACK, encoding="utf-8")
        return root

    def test_the_build_metadata_leaves_the_digest_unchanged(self):
        target = mb.digests(self.model("@Status { build = ImplementationState::target; }"))["CL-901-01"]
        built = mb.digests(self.model('@Status { build = ImplementationState::implemented; } '
                                      '@ImplementedIn { module = "server/src/port.rs"; }'))["CL-901-01"]
        self.assertEqual(target, built)

    def test_a_changed_promise_changes_the_digest(self):
        before = mb.digests(self.model())["CL-901-01"]
        after = mb.digests(self.model(text=CLAUSE.format(build="").replace("MUST be chosen", "MUST be fixed")))
        self.assertNotEqual(before, after["CL-901-01"])

    def test_a_changed_subject_changes_the_digest(self):
        before = mb.digests(self.model())["CL-901-01"]
        after = mb.digests(self.model(text=CLAUSE.format(build="").replace("service : PortService", "s : Other")))
        self.assertNotEqual(before, after["CL-901-01"])

    def test_white_space_and_comments_leave_the_digest_unchanged(self):
        before = mb.digests(self.model())["CL-901-01"]
        after = mb.digests(self.model(text=CLAUSE.format(build="// a note").replace("    doc", "\n        doc")))
        self.assertEqual(before, after["CL-901-01"])

    def test_a_clause_is_satisfied_by_its_subjects_part_and_an_fr_by_its_shack_part(self):
        self.assertEqual(mb.satisfiers(self.model()), {"CL-901-01": "PortService", "FR-901": "ports"})

    def test_a_clause_without_a_subject_has_no_satisfier(self):
        text = CLAUSE.format(build="").replace("        subject service : PortService;\n", "")
        self.assertEqual(mb.satisfiers(self.model(text=text, shack=False)), {})

    def test_only_real_equipment_leaves_a_case_to_accept(self):
        self.assertTrue(mb.left_to_accept([(3, "station")]))
        self.assertTrue(mb.left_to_accept([(1, "developmentPc"), (4, "flexRadio")]))
        self.assertFalse(mb.left_to_accept([(2, "simulator")]))
        self.assertFalse(mb.left_to_accept([(1, "developmentPc")]))
        self.assertFalse(mb.left_to_accept([]))


if __name__ == "__main__":
    unittest.main()
