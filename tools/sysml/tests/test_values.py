"""TR-16: model values, names and variables against the code (M6.8, M6.13), on a temporary
root with model and code files.

The accepted fixture covers each value one way: V3 (only target clauses reach it), V4 (its
`@CodeDiffers`, the code differing), V1 (its constant `D::F`, `d::F` or module `F`, a
JavaScript `D.F`; a literal, wire name, command field or variable found) or V2 (a test
bound to a case of a clause reaching it holds its qualified name). Each negative test
breaks the fixture once. Expected lines are written by hand: message, file key and line.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("values_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CLOCK = "docs/sysml/backend/clock/StationClock.sysml"
AIR = "server/src/clock/air.rs"
CHECK = "server/src/clock/check.rs"
SHARED = "server/src/shared/clock_values.rs"
AIR_CLOCK = """pub struct AirClock {
    votes: Vec<i64>,
}

impl AirClock {
    pub const MAX_AGE_SECONDS: u64 = 60;
    pub const WINDOW_SECONDS: u64 = 2 * 60;
}
"""
WARNING_RULE = """pub mod warning_rule {
    pub const MAX_OFFSET_MS: i64 = 400;
}
"""
FILES = {
    "docs/sysml/backend/clock/Clock.sysml": """package WstxClockPart {
    part def ClockService {
        @ImplementedIn {
            module = "server/src/clock/air.rs; server/src/clock/check.rs; client/src/clock/clock.js";
        }
    }
}
""",
    CLOCK: """package WstxStationClock {
    private import ScalarValues::*;
    private import WstxClockPart::ClockService;

    requirement 'CL-043-01' {
        subject clock : ClockService;
        doc /* The clock MUST hold station time as the PC clock plus its correction (TimeBase). */
        @Status { build = ImplementationState::implemented; }
    }

    attribute def TimeBase {
        attribute startCorrectionMs : Integer = 0;
    }

    requirement 'CL-043-02' {
        subject clock : ClockService;
        doc /* The clock MUST restart its correction after a step of the PC clock (StepRule). */
        @Status { build = ImplementationState::implemented; }
    }

    attribute def StepRule {
        attribute restartMs : Integer = 3000;
    }

    attribute def AirClock {
        attribute maxAgeSeconds : Integer = 60;
        attribute windowSeconds : Integer = 120;
    }

    attribute def Correction {
        attribute maxAgeSeconds : Integer = 90;
        attribute slewRate : Real = 200.0;
        attribute gain : Real = 0.33;
        attribute holdSeconds : Integer = 2;
        attribute maxStepMs : Integer = 50 * 2;
    }

    attribute def TimeServerCheck {
        doc /* The environment variable WSTX_SNTP_SERVERS gives another list of servers. */
        attribute maxOffsetMs : Integer = 500;
    }

    attribute def WarningRule {
        attribute maxOffsetMs : Integer = 400;
    }

    attribute def ClockDisplay {
        attribute refreshMs : Integer = 250;
    }

    attribute def Limits {
        attribute alcLimit : Real = 0.5 {
            @CodeDiffers { what = "The code holds 0.6."; }
        }
    }

    attribute def Drift {
        attribute limitMs : Integer = 7;
    }
}
""",
    "docs/sysml/interfaces/internal/StationTime.sysml": """package WstxStationTime {
    requirement 'CL-044-01' {
        doc /* The station time MUST stay within WstxStationClock::Drift. */
        @Status { build = ImplementationState::target; }
    }
}
""",
    "docs/sysml/interfaces/internal/StationLink.sysml": """package WstxStationLink {
    private import ScalarValues::*;

    attribute def WireNames {
        doc /* The control interfaces: WstxTransmitControl. */
    }

    item def Heartbeat {
        attribute 'type' : String = "heartbeat";
        attribute sentAt : Integer;
    }
}
""",
    "docs/sysml/interfaces/internal/TransmitControl.sysml": """package WstxTransmitControl {
    private import ScalarValues::*;

    item def HoldTx {
        attribute holdSlot : Boolean = false;
    }
}
""",
    AIR: """use std::time::Duration;

""" + AIR_CLOCK + """
pub enum Correction {
    Hold,
    Move(i64),
}

impl Correction {
    pub const MAX_AGE_SECONDS: u64 = 90;
    pub const SLEW_RATE: f64 = 200.;
    pub const GAIN: f64 = 1.0 / 3.0;
    pub const HOLD_SECONDS: Duration = Duration::from_millis(2_000);
    pub const MAX_STEP_MS: i64 = 100;
}

