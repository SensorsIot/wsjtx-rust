"""TR-16: model values, names and variables against the code (M6.8, M6.13), on a temporary
root with model and code files.

The accepted fixture covers each value one way: V3 (only target clauses reach it), V4 (its
`@CodeDiffers`, the code differing), V1 (its constant `D::F`, `d::F` or module `F`, a
JavaScript `D.F`; a literal, wire name, command field or variable found) or V2: a test
bound to a case of a clause reaching it (the test `symbol` of its `path::symbol` binding)
holds in its own code, outside comments, its qualified name, or its definition's qualified name and the
feature's name. Its own code is its body and the bodies of the functions of its file it
calls, directly or through each other. A comment is a Rust `//`, `///`, `//!` or block
comment, a Node `//` or block comment, or a Python `#` comment or docstring. Another test,
the file's top level, a comment before the test and a comment inside it do not count.
Each negative test breaks the fixture once. Expected lines are written by hand: message,
file key and line.
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
    "tests/clock.cjs": """// Proves: TC-043-001, TC-043-002
test("the step rule restarts the correction", () => {
  const restart = modelValue("WstxStationClock::StepRule::restartMs");
});
""",
}
ENTRIES = {
    "CL-043-01": {"kind": "requirement", "state": "implemented", "file": "backend/clock/StationClock.sysml", "line": 5,
                  "own": [], "frs": ["FR-006"], "cases": ["TC-043-001"]},
    "CL-043-02": {"kind": "requirement", "state": "implemented", "file": "backend/clock/StationClock.sysml", "line": 15,
                  "own": [], "frs": ["FR-006"], "cases": ["TC-043-002"]},
    "CL-044-01": {"kind": "requirement", "state": "target", "file": "interfaces/internal/StationTime.sysml", "line": 2,
                  "own": [], "frs": ["FR-006"], "cases": []},
    "TC-043-001": {"kind": "verification", "state": "implemented", "file": "backend/clock/StationClock.sysml", "line": 0,
                   "bindings": ["tests/clock.cjs::the step rule restarts the correction"], "refs": ["CL-043-01"]},
    "TC-043-002": {"kind": "verification", "state": "implemented", "file": "backend/clock/StationClock.sysml", "line": 0,
                   "bindings": ["tests/clock.cjs::the step rule restarts the correction"], "refs": ["CL-043-02"]},
}
KEY = "backend/clock/StationClock.sysml"


class ValuesTest(unittest.TestCase):
    def faults(self, edits=(), added=None, bindings=None) -> list[str]:
        """The fault lines of the fixture after each (path, old, new) edit, each old text
        replaced once, with the `added` files (text, or bytes written as they stand) and the
        cases' `bindings` replaced."""
        files = dict(FILES)
        files.update(added or {})
        entries = {identity: dict(entry) for identity, entry in ENTRIES.items()}
        for case, bound in (bindings or {}).items():
            entries[case]["bindings"] = bound
        for path, old, new in edits:
            self.assertEqual(files[path].count(old), 1, old)
            files[path] = files[path].replace(old, new)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for path, text in files.items():
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                if isinstance(text, bytes):
                    (root / path).write_bytes(text)
                else:
                    (root / path).write_text(text, encoding="utf-8", newline="\n")
            model = tool.Model(root / "docs/sysml")
            links, link_faults = tool.code_links(model, entries)
            self.assertEqual(link_faults, [])
            return tool.fault_lines(tool.value_faults(model, entries, links, root))

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


QUALIFIED = "WstxStationClock::StepRule::restartMs"
DEFINITION = "WstxStationClock::StepRule"
NOT_VERIFIED = [f"Value not verified: {QUALIFIED}: {KEY}:22"]
RUST = "server/tests/clock_rule.rs"
NODE = "tests/clock_rule.test.cjs"
PYTHON = "tests/test_clock_rule.py"


def rust_test(body: str, before: str = "") -> str:
    """A Rust file with the test `restart_holds` and its `body`, after `before`."""
    return before + "#[test]\nfn restart_holds() {\n" + body + "}\n"


def node_test(body: str, before: str = "") -> str:
    """A Node file with a test named by `TC-043-002` and its `body`, after `before`."""
    return before + 'test("TC-043-002 the correction restarts", () => {\n' + body + "});\n"


def python_test(body: str) -> str:
    """A Python file with the test method `RuleTest.test_restart` and its `body`."""
    return "import unittest\n\n\nclass RuleTest(unittest.TestCase):\n    def test_restart(self):\n" + body


