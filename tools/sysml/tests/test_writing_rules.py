"""TR-18: the writing rules M5.10 (no "user"), M6.4, M6.10, M7.3 to M7.6 and the package names
of M7.5.

The accepted fixture holds the model's forms: the authority marker, an FR of two sentences,
a part definition with its code link joined at `; `, a clause of one sentence naming the
element after it, a case, and a line of exactly 100 columns. Each negative case changes one
text of one file once and expects exactly its one fault line, written by hand.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("writing_rule_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

COLUMNS_100 = "        doc /* A tick follows every second; this line of the rule holds one hundred columns here. */"
ACCEPTED = {
    "Requirements.sysml": """// Canonical authority: SysML
package WstxRequirements {
    requirement 'FR-001' {
        doc /* Station time
             Keep the station time. Show it on the screen. */
    }
}
""",
    "backend/clock/Clock.sysml": """package WstxClockPart {
    part def ClockService {
        doc /* The part that keeps the station time. */
        @ImplementedIn { module = "server/src/clock/mod.rs; " + "server/src/clock/air.rs"; }
    }
}
""",
    "backend/clock/StationClock.sysml": f"""package WstxStationClock {{
    private import WstxClockPart::ClockService;
    requirement 'CL-001-01' {{
        doc /* The ClockService MUST keep the station time by the TickRule. */
        subject clock : ClockService;
    }}
    attribute def TickRule {{
{COLUMNS_100}
        attribute tickRate : Real = 1.0;
    }}
    verification 'TC-001-001' {{
        doc /* The clock ticks every second. */
        subject clock : ClockService;
        objective {{ verify 'CL-001-01'; }}
    }}
}}
""",
}
CLOCK, STATION_CLOCK = "backend/clock/Clock.sysml", "backend/clock/StationClock.sysml"
PART_DOC = "The part that keeps the station time."
CLAUSE_DOC = "The ClockService MUST keep the station time by the TickRule."
# The history texts M7.4 forbids, built so that this file holds none of them.
DATE, ISSUE, FORMERLY = "20" + "26-11-18", "#" + "12", "former" + "ly"

# Each way to break the writing rules: (way, file, text replaced, replacement, the fault).
NEGATIVES = (
    ("the word user", CLOCK, PART_DOC, "The part that keeps the user's time.",
     f"the word user: {CLOCK}:3"),
    ("a clause of two sentences", STATION_CLOCK, CLAUSE_DOC, CLAUSE_DOC + " It MAY drift.",
     f"CL-001-01 is 2 sentences: {STATION_CLOCK}:3"),
    ("a clause without MUST, SHOULD or MAY", STATION_CLOCK, "MUST keep", "keeps",
     f"CL-001-01 has no MUST, SHOULD or MAY: {STATION_CLOCK}:3"),
    ("a clause naming no element of its file", STATION_CLOCK, "by the TickRule", "by the rule",
     f"CL-001-01 names no element of its file: {STATION_CLOCK}:3"),
    ("a clause naming its own identity", STATION_CLOCK, CLAUSE_DOC, "CL-001-01: " + CLAUSE_DOC,
     f"CL-001-01 names itself: {STATION_CLOCK}:3"),
    ("a case naming its own identity", STATION_CLOCK, "The clock ticks", "TC-001-001: the clock ticks",
     f"TC-001-001 names itself: {STATION_CLOCK}:11"),
    ("a date", CLOCK, PART_DOC, f"The part that keeps the station time since {DATE}.",
     f"history in a text: {DATE}: {CLOCK}:3"),
    ("an issue number", CLOCK, PART_DOC, f"The part that keeps the station time, see {ISSUE}.",
     f"history in a text: {ISSUE}: {CLOCK}:3"),
    ("a history word", CLOCK, PART_DOC, f"The part, {FORMERLY} the timer, that keeps the station time.",
     f"history in a text: {FORMERLY}: {CLOCK}:3"),
    ("a name with an underscore", STATION_CLOCK, "attribute tickRate", "attribute tick_rate",
     f"name with an underscore: tick_rate: {STATION_CLOCK}:9"),
    ("a definition in lowerCamelCase", CLOCK, "part def ClockService", "part def clockService",
     f"definition not in UpperCamelCase: clockService: {CLOCK}:2"),
    ("a function file's package not Wstx<file>", STATION_CLOCK, "package WstxStationClock", "package WstxClock",
     f"package WstxClock is not WstxStationClock: {STATION_CLOCK}:1"),
    ("a part file's package without Part", CLOCK, "package WstxClockPart", "package WstxClock",
     f"package WstxClock is not WstxClockPart: {CLOCK}:1"),
    ("Requirements' package not WstxRequirements", "Requirements.sysml", "package WstxRequirements",
     "package WstxRequirement", "package WstxRequirement is not WstxRequirements: Requirements.sysml:2"),
    ("a // comment", CLOCK, "        @ImplementedIn", "        // the code\n        @ImplementedIn",
     f"comment //: {CLOCK}:4"),
    ("a /* */ outside a doc", CLOCK, "        @ImplementedIn", "        /* the code */\n        @ImplementedIn",
     f"comment /* */ outside a doc: {CLOCK}:4"),
    ("a line of 101 columns", STATION_CLOCK, "columns here.", "columns there.",
     f"line of 101 characters: {STATION_CLOCK}:8"),
    ("a path split inside a word", CLOCK, '"server/src/clock/mod.rs; " + "server/src/clock/air.rs"',
     '"server/src/a" + ".rs"', f"joined value split inside a word: {CLOCK}:4"),
)


def writing_lines(files: dict[str, str]) -> list[str]:
    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        for key, text in files.items():
            path = folder / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        return tool.fault_lines(tool.writing_faults(tool.Model(folder)))


def broken(key: str, old: str, new: str) -> dict[str, str]:
    files = dict(ACCEPTED)
    assert files[key].count(old) == 1, old
    files[key] = files[key].replace(old, new)
    return files


class WritingRulesTest(unittest.TestCase):
    def test_accepted(self):
        """TR-18: the model's forms, a joined path at `; ` and a line of 100 columns are accepted."""
        self.assertEqual(len(COLUMNS_100), 100)
        self.assertEqual(writing_lines(ACCEPTED), [])

    def test_negatives(self):
        """TR-18: each way to break the writing rules is refused with its one fault line."""
        for way, key, old, new, expected in NEGATIVES:
            with self.subTest(way):
                self.assertEqual(writing_lines(broken(key, old, new)), [expected])

    def test_doc_line_names_no_element(self):
        """TR-18: a word that begins a wrapped doc line is no element of the file, so a clause
        naming only that word names no element of its file."""
        files = broken(STATION_CLOCK, "by the TickRule", "by the length of a second")
        files = broken_in(files, STATION_CLOCK, "        attribute tickRate",
                          "        doc /* The rule of each tick, a\n             part of a second. */\n"
                          "        attribute tickRate")
        self.assertEqual(writing_lines(files), [f"CL-001-01 names no element of its file: {STATION_CLOCK}:3"])

    def test_real_model_writing(self):
        """TR-18: the real model `docs/sysml` meets the writing rules."""
        self.assertEqual(tool.fault_lines(tool.writing_faults(tool.Model(ROOT / "docs/sysml"))), [])


def broken_in(files: dict[str, str], key: str, old: str, new: str) -> dict[str, str]:
    assert files[key].count(old) == 1, old
    return {**files, key: files[key].replace(old, new)}


if __name__ == "__main__":
    unittest.main()
