"""TR-05: what Requirements, Shack, UseCases and Context hold (M4.1 to M4.3, M4.9).

The accepted fixture holds the four files in their forms. Each negative case changes one
text of one file once and expects exactly its one fault line, written by hand.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("content_rule_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

ACCEPTED = {
    "Requirements.sysml": """// Canonical authority: SysML
package WstxRequirements {
    private import ScalarValues::*;
    attribute def BehaviorBaseline {
        doc /* The WSJT-X release the decoder is compared with. */
        attribute release : String = "v3.3.0-beta6";
    }
    requirement 'FR-001' {
        doc /* Station time
             Keep the station time. */
    }
}
""",
    "Shack.sysml": """package WstxShack {
    private import WstxRequirements::*;
    private import WstxClockPart::ClockService;
    part def Shack {
        part stations[*] : Station;
    }
    part def Station {
        part clock : ClockService;
        satisfy 'FR-001' by clock;
    }
}
""",
    "Context.sysml": """package WstxContext {
    private import WstxShack::Shack;
    part def ShackContext {
        part shack : Shack;
        part operator;
    }
    part context : ShackContext;
}
""",
    "UseCases.sysml": """package WstxUseCases {
    private import WstxShack::Shack;
    private import WstxContext::context;
    use case def KeepTime {
        doc /* The operator reads the station time. */
        subject shack : Shack;
        actor operator :> context.operator;
        objective {
            doc /* The station time is shown. */ }
        action readTime {
            doc /* The operator reads the time on the screen. */
            requirement :> WstxStationClock::'CL-001-01';
        }
    }
}
""",
}

# Each way to break the contents: (way, file, text replaced, replacement, the fault).
NEGATIVES = (
    ("an FR with a subject", "Requirements.sysml", "Keep the station time. */",
     "Keep the station time. */\n        subject station;",
     "FR-001 holds subject station: Requirements.sysml:11"),
    ("an FR with @Status", "Requirements.sysml", "Keep the station time. */",
     "Keep the station time. */\n        @Status { state = ImplementationState::target; }",
     "FR-001 holds @ Status: Requirements.sysml:11"),
    ("an FR with @ImplementedIn", "Requirements.sysml", "Keep the station time. */",
     'Keep the station time. */\n        @ImplementedIn { module = "server/src/clock/mod.rs"; }',
     "FR-001 holds @ ImplementedIn: Requirements.sysml:11"),
    ("an FR naming an issue", "Requirements.sysml", "Keep the station time. */",
     "Keep the station time, see #" + "40. */", "FR-001 names an issue: Requirements.sysml:8"),
    ("Shack with a clause", "Shack.sysml", "        satisfy 'FR-001' by clock;\n",
     "        satisfy 'FR-001' by clock;\n        requirement 'CL-001-01' {\n"
     "            doc /* The ClockService MUST keep the time. */ }\n",
     "Shack holds requirement 'CL-001-01': Shack.sysml:10"),
    ("Shack with an attribute", "Shack.sysml", "        part stations[*] : Station;\n",
     "        part stations[*] : Station;\n        attribute stationLimit = 6;\n",
     "Shack holds attribute stationLimit: Shack.sysml:6"),
    ("Shack with a satisfy of a clause", "Shack.sysml", "        satisfy 'FR-001' by clock;\n",
     "        satisfy 'FR-001' by clock;\n        satisfy WstxStationClock::'CL-001-01' by clock;\n",
     "satisfy of no FR: Shack.sysml:10"),
    ("UseCases with a value", "UseCases.sysml", "subject shack : Shack;",
     "subject shack : Shack = context.shack;", "UseCases holds a value: UseCases.sysml:6"),
    ("a step naming a clause in text only", "UseCases.sysml", "reads the time on the screen.",
     "reads the time on the screen (CL-001-02).", "a step names a clause in its text: UseCases.sysml:10"),
)


def content_lines(files: dict[str, str]) -> list[str]:
    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        for key, text in files.items():
            path = folder / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        return tool.fault_lines(tool.content_faults(tool.Model(folder)))


class FileContentsTest(unittest.TestCase):
    def test_accepted(self):
        """TV-071 (TR-05): Requirements, Shack, Context and UseCases in the forms of M4.1 to M4.3 and M4.9
        are accepted."""
        self.assertEqual(content_lines(ACCEPTED), [])

    def test_negatives(self):
        """TV-072 (TR-05): each way to break what a file holds is refused with its one fault line."""
        for way, key, old, new, expected in NEGATIVES:
            with self.subTest(way):
                files = dict(ACCEPTED)
                self.assertEqual(files[key].count(old), 1)
                files[key] = files[key].replace(old, new)
                self.assertEqual(content_lines(files), [expected])

    def test_real_model_contents(self):
        """TV-073 (TR-05): the real model `docs/sysml` holds in each file what M4 allows."""
        self.assertEqual(tool.fault_lines(tool.content_faults(tool.Model(ROOT / "docs/sysml"))), [])


if __name__ == "__main__":
    unittest.main()
