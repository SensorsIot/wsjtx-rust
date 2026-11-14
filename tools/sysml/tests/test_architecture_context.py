"""TC-DOC-005: the context list WstxContext::OutsideThing and the black boxes of
StationContext, read from the model text."""
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
PENDING_FILE = TOOL.parent / "sysml/pending-structure.json"
ROOT = "context.station.backend"

# The target structure's table of outside things and the function that owns each, written by
# hand: a connected one is owned by the function its port joins, an unconnected one by the
# function of its pending entry.
OWNERS = {
    "catRadio": "catAdapter",
    "flexRadio": "flexAdapter",
    "soundDevice": "audioAdapter",
    "browser": "web",
    "mcpClient": "mcp",
    "udpPeer": "udp",
    "pskReporter": "spots",
    "clubLog": "ranking",
    "timeServer": "clock",
    "windowsTime": "transmit",
    "profileFiles": "profile",
    "tlsFiles": "web",
    "resourceLocks": "radioAuthority",
}
UNCONNECTED = {"browser", "windowsTime", "profileFiles", "tlsFiles", "resourceLocks"}
STRING = r'"(?:[^"\\]|\\.)*"'
JOIN = re.compile(r"\binterface\s+\w+\s*:\s*\w+\s+connect\s+([\w.]+)\s+to\s+(\w+)\.link\s*;")


def body_of(code, pattern):
    opening = re.search(pattern, code)
    return tool.declaration_body(code, opening.end() - 1) if opening else None


def context_faults(text, parts, pending):
    """The faults of the context list in model text `text`, against the deployment's part
    paths `parts` (dot paths) and the pending elements `pending` (name to owner); an empty
    list when the list is as the table states."""
    code = tool.without_comments(text)
    body = body_of(code, r"\benum\s+def\s+OutsideThing\s*\{")
    boxes = body_of(code, r"\bpart\s+def\s+StationContext\s*\{")
    if body is None or boxes is None:
        return ["no enum def OutsideThing or part def StationContext"]
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
    declared = set(re.findall(r"^\s*part\s+(\w+)\b", boxes, flags=re.M)) - {"station"}
    if declared != set(OWNERS) | {"operator"}:
        faults.append("black boxes " + str(sorted(declared ^ (set(OWNERS) | {"operator"}))))
    joins = {}
    for end, box in JOIN.findall(boxes):
        joins.setdefault(box, []).append(end)
    for name in sorted(OWNERS):
        if name in UNCONNECTED:
            owner = pending.get("WstxContext::StationContext::" + name)
            if name in joins or owner != OWNERS[name]:
                faults.append("owner of " + name + ": " + str(owner))
            found = owner
        else:
            ends = joins.get(name, [])
            match = re.fullmatch(r"station\.backend\.stations\.(\w+)\.\w+", ends[0]) if len(ends) == 1 else None
            found = match[1] if match else None
            if found != OWNERS[name]:
                faults.append("owner of " + name + ": " + str(ends))
        place = "context.station.backend.radioAuthority" if found == "radioAuthority" \
            else ROOT + ".stations." + str(found)
        if found == OWNERS[name] and place not in parts:
            faults.append("owner outside the deployment: " + name)
    for name in sorted(set(joins) - set(OWNERS) - {"operator"}):
        faults.append("link of an unlisted entry: " + name)
    if joins.get("operator") != ["station.frontend.browsers.operator"]:
        faults.append("link of operator: " + str(joins.get("operator")))
    return faults


class ContextListTests(unittest.TestCase):
    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_context_list_names_each_outside_thing_once_with_owner_and_source(self):
        """R5: the 13 entries, each with one owner in the deployment and one FollowsSource;
        each fault of the text is refused."""
        text = ARCHITECTURE.read_text(encoding="utf-8")
        parts = set(json.loads(ORACLE_FILE.read_text(encoding="utf-8"))["parts"])
        pending = json.loads(PENDING_FILE.read_text(encoding="utf-8"))["elements"]
        self.assertEqual(len(OWNERS), 13)
        self.assertEqual(context_faults(text, parts, pending), [])
        mutations = {
            "entry removed": (r"\benum resourceLocks \{.*?\n        \}\n", "", pending),
            "join removed": (r"interface clubLogLink : ClubLog\s+connect [\w.]+ to clubLog\.link;", "", pending),
            "second join": (r"(interface udpLink : Udp connect [\w.]+ to udpPeer\.link;)",
                            r"\1\n        interface udpLink2 : Udp connect station.backend.stations.web.client to udpPeer.link;",
                            pending),
            "join to another function": (r"station\.backend\.stations\.clock\.timeSource",
                                         "station.backend.stations.web.client", pending),
            "FollowsSource removed": (r"(\benum windowsTime \{.*?)@FollowsSource \{[^}]*\}", r"\1", pending),
            "pending entry removed": (None, None, {name: owner for name, owner in pending.items()
                                                   if name != "WstxContext::StationContext::tlsFiles"}),
        }
        for name, (pattern, replacement, listed) in mutations.items():
            with self.subTest(mutation=name):
                mutated = text
                if pattern:
                    mutated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
                    self.assertEqual(count, 1, "mutation no longer targets the model")
                self.assertNotEqual(context_faults(mutated, parts, listed), [])


if __name__ == "__main__":
    unittest.main()
