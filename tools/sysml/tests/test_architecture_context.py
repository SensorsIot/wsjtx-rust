"""TC-DOC-005: the context list WstxContext::OutsideThing, read from the model text."""
import importlib.util
import json
from pathlib import Path
import re
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("context_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

# The model file of WstxContext, found by its package.
ARCHITECTURE = next(path for path in tool.model_files(TOOL.parent.parent / "docs/sysml").values()
                    if tool.file_package(tool.without_comments(path.read_text(encoding="utf-8"))) == "WstxContext")
ORACLE_FILE = TOOL.parent / "sysml/architecture-oracle.json"
ROOT = "physicalStation"

# The issue's table of outside things and their owners, written by hand.
OWNERS = {
    "catRadio": "physicalStation::backend::stations::radioControl",
    "flexRadio": "physicalStation::backend::stations::receive",
    "soundDevice": "physicalStation::backend::stations::audio",
    "browser": "physicalStation::backend::stations::web",
    "mcpClient": "physicalStation::backend::stations::mcp",
    "udpPeer": "physicalStation::backend::stations::station",
    "pskReporter": "physicalStation::backend::stations::qso",
    "clubLog": "physicalStation::backend::stations::qso",
    "timeServer": "physicalStation::backend::stations::transmit",
    "windowsTime": "physicalStation::backend::stations::transmit",
    "profileFiles": "physicalStation::backend::stations::profile",
    "tlsFiles": "physicalStation::backend::stations::web",
    "resourceLocks": "physicalStation::backend::radioAuthority",
}
STRING = r'"(?:[^"\\]|\\.)*"'


def context_faults(text, parts):
    """The faults of the context list in model text `text`, against the deployment's part
    paths `parts` (dot paths); an empty list when the list is as the table states."""
    code = tool.without_comments(text)
    opening = re.search(r"\benum\s+def\s+OutsideThing\s*\{", code)
    if not opening:
        return ["no enum def OutsideThing"]
    body = tool.declaration_body(code, opening.end() - 1)
    faults = []
    literals = {}
    for match in re.finditer(r"\benum\s+(\w+)\s*(\{|;)", body):
        literals[match[1]] = tool.declaration_body(body, match.end() - 1) if match[2] == "{" else ""
    if sorted(literals) != sorted(OWNERS):
        faults.append("entries " + str(sorted(set(literals) ^ set(OWNERS))))
    for name, literal in sorted(literals.items()):
        sources = re.findall(r"@\s*FollowsSource\s*\{\s*reference\s*=\s*(" + STRING + r"(?:\s*\+\s*" + STRING
                             + r")*)\s*;\s*\}", literal)
        if len(sources) != 1 or not "".join(part[1:-1] for part in re.findall(STRING, sources[0])).strip():
            faults.append("FollowsSource of " + name)
    owners = {}
    for literal, target in re.findall(r"\bdependency\s+\w+\s+from\s+OutsideThing::(\w+)\s+to\s+([\w:]+)\s*;", code):
        owners.setdefault(literal, []).append(target)
    for name in sorted(OWNERS):
        if owners.get(name) != [OWNERS[name]]:
            faults.append("owner of " + name + ": " + str(owners.get(name)))
        elif OWNERS[name].replace("::", ".") not in parts:
            faults.append("owner outside the deployment: " + name)
    for name in sorted(set(owners) - set(OWNERS)):
        faults.append("owner of an unlisted entry: " + name)
    return faults


class ContextListTests(unittest.TestCase):
    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_context_list_names_each_outside_thing_once_with_owner_and_source(self):
        """R5: the 13 entries, each with one owner in the deployment and one FollowsSource;
        each fault of the text is refused."""
        text = ARCHITECTURE.read_text(encoding="utf-8")
        parts = set(json.loads(ORACLE_FILE.read_text(encoding="utf-8"))["parts"])
        self.assertEqual(len(OWNERS), 13)
        self.assertTrue(all(OWNERS[name].replace("::", ".") in parts for name in OWNERS))
        self.assertEqual(context_faults(text, parts), [])
        clock = "dependency timeServerOwner from OutsideThing::timeServer"
        mutations = {
            "entry removed": (r"\benum resourceLocks \{.*?\n        \}\n", ""),
            "owner removed": (r"dependency clubLogOwner from OutsideThing::clubLog\s+to [\w:]+;", ""),
            "second owner": (r"(dependency udpPeerOwner from OutsideThing::udpPeer\s+to [\w:]+;)",
                             r"\1\n    dependency udpPeerOwner2 from OutsideThing::udpPeer to "
                             r"physicalStation::backend::stations::web;"),
            "owner outside the deployment": (re.escape(clock) + r"\s+to [\w:]+;",
                                             clock + " to physicalStation::frontend::browsers::station;"),
            "FollowsSource removed": (r"(\benum windowsTime \{.*?)@FollowsSource \{[^}]*\}", r"\1"),
        }
        for name, (pattern, replacement) in mutations.items():
            with self.subTest(mutation=name):
                mutated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
                self.assertEqual(count, 1, "mutation no longer targets the model")
                self.assertNotEqual(context_faults(mutated, parts), [])


if __name__ == "__main__":
    unittest.main()
