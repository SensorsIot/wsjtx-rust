# Proves: CL-007-03; TC-004-001, TC-004-002.
"""CL-007-03: each decoder mode's offline case is executed by that mode's own fixtures.

TC-004-001 (FT4) and TC-004-002 (FT8) must bind named Rust tests whose bodies select
that mode and load an independent fixture containing that mode's cases. An FT8-only
executable, or a whole-file binding that only names the case in a Proves tag, does not
establish FT4 correctness (and vice versa).
"""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
REQUIREMENTS = ROOT / "docs/sysml/Requirements.sysml"
CASES = {"TC-004-001": ("ft4", "Mode::Ft4"), "TC-004-002": ("ft8", "Mode::Ft8")}


def executable(identifier: str) -> list[str]:
    texts = (path.read_text(encoding="utf-8") for path in sorted(REQUIREMENTS.parent.rglob("*.sysml")))
    text = next(text for text in texts if f"verification '{identifier}' {{" in text)
    start = text.index(f"verification '{identifier}' {{")
    body = text[start:text.index("\n    }", start)]
    binding = re.search(r'attribute\s+executable\s*:\s*String\s*=\s*"([^"]*)"\s*;', body)
    if not binding:
        return []
    return [item.strip() for item in binding[1].split(";") if item.strip()]


def function_body(path: Path, symbol: str) -> str:
    source = path.read_text(encoding="utf-8")
    match = re.search(r"(?m)^(?:async\s+)?fn\s+" + re.escape(symbol) + r"\s*\(", source)
    if not match:
        raise AssertionError(f"missing test function {path.name}::{symbol}")
    end = re.search(r"(?m)^}", source[match.end():])
    return source[match.start():match.end() + end.end()]


def fixture_modes(path: Path, body: str) -> set[str]:
    modes = set()
    for name in re.findall(r'include_str!\(\s*"([^"]+\.json)"\s*\)', body):
        document = json.loads((path.parent / name).read_text(encoding="utf-8"))
        for key in ("vectors", "cases"):
            for entry in document.get(key, []):
                modes.update(entry.get(field) for field in ("mode", "decode_mode") if entry.get(field))
    return modes


class DecoderModeTraceTests(unittest.TestCase):
    def test_each_mode_case_binds_tests_of_that_mode(self):
        for identifier, (mode, selector) in CASES.items():
            with self.subTest(case=identifier):
                bindings = executable(identifier)
                self.assertTrue(bindings, f"{identifier} has no executable binding")
                covered = set()
                for binding in bindings:
                    path_text, separator, symbol = binding.partition("::")
                    self.assertTrue(separator and symbol,
                                    f"{identifier}: whole-file binding {binding} does not show which test runs {mode}")
                    path = ROOT / path_text
                    body = function_body(path, symbol)
                    self.assertIn(selector, body, f"{identifier}: {binding} never selects {mode}")
                    covered |= fixture_modes(path, body)
                self.assertIn(mode, covered, f"{identifier}: no bound test loads an independent {mode} fixture")


if __name__ == "__main__":
    unittest.main()
