"""TR-23: M5.11, the status of a boundary port.

A guard reads the availability of a status, never its reason (limit 1); `status` is out on a
port definition that specializes ExternalPort and nothing else redefines it (limit 4). Each
case writes one tiny model file and compares the fault lines.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("boundary_rule_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

PATTERN = """package WstxExternalPort {
    enum def Availability { enum notUsable; enum usable; }
    abstract item def InterfaceStatus { attribute availability : Availability; }
    abstract port def ExternalPort { out item status : InterfaceStatus; }
}
"""
RADIO = """package WstxRadio {
    private import WstxExternalPort::*;
    item def RadioStatus :> InterfaceStatus { attribute reason : String[0..1]; }
    port def RadioPort :> ExternalPort { %s }
    part def Consumer {
        state watch {
            entry; then off;
            state off;
            state on;
            transition seen first off accept s : RadioStatus if %s then on;
        }
        %s
    }
}
"""


class BoundaryTest(unittest.TestCase):
    def faults(self, port="out item :>> status : RadioStatus;", guard="s.availability == Availability::usable",
               extra=""):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "ExternalPort.sysml").write_text(PATTERN, encoding="utf-8")
            (folder / "Radio.sysml").write_text(RADIO % (port, guard, extra), encoding="utf-8")
            return tool.fault_lines(tool.boundary_faults(tool.Model(folder)))

    def test_a_guard_on_availability_and_an_out_status_pass(self):
        self.assertEqual(self.faults(), [])

    def test_a_guard_that_reads_the_reason_is_refused(self):
        self.assertEqual(len(self.faults(guard="s.reason == null")), 1)
        self.assertIn("transition guard reads reason of a status", self.faults(guard="s.reason == null")[0])

    def test_an_in_status_on_the_hosting_port_is_refused(self):
        found = self.faults(port="in item :>> status : RadioStatus;")
        self.assertEqual(len(found), 1)
        self.assertIn("status of RadioPort is not out", found[0])

    def test_a_status_redefined_outside_the_port_is_refused(self):
        found = self.faults(extra="item :>> status : RadioStatus;")
        self.assertEqual(len(found), 1)
        self.assertIn("status redefined outside an ExternalPort port definition", found[0])

    def test_the_real_model_passes(self):
        self.assertEqual(tool.fault_lines(tool.boundary_faults(
            tool.Model(Path(__file__).resolve().parents[3] / "docs/sysml"))), [])


if __name__ == "__main__":
    unittest.main()
