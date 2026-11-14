"""CL-014-06: a reference's target in the resolved inventory is the deployment path of the
subsetted feature, whether the model writes it from the root (the absolute form) or from
the enclosing usage that holds it (the nested form); a redefinition is no target.

Two small models, one in each form, are validated by the real pinned Pilot; their REF rows
must be equal and rooted at the deployment root.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("reference_target_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"

HEAD = '''package WstxFixture {
    part def Client;
    part def Authority;
    part def Frontend { part browsers[*] : Client; }
    part def Backend {
        part radioAuthority : Authority;
        %(stations)s
    }
    part def Process { ref part authority : Authority%(authority)s; }
    part def Attachment { ref part browser : Client%(browser)s; }
    part def Station {
        part frontend : Frontend;
        part backend : Backend;
        part attachments[*] : Attachment%(attachments)s
    }
    part def Context { part station : Station; }
    part context : Context;
}
'''
ABSOLUTE = HEAD % {
    "stations": "part stations[*] : Process;",
    "authority": " :> context.station.backend.radioAuthority",
    "browser": " :> context.station.frontend.browsers",
    "attachments": ";",
}
NESTED = HEAD % {
    "stations": "part stations[*] : Process { ref part :>> authority : Authority :> radioAuthority; }",
    "authority": "",
    "browser": "",
    "attachments": " { ref part :>> browser : Client :> frontend.browsers; }",
}


def references(text):
    """The REF rows of the model `text` in the resolved inventory, by path."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "Fixture.sysml"
        path.write_text(text, encoding="utf-8")
        result = tool.validate([path], CACHE, inventory=True)
    assert result.returncode == 0, result.stdout[-3000:] + result.stderr[-3000:]
    return {row[0]: row[1:] for row in tool.inventory_records(result.stdout).get("REF", [])}


class ReferenceTargetTests(unittest.TestCase):
    # Proves: CL-014-06
    def test_nested_and_absolute_forms_give_equal_reference_rows(self):
        absolute, nested = references(ABSOLUTE), references(NESTED)
        self.assertEqual(sorted(absolute), ["context.station.attachments.browser",
                                            "context.station.backend.stations.authority"])
        self.assertEqual(absolute["context.station.attachments.browser"][3], "context.station.frontend.browsers")
        self.assertEqual(absolute["context.station.backend.stations.authority"][3],
                         "context.station.backend.radioAuthority")
        self.assertEqual(nested, absolute)


if __name__ == "__main__":
    unittest.main()
