"""TR-04: the layers M3.1 to M3.4 on every model file, and `WstxContext` named only by
Context and UseCases.

The accepted fixture imports from earlier layers, UseCases takes its actors from Context and
QsoControl imports a type of TransmitControl. Each negative case adds one line as line 2 of
one file and expects exactly its one fault line, written by hand.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("layer_rule_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

ACCEPTED = {
    "Requirements.sysml": """package WstxRequirements {
    private import WstxUnits::*;
    requirement 'FR-001' {
        doc /* Time
             Keep the station time. */
    }
}
""",
    "shared/Units.sysml": """package WstxUnits {
    attribute def Hz;
}
""",
    "interfaces/internal/StationLink.sysml": """package WstxStationLink {
    private import WstxUnits::*;
    private import WstxQsoControl::QsoCommand;
    attribute def WireNames {
        doc /* The function of a feature is the part whose control interface defines it:
             qso for WstxQsoControl, transmit for WstxTransmitControl. */
    }
}
""",
    "interfaces/internal/QsoControl.sysml": """package WstxQsoControl {
    private import WstxUnits::*;
    private import WstxTransmitControl::TxPower;
    item def QsoCommand {
        attribute power : TxPower;
    }
}
""",
    "interfaces/internal/TransmitControl.sysml": """package WstxTransmitControl {
    attribute def TxPower;
}
""",
    "interfaces/internal/OperatingChain.sysml": """package WstxOperatingChain {
    private import WstxQsoControl::QsoCommand;
    item def RankedActivity;
}
""",
    "interfaces/external/Mcp.sysml": """package WstxMcp {
    private import WstxStationLink::WireNames;
    port def McpPort;
}
""",
    "interfaces/external/Cat.sysml": """package WstxCat {
    private import WstxUnits::Hz;
    port def CatPort;
}
""",
    "backend/clock/Clock.sysml": """package WstxClockPart {
    private import WstxUnits::*;
    private import WstxTransmitControl::TxPower;
    private import WstxRequirements::*;
    part def ClockService;
}
""",
    "backend/clock/StationClock.sysml": """package WstxStationClock {
    private import WstxClockPart::ClockService;
    attribute def Tick;
}
""",
    "backend/transmit/Transmit.sysml": """package WstxTransmitPart {
    part def TransmitService;
}
""",
    "Shack.sysml": """package WstxShack {
    private import WstxRequirements::*;
    private import WstxClockPart::ClockService;
    private import WstxTransmitPart::TransmitService;
    private import WstxQsoControl::QsoCommand;
    part def Shack {
        part clock : ClockService;
        part transmit : TransmitService;
    }
}
""",
    "Context.sysml": """package WstxContext {
    private import WstxShack::Shack;
    private import WstxCat::CatPort;
    part def ShackContext {
        part shack : Shack;
        part operator;
        part catRadio { port cat : CatPort; }
    }
    part context : ShackContext;
}
""",
    "UseCases.sysml": """package WstxUseCases {
    private import WstxShack::Shack;
    private import WstxContext::context;
    use case def KeepTime {
        subject shack : Shack;
        actor operator :> context.operator;
        actor radio :> WstxContext::context.catRadio;
    }
}
""",
}

# Each way to break the layers: (file, line added as line 2, the fault written by hand).
NEGATIVES = (
    ("a part importing another part", "backend/clock/Clock.sysml", "private import WstxTransmitPart::*;",
     "part names WstxTransmitPart of another part: backend/clock/Clock.sysml:2"),
    ("a part importing Shack", "backend/clock/Clock.sysml", "private import WstxShack::Shack;",
     "names WstxShack of a later layer: backend/clock/Clock.sysml:2"),
    ("an interface importing a part", "interfaces/internal/TransmitControl.sysml",
     "private import WstxClockPart::ClockService;",
     "names WstxClockPart of a later layer: interfaces/internal/TransmitControl.sysml:2"),
    ("Shack importing Context", "Shack.sysml", "private import WstxContext::*;",
     "names the context package WstxContext: Shack.sysml:2"),
    ("an external interface importing a control interface", "interfaces/external/Cat.sysml",
     "private import WstxQsoControl::QsoCommand;",
     "external interface names the control interface WstxQsoControl: interfaces/external/Cat.sysml:2"),
    ("a control interface importing StationLink", "interfaces/internal/TransmitControl.sysml",
     "private import WstxStationLink::*;",
     "control interface names WstxStationLink: interfaces/internal/TransmitControl.sysml:2"),
    ("a control interface importing Mcp", "interfaces/internal/TransmitControl.sysml",
     "private import WstxMcp::McpPort;",
     "control interface names WstxMcp: interfaces/internal/TransmitControl.sysml:2"),
    ("a control interface importing OperatingChain", "interfaces/internal/QsoControl.sysml",
     "private import WstxOperatingChain::RankedActivity;",
     "control interface names WstxOperatingChain: interfaces/internal/QsoControl.sysml:2"),
    ("Requirements importing a part", "Requirements.sysml", "private import WstxClockPart::*;",
     "Requirements names WstxClockPart: Requirements.sysml:2"),
    ("another file naming WstxContext", "backend/transmit/Transmit.sysml",
     "part outside : WstxContext::ShackContext;",
     "names the context package WstxContext: backend/transmit/Transmit.sysml:2"),
)


def layer_lines(files: dict[str, str]) -> list[str]:
    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        for key, text in files.items():
            path = folder / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        return tool.fault_lines(tool.layer_faults(tool.Model(folder)))


class LayerTest(unittest.TestCase):
    def test_accepted(self):
        """TV-081 (TR-04): imports from earlier layers, UseCases naming Context's actors and QsoControl
        importing a type of TransmitControl are accepted."""
        self.assertEqual(layer_lines(ACCEPTED), [])

    def test_control_interfaces(self):
        """TV-082 (TR-04): the control interfaces are the packages `WstxStationLink::WireNames` lists."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for key, text in ACCEPTED.items():
                (folder / key).parent.mkdir(parents=True, exist_ok=True)
                (folder / key).write_text(text, encoding="utf-8")
            self.assertEqual(tool.control_packages(tool.Model(folder)), {"WstxQsoControl", "WstxTransmitControl"})

    def test_negatives(self):
        """TV-083 (TR-04): each way to break the layers is refused with its one fault line."""
        for way, key, added, expected in NEGATIVES:
            with self.subTest(way):
                files = dict(ACCEPTED)
                first, rest = files[key].split("\n", 1)
                files[key] = f"{first}\n    {added}\n{rest}"
                self.assertEqual(layer_lines(files), [expected])

    def test_real_model_layers(self):
        """TV-084 (TR-04): the real model `docs/sysml` keeps its layers."""
        self.assertEqual(tool.fault_lines(tool.layer_faults(tool.Model(ROOT / "docs/sysml"))), [])


if __name__ == "__main__":
    unittest.main()
