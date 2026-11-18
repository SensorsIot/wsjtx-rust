"""TR-07: the outside things of the real model's ShackContext, checked against an owner table
of their own, read from the model text without the Pilot."""
import importlib.util
from pathlib import Path
import re
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("architecture_context_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

MODELS = TOOL.parent.parent / "docs/sysml"
CONTEXT = MODELS / "Context.sysml"
EXTERNAL = MODELS / "interfaces/external"

# Each outside thing of ShackContext with each of its ports and the station function that
# port joins, written by hand: `browsers` is the frontend's browser client, any other name
# a part of the station's backend.
OWNERS = {
    "operator": {"link": "browsers"},
    "agent": {"link": "mcp"},
    "catRadio": {"link": "catAdapter"},
    "flexRadio": {"link": "flexAdapter"},
    "soundDevice": {"link": "audioAdapter"},
    "udpPeer": {"link": "udp"},
    "pskReporter": {"link": "spots", "collector": "spots"},
    "clubLog": {"link": "profile"},
    "countryFiles": {"link": "profile"},
    "timeServer": {"link": "clock"},
}
JOIN = re.compile(r"\binterface\s+(\w+)\s*:\s*(\w+)\s+connect\s+([\w.]+)\s+to\s+([\w.]+)\s*;")
FUNCTION = re.compile(r"shack\.stations\.(?:backend\.(\w+)|frontend\.(browsers))\.\w+")


def external_packages():
    """The packages declared by the files of interfaces/external."""
    return {match for path in EXTERNAL.glob("*.sysml")
            for match in re.findall(r"^package\s+(\w+)\s*\{", path.read_text(encoding="utf-8"), re.M)}


def owner_faults(text):
    """The differences of the Context text `text` from OWNERS; [] when it is as the table
    states."""
    code = tool.structure_code(text)
    tree = tool.parse_model("Context.sysml", text)
    holder = next((element for element in tree.walk() if element.kind == "part def" and element.name == "ShackContext"), None)
    if holder is None:
        return ["no part def ShackContext"]
    things = {child.name: sorted(port.name for port in child.children if port.kind == "port")
              for child in holder.children if child.kind == "part" and child.name != "shack"}
    imported = dict((name, package) for package, name in re.findall(r"\bimport\s+(\w+)::(\w+)\s*;", code))
    external = external_packages()
    faults = []
    if sorted(things) != sorted(OWNERS):
        faults.append("outside things " + str(sorted(set(things) ^ set(OWNERS))))
    joined = {}
    for name, typed, first, second in JOIN.findall(code[holder.begin:holder.stop]):
        for end, other in ((first, second), (second, first)):
            if end.split(".")[0] in things:
                joined.setdefault(end, []).append((name, typed, other))
    for thing, ports in sorted(things.items()):
        if thing in OWNERS and ports != sorted(OWNERS[thing]):
            faults.append(f"ports of {thing}: {ports}")
        for port in ports:
            joins = joined.get(f"{thing}.{port}", [])
            if len(joins) != 1:
                faults.append(f"{thing}.{port} joined {len(joins)} times")
                continue
            name, typed, other = joins[0]
            if imported.get(typed) not in external:
                faults.append(f"{name} typed by {typed}, not an interface of interfaces/external")
            found = FUNCTION.fullmatch(other)
            function = (found[1] or found[2]) if found else other
            if function != OWNERS.get(thing, {}).get(port):
                faults.append(f"{thing}.{port} joined to {function}")
    return faults


class ShackContextOwnerTests(unittest.TestCase):
    def test_outside_things_join_their_owners(self):
        """TR-07: each outside thing of ShackContext has the ports the owner table lists,
        each joined once, through an interface of interfaces/external, to its function."""
        self.assertEqual(owner_faults(CONTEXT.read_text(encoding="utf-8")), [])

    def test_each_difference_from_the_table_is_found(self):
        """TR-07: an outside thing added or removed, a join removed, doubled, moved to another
        function or typed by an internal interface differs from the table."""
        text = CONTEXT.read_text(encoding="utf-8")
        mutations = {
            "outside thing added": (r"(\n        part timeServer \{)",
                                    r"\n        part spareService {\n            port link : ~TimeSourcePort;\n        }\1",
                                    ["outside things ['spareService']", "spareService.link joined 0 times"]),
            "outside thing removed": (r"\n        part timeServer \{.*?\n        \}\n", "\n",
                                      ["outside things ['timeServer']"]),
            "join removed": (r"interface clubLogLink : ClubLog\s+connect [\w.]+ to clubLog\.link;", "",
                             ["clubLog.link joined 0 times"]),
            "second join": (r"(interface udpLink : Udp connect [\w.]+ to udpPeer\.link;)",
                            r"\1\n        interface udpSpare : Udp connect shack.stations.backend.udp.peers to udpPeer.link;",
                            ["udpPeer.link joined 2 times"]),
            "join to another function": (r"shack\.stations\.backend\.clock\.timeSource",
                                         "shack.stations.backend.web.timeSource", ["timeServer.link joined to web"]),
            "internal interface": (r"interface timeSourceLink : TimeSource", "interface timeSourceLink : StationTimeLink",
                                   ["timeSourceLink typed by StationTimeLink, not an interface of interfaces/external"]),
        }
        for name, (pattern, replacement, expected) in mutations.items():
            with self.subTest(mutation=name):
                mutated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
                self.assertEqual(count, 1, "mutation does not target the model")
                self.assertEqual(owner_faults(mutated), expected)


if __name__ == "__main__":
    unittest.main()