SYMBOL = {RUST: RUST + "::restart_holds", PYTHON: PYTHON + "::RuleTest.test_restart",
          NODE: NODE + "::TC-043-002 the correction restarts"}


class BoundTestCodeTest(unittest.TestCase):
    """V2 judged on the code of one bound test: `restartMs` of the clause CL-043-02, whose case
    TC-043-002 each test binds by default as the test of its file by its symbol or, in Node,
    by its title, the fixture's tests/clock.cjs emptied."""

    faults = ValuesTest.faults

    def judged(self, path: str, text, binding: str | None = None, bindings=None, edits=()) -> list[str]:
        """The fault lines with `text` at `path` and TC-043-002 bound by `binding` (by default
        the test of the file by its symbol or, in Node, by its title)."""
        bound = {"TC-043-002": [binding or SYMBOL[path]]}
        bound.update(bindings or {})
        return self.faults(edits, added={"tests/clock.cjs": "", path: text}, bindings=bound)

    def verdicts(self, cases: dict, expected: list[str]):
        for name, (path, text, *binding) in cases.items():
            with self.subTest(name):
                self.assertEqual(self.judged(path, text, *binding), expected)

    def test_rust_test_by_symbol_holding_the_name_in_a_string_is_accepted(self):
        """TV-215 (TR-16): a test bound by `path::symbol` whose Rust body holds the qualified name
        in a string literal verifies the value."""
        self.verdicts({"symbol": (RUST, rust_test(f'    assert_eq!(model_value("{QUALIFIED}"), 3000);\n'))}, [])

    def test_node_test_named_by_its_title_is_accepted(self):
        """TV-216 (TR-16): a Node test bound by its title, which names the case, holding the
        qualified name in its callback verifies the value."""
        self.verdicts({"title": (NODE, node_test(f'  assert.equal(modelValue("{QUALIFIED}"), 3000);\n'))}, [])

    def test_rust_test_named_by_proves_with_definition_and_feature_is_accepted(self):
        """TV-217 (TR-16): a Rust test bound by name and tagged with `Proves:`, holding the
        definition's qualified name and the feature's name in its body's code, verifies the
        value."""
        body = f'    let rule = model_part("{DEFINITION}");\n    assert_eq!(rule.value("restartMs"), 3000);\n'
        self.verdicts({"Proves": (RUST, rust_test(body, "// Proves: TC-043-002\n"))}, [])

    def test_name_in_a_helper_two_calls_away_is_accepted(self):
        """TV-218 (TR-16): the qualified name in a function of the file that the bound test calls
        through a second function verifies the value."""
        helpers = (f'fn restart() -> i64 {{\n    model_value("{QUALIFIED}")\n}}\n\n'
                   "fn rule_value() -> i64 {\n    self::restart()\n}\n\n")
        self.verdicts({"two levels": (RUST, rust_test("    assert_eq!(rule_value(), 3000);\n", helpers))}, [])

    def test_definition_in_a_node_arrow_helper_and_feature_in_the_test_is_accepted(self):
        """TV-219 (TR-16): the definition's qualified name in a Node arrow function the bound test
        calls and the feature's name in the test's callback verify the value."""
        helper = f'const rule = name => modelValue("{DEFINITION}", name);\n\n'
        self.verdicts({"arrow": (NODE, node_test('  assert.equal(rule("restartMs"), 3000);\n', helper))}, [])

    def test_python_test_method_is_accepted(self):
        """TV-220 (TR-16): a Python test method bound by `path::Class.test_x`, with or without its
        `Proves:` tag, holding the qualified name, verifies the value, also after line separators
        in an earlier string."""
        body = f'        self.assertEqual(model_value("{QUALIFIED}"), 3000)\n'
        tagged = python_test(body).replace("    def test_", "    # Proves: TC-043-002\n    def test_")
        separated = python_test(body).replace("    def test_", '    def helper(self):\n        return "a b\fc d"\n\n'
                                                                 "    def test_")
        self.verdicts({"symbol": (PYTHON, python_test(body)), "Proves": (PYTHON, tagged),
                       "line separators in an earlier string": (PYTHON, separated)}, [])

    def test_helpers_calling_each_other_end_and_are_accepted(self):
        """TV-221 (TR-16): two functions that call each other, one called by the bound test: the
        check ends and the qualified name in either verifies the value."""
        name = f'model_value("{QUALIFIED}")'
        first = ("fn ping(n: u32) -> i64 {\n    if n == 0 { " + name + " } else { pong(n - 1) }\n}\n\n"
                 "fn pong(n: u32) -> i64 {\n    ping(n)\n}\n\n")
        second = ("fn ping(n: u32) -> i64 {\n    if n == 0 { 0 } else { pong(n - 1) }\n}\n\n"
                  "fn pong(n: u32) -> i64 {\n    if n > 9 { " + name + " } else { ping(n) }\n}\n\n")
        body = "    assert_eq!(pong(2), 3000);\n"
        self.verdicts({"name in the called-back": (RUST, rust_test(body, first)),
                       "name in the called": (RUST, rust_test(body, second))}, [])

    def test_comment_marks_inside_a_string_are_code(self):
        """TV-222 (TR-16): the qualified name in a string literal holding `//` or `/*` before it, in
        Rust, Node and Python, verifies the value."""
        self.verdicts({
            "Rust": (RUST, rust_test(f'    assert_eq!(model_value("// /* {QUALIFIED}"), 3000);\n')),
            "Node": (NODE, node_test(f'  assert.equal(modelValue("// /* {QUALIFIED}"), 3000);\n')),
            "Python": (PYTHON, python_test(f'        self.assertEqual(model_value("# // /* {QUALIFIED}"), 3000)\n')),
        }, [])

    def test_raw_and_template_strings_are_code(self):
        """TV-223 (TR-16): the qualified name in a Rust raw string and in a Node template literal
        verifies the value."""
        self.verdicts({
            "Rust raw": (RUST, rust_test(f'    assert_eq!(model_value(r#"{QUALIFIED} "quoted""#), 3000);\n')),
            "Node template": (NODE, node_test(f"  assert.equal(modelValue(`{QUALIFIED}`), 3000);\n")),
        }, [])

    def test_quote_in_a_comment_does_not_hide_a_string(self):
        """TV-224 (TR-16): a bound test holding the name in a comment and in a string, after a
        comment holding a quote mark, verifies the value."""
        self.verdicts({
            "Rust": (RUST, rust_test(f'    // reads the "rule\n    // {QUALIFIED}\n'
                                     f'    assert_eq!(model_value("{QUALIFIED}"), 3000);\n')),
            "Node": (NODE, node_test(f"  // it's the rule\n  /* \" {QUALIFIED} */\n"
                                     f'  assert.equal(modelValue("{QUALIFIED}"), 3000);\n')),
        }, [])

    def test_name_in_another_unbound_test_is_refused(self):
        """TV-225 (TR-16): the qualified name in another test of the file, not bound, while the bound
        test does not hold it, verifies nothing."""
        other = f'\n#[test]\nfn rule_is_read() {{\n    assert_eq!(model_value("{QUALIFIED}"), 3000);\n}}\n'
        self.verdicts({"other test": (RUST, rust_test("    assert_eq!(restart(), 3000);\n") + other)}, NOT_VERIFIED)

    def test_name_in_another_test_bound_to_another_case_is_refused(self):
        """TV-226 (TR-16): the qualified name in another test of the file that is bound to another
        case verifies nothing."""
        text = (rust_test("    assert_eq!(restart(), 3000);\n", "// Proves: TC-043-002\n")
                + f'\n// Proves: TC-043-001\n#[test]\nfn rule_is_read() {{\n    assert_eq!(model_value("{QUALIFIED}"), 3000);\n}}\n')
        self.assertEqual(self.judged(RUST, text, None, {"TC-043-001": [RUST + "::rule_is_read"]}), NOT_VERIFIED)

    def test_name_at_the_top_level_is_refused(self):
        """TV-227 (TR-16): the qualified name only at the file's top level, as a Rust `const` or
        `static` and as a Node module `const`, verifies nothing."""
        self.verdicts({
            "Rust const": (RUST, rust_test("    assert_eq!(model_value(RULE), 3000);\n", f'const RULE: &str = "{QUALIFIED}";\n\n')),
            "Rust static": (RUST, rust_test("    assert_eq!(model_value(RULE), 3000);\n", f'static RULE: &str = "{QUALIFIED}";\n\n')),
            "Node const": (NODE, node_test("  assert.equal(modelValue(RULE), 3000);\n", f'const RULE = "{QUALIFIED}";\n\n')),
        }, NOT_VERIFIED)

    def test_name_in_a_comment_before_the_test_is_refused(self):
        """TV-228 (TR-16): the qualified name only in a comment between the `Proves:` tag and the
        test verifies nothing."""
        body = "    assert_eq!(restart(), 3000);\n"
        self.verdicts({
            "line comment": (RUST, rust_test(body, f"// Proves: TC-043-002\n// reads {QUALIFIED}\n")),
            "doc comment": (RUST, rust_test(body, f"// Proves: TC-043-002\n/// reads {QUALIFIED}\n")),
        }, NOT_VERIFIED)

    def test_helper_only_another_test_calls_is_refused(self):
        """TV-229 (TR-16): the qualified name in a function that only an unbound test calls verifies
        nothing."""
        text = (f'fn restart() -> i64 {{\n    model_value("{QUALIFIED}")\n}}\n\n'
                + rust_test("    assert_eq!(3000, 3000);\n")
                + "\n#[test]\nfn rule_is_read() {\n    assert_eq!(restart(), 3000);\n}\n")
        self.verdicts({"helper of another test": (RUST, text)}, NOT_VERIFIED)

    def test_two_parts_in_two_tests_are_refused(self):
        """TV-230 (TR-16): the definition's qualified name in another test and the feature's name in
        the bound test verify nothing."""
        text = (rust_test('    assert_eq!(rule.value("restartMs"), 3000);\n')
                + f'\n#[test]\nfn rule_is_read() {{\n    let rule = model_part("{DEFINITION}");\n}}\n')
        self.verdicts({"split over two tests": (RUST, text)}, NOT_VERIFIED)

    def test_name_in_an_untagged_test_beside_the_bound_test_is_refused(self):
        """TV-231 (TR-16): the qualified name in an untagged test of the file, while the test bound
        by name (tagged in Rust, named by its title in Node) does not hold it, verifies nothing."""
        self.verdicts({
            "Rust": (RUST, rust_test("    assert_eq!(restart(), 3000);\n", "// Proves: TC-043-002\n")
                     + f'\n#[test]\nfn rule_is_read() {{\n    assert_eq!(model_value("{QUALIFIED}"), 3000);\n}}\n'),
            "Node": (NODE, node_test("  assert.equal(restart(), 3000);\n")
                     + f'\ntest("the rule is read", () => {{\n  assert.equal(modelValue("{QUALIFIED}"), 3000);\n}});\n'),
        }, NOT_VERIFIED)

    def test_binding_naming_no_test_of_the_file_is_refused(self):
        """TV-232 (TR-16): a name binding that names no test of its file verifies nothing, though
        another test of the file holds the qualified name."""
        text = f'#[test]\nfn rule_is_read() {{\n    assert_eq!(model_value("{QUALIFIED}"), 3000);\n}}\n'
        self.verdicts({"no test of the name": (RUST, text)}, NOT_VERIFIED)

    def test_unreadable_bound_file_is_not_verified(self):
        """TV-233 (TR-16): a bound file that is no UTF-8, or holds a raw string without its end,
        verifies nothing and raises no exception."""
        name = f'    assert_eq!(model_value("{QUALIFIED}"), 3000);\n'
        self.verdicts({
            "not UTF-8 by symbol": (RUST, rust_test("    // \xff\n" + name).encode("latin-1")),
            "not UTF-8, tagged": (RUST, rust_test("    // \xff\n" + name, "// Proves: TC-043-002\n").encode("latin-1")),
            "raw string without its end": (RUST, rust_test(name + '    let open = r#"never closed;\n')),
        }, NOT_VERIFIED)

    def test_rust_line_comment_in_the_test_is_refused(self):
        """TV-234 (TR-16): the qualified name only in a Rust `//` comment in the bound test verifies
        nothing."""
        self.verdicts({"//": (RUST, rust_test(f"    // {QUALIFIED}\n    assert_eq!(restart(), 3000);\n"))}, NOT_VERIFIED)

    def test_rust_doc_comment_in_the_test_is_refused(self):
        """TV-235 (TR-16): the qualified name only in a Rust `///` or `//!` comment in the bound test
        verifies nothing."""
        self.verdicts({
            "///": (RUST, rust_test(f"    /// {QUALIFIED}\n    assert_eq!(restart(), 3000);\n")),
            "//!": (RUST, rust_test(f"    //! {QUALIFIED}\n    assert_eq!(restart(), 3000);\n")),
        }, NOT_VERIFIED)

    def test_rust_block_comment_in_the_test_is_refused(self):
        """TV-236 (TR-16): the qualified name only in a Rust block comment in the bound test, on one
        line or over lines, or a `/** */` comment, verifies nothing."""
        self.verdicts({
            "one line": (RUST, rust_test(f"    /* {QUALIFIED} */\n    assert_eq!(restart(), 3000);\n")),
            "over lines": (RUST, rust_test(f"    /* reads\n       {QUALIFIED} */\n    assert_eq!(restart(), 3000);\n")),
            "/** */": (RUST, rust_test(f"    /** {QUALIFIED} */\n    assert_eq!(restart(), 3000);\n")),
        }, NOT_VERIFIED)

    def test_node_line_comment_in_the_test_is_refused(self):
        """TV-237 (TR-16): the qualified name only in a Node `//` comment in the test's callback
        verifies nothing."""
        self.verdicts({"//": (NODE, node_test(f"  // {QUALIFIED}\n  assert.equal(restart(), 3000);\n"))}, NOT_VERIFIED)

    def test_node_block_comment_in_the_test_is_refused(self):
        """TV-238 (TR-16): the qualified name only in a Node block comment in the test's callback
        verifies nothing."""
        self.verdicts({
            "one line": (NODE, node_test(f"  /* {QUALIFIED} */\n  assert.equal(restart(), 3000);\n")),
            "over lines": (NODE, node_test(f"  /* reads\n     {QUALIFIED} */\n  assert.equal(restart(), 3000);\n")),
        }, NOT_VERIFIED)

    def test_python_comment_in_the_test_is_refused(self):
        """TV-239 (TR-16): the qualified name only in a Python `#` comment in the test method verifies
        nothing."""
        self.verdicts({"#": (PYTHON, python_test(f"        # {QUALIFIED}\n        self.assertEqual(restart(), 3000)\n"))},
                      NOT_VERIFIED)

    def test_python_docstring_of_the_test_is_refused(self):
        """TV-240 (TR-16): the qualified name only in the docstring of the test method verifies
        nothing."""
        self.verdicts({"docstring": (PYTHON, python_test(f'        """Reads {QUALIFIED}."""\n'
                                                         "        self.assertEqual(restart(), 3000)\n"))}, NOT_VERIFIED)

    def test_comment_in_a_called_helper_is_refused(self):
        """TV-241 (TR-16): the qualified name only in a comment of a function the bound test calls,
        in Rust and in a Node arrow function, verifies nothing."""
        self.verdicts({
            "Rust": (RUST, rust_test("    assert_eq!(restart(), 3000);\n",
                                     f"fn restart() -> i64 {{\n    // {QUALIFIED}\n    3000\n}}\n\n")),
            "Node arrow": (NODE, node_test("  assert.equal(restart(), 3000);\n",
                                           f"const restart = () => {{\n  // {QUALIFIED}\n  return 3000;\n}};\n\n")),
        }, NOT_VERIFIED)

    def test_second_form_with_one_part_in_a_comment_is_refused(self):
        """TV-242 (TR-16): the definition's qualified name in code and the feature's name only in a
        comment, or the other way round, verify nothing."""
        self.verdicts({
            "feature in a comment": (RUST, rust_test(f'    let rule = model_part("{DEFINITION}");\n    // restartMs\n')),
            "definition in a comment": (RUST, rust_test(f'    // {DEFINITION}\n    assert_eq!(rule.value("restartMs"), 3000);\n')),
        }, NOT_VERIFIED)

    def test_variable_in_the_bound_test_is_still_not_verified(self):
        """TV-243 (TR-16): a `WSTX_*` variable whose name stands only in the code of a bound test of a
        clause reaching it is not verified."""
        text = rust_test('    assert_eq!(std::env::var("WSTX_SNTP_SERVERS").is_ok(), true);\n'
                         f'    assert_eq!(model_value("{QUALIFIED}"), 3000);\n')
        edits = [(CLOCK, "(StepRule)", "(StepRule, TimeServerCheck)"), (CHECK, '"WSTX_SNTP_SERVERS"', '"WSTX_TIME_SERVERS"')]
        self.assertEqual(self.judged(RUST, text, edits=edits), [f"Value not verified: WSTX_SNTP_SERVERS: {KEY}:39"])


if __name__ == "__main__":
    unittest.main()