pub mod time_server_check {
    pub const MAX_OFFSET_MS: i64 = 500;
}

""" + WARNING_RULE,
    CHECK: """pub const START_CORRECTION_MS: i64 = 0;

pub struct Limits {
    level: f64,
}

impl Limits {
    pub const ALC_LIMIT: f64 = 0.6;
}

pub fn servers() -> String {
    std::env::var("WSTX_SNTP_SERVERS").unwrap_or_default()
}

pub fn beacon(now: u64) -> serde_json::Value {
    serde_json::json!({"type": "heartbeat", "sent_at": now, "hold_slot": false})
}
""",
    "client/src/clock/clock.js": """export const ClockDisplay = Object.freeze({
  REFRESH_MS: 250,
});
""",
    SHARED: "pub fn unused() {}\n",
    "tests/clock.cjs": 'const restart = modelValue("WstxStationClock::StepRule::restartMs");\n',
}
ENTRIES = {
    "CL-043-01": {"kind": "requirement", "state": "implemented", "file": "backend/clock/StationClock.sysml", "line": 5,
                  "own": [], "frs": ["FR-006"], "cases": ["TC-043-001"]},
    "CL-043-02": {"kind": "requirement", "state": "implemented", "file": "backend/clock/StationClock.sysml", "line": 15,
                  "own": [], "frs": ["FR-006"], "cases": ["TC-043-002"]},
    "CL-044-01": {"kind": "requirement", "state": "target", "file": "interfaces/internal/StationTime.sysml", "line": 2,
                  "own": [], "frs": ["FR-006"], "cases": []},
    "TC-043-001": {"kind": "verification", "state": "implemented", "file": "backend/clock/StationClock.sysml", "line": 0,
                   "bindings": ["tests/clock.cjs"], "refs": ["CL-043-01"]},
    "TC-043-002": {"kind": "verification", "state": "implemented", "file": "backend/clock/StationClock.sysml", "line": 0,
                   "bindings": ["tests/clock.cjs"], "refs": ["CL-043-02"]},
}
KEY = "backend/clock/StationClock.sysml"


class ValuesTest(unittest.TestCase):
    def faults(self, edits=()) -> list[str]:
        """The fault lines of the fixture after each (path, old, new) edit, each old text
        replaced once."""
        files = dict(FILES)
        for path, old, new in edits:
            self.assertEqual(files[path].count(old), 1, old)
            files[path] = files[path].replace(old, new)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for path, text in files.items():
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_text(text, encoding="utf-8", newline="\n")
            model = tool.Model(root / "docs/sysml")
            links, link_faults = tool.code_links(model, ENTRIES)
            self.assertEqual(link_faults, [])
            return tool.fault_lines(tool.value_faults(model, ENTRIES, links, root))

    def check(self, cases: dict):
        for name, (edits, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(self.faults(edits), expected)

    def test_every_way_of_verifying_is_accepted(self):
        """TV-144 (TR-16): constants with expressions, `200.`, a rounded Real and `from_millis`;
        `A::F`, `B::F` and `a::F`, `b::F` in one module; a module `F`; a JavaScript `D.F`; a
        bound test; a target clause in another file; a marker; a literal, wire name,
        variable and command field found: all accepted."""
        self.assertEqual(self.faults(), [])

    def test_unequal_constant_is_refused(self):
        """TV-145 (TR-16): a constant unequal to its model value is refused."""
        self.check({
            "unequal": ([(AIR, "2 * 60;", "2 * 60 + 1;")],
                        [f"Model and code differ: WstxStationClock::AirClock::windowSeconds: model 120, code 2 * 60 + 1: {KEY}:27"]),
            "swapped between A::F and B::F": (
                [(AIR, "MAX_AGE_SECONDS: u64 = 60;\n    pub const WINDOW", "MAX_AGE_SECONDS: u64 = 90;\n    pub const WINDOW"),
                 (AIR, "MAX_AGE_SECONDS: u64 = 90;\n    pub const SLEW", "MAX_AGE_SECONDS: u64 = 60;\n    pub const SLEW")],
                [f"Model and code differ: WstxStationClock::AirClock::maxAgeSeconds: model 60, code 90: {KEY}:26",
                 f"Model and code differ: WstxStationClock::Correction::maxAgeSeconds: model 90, code 60: {KEY}:31"]),
        })

    def test_value_none_verifies_is_refused(self):
        """TV-146 (TR-16): a value that no constant, marker, target clause or bound test verifies is
        refused."""
        self.check({
            "constant removed": ([(CHECK, "pub const START_CORRECTION_MS: i64 = 0;\n", "")],
                                 [f"Value not verified: WstxStationClock::TimeBase::startCorrectionMs: {KEY}:12"]),
            "implemented clause reaching a target-covered value": (
                [(CLOCK, "(TimeBase)", "(TimeBase, Drift)")],
                [f"Value not verified: WstxStationClock::Drift::limitMs: {KEY}:58"]),
        })

    def test_name_absent_is_refused(self):
        """TV-147 (TR-16): a literal, wire name or variable the code does not hold is refused."""
        self.check({
            "literal": ([(CHECK, '"heartbeat"', '"pulse"')],
                        ["Value not verified: WstxStationLink::Heartbeat::'type': interfaces/internal/StationLink.sysml:9"]),
            "wire name": ([(CHECK, '"sent_at"', '"sent"')],
                          ["Value not verified: WstxStationLink::Heartbeat::sentAt: interfaces/internal/StationLink.sysml:10"]),
            "variable": ([(CHECK, '"WSTX_SNTP_SERVERS"', '"WSTX_TIME_SERVERS"')],
                         [f"Value not verified: WSTX_SNTP_SERVERS: {KEY}:39"]),
        })

    def test_marker_where_the_code_matches_is_refused(self):
        """TV-148 (TR-16): a CodeDiffers on a value the code holds as the model states is refused."""
        self.assertEqual(self.faults([(CHECK, "ALC_LIMIT: f64 = 0.6;", "ALC_LIMIT: f64 = 0.5;")]),
                         [f"Code matches its CodeDiffers: WstxStationClock::Limits::alcLimit: {KEY}:52"])

    def test_name_twice_is_refused(self):
        """TV-149 (TR-16): a value with two candidates, or whose only module `F` stands where another
        value of that name has its code, is refused as named twice."""
        self.check({
            "two candidates": ([(AIR, "use std::time::Duration;\n", "use std::time::Duration;\n\npub const START_CORRECTION_MS: i64 = 0;\n")],
                               [f"Name twice in one code: START_CORRECTION_MS: {KEY}:12"]),
            "A::f, B::f of one module, the value on one F": (
                [(AIR, "    pub const MAX_AGE_SECONDS: u64 = 60;\n", ""),
                 (AIR, "use std::time::Duration;\n", "use std::time::Duration;\n\npub const MAX_AGE_SECONDS: u64 = 60;\n")],
                [f"Name twice in one code: MAX_AGE_SECONDS: {KEY}:26"]),
        })

    def test_constant_outside_its_binding_is_not_verified(self):
        """TV-150 (TR-16): `D::F` or `d::F` outside its code, `D::F` on a unit struct `D` and `F` in a
        `mod` named after no owner verify nothing."""
        self.check({
            "D::F outside its code": ([(AIR, AIR_CLOCK, ""), (SHARED, "pub fn unused() {}\n", AIR_CLOCK)],
                                      [f"Value not verified: WstxStationClock::AirClock::maxAgeSeconds: {KEY}:26",
                                       f"Value not verified: WstxStationClock::AirClock::windowSeconds: {KEY}:27"]),
            "d::F outside its code": ([(AIR, WARNING_RULE, ""), (SHARED, "pub fn unused() {}\n", WARNING_RULE)],
                                      [f"Value not verified: WstxStationClock::WarningRule::maxOffsetMs: {KEY}:44"]),
            "D::F on a unit struct": ([(AIR, "pub struct AirClock {\n    votes: Vec<i64>,\n}\n", "pub struct AirClock;\n")],
                                      [f"Value not verified: WstxStationClock::AirClock::maxAgeSeconds: {KEY}:26",
                                       f"Value not verified: WstxStationClock::AirClock::windowSeconds: {KEY}:27"]),
            "F in a mod named after no owner": ([(AIR, "pub mod time_server_check {", "pub mod server_check {")],
                                                [f"Value not verified: WstxStationClock::TimeServerCheck::maxOffsetMs: {KEY}:40"]),
        })


if __name__ == "__main__":
    unittest.main()
