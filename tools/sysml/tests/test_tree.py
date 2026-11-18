"""TR-03: the model files are exactly the tree of M2.1 with the packages of M7.5; beside them
only `data/`; each required package is the package of exactly one model file.

Each case writes the tree as tiny files in a temporary folder, breaks it once and compares
the fault lines with lines written by hand. The tree below is copied from M2.1.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("tree_rule_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

# M2.1, folder by folder; `*` marks a part's own file.
M21 = """
: Context, Requirements, Shack, UseCases
interfaces/internal: StationLink, StationCommands, Strategies, RankingControl, AutoControl,
    QsoControl, LogControl, ReceiveControl, TransmitControl, AudioControl, RadioControl, Keying,
    Decodes, DisplayData, StationTime, OperatingChain, Hearing, AudioStreams, ModeProcessing,
    ProfileAccess, RecordingTransfer, UdpControl, WebControl
interfaces/external: OperatorInteraction, Mcp, Cat, RadioProperties, FlexApi, SoundDevice, Udp,
    PskReporter, ClubLog, CountryFiles, TimeSource
backend/supervisor: Supervisor*, OperatingSelection, StationAuthority, Startup, SettingsCheck
backend/web: Web*, Listener, ContentCoding
backend/mcp: Mcp*, McpEndpoint
backend/profile: Profile*, ProfileDocument, Recordings
backend/receive: Receive*, ReceiveJob, Spectrum, LiveReceive
backend/modes: Modes*, Decode, MessageEncode, MessagePayload
backend/clock: Clock*, StationClock
backend/transmit: Transmit*, TransmitState, Schedule, TxLevel
backend/operating: Operating*, StrategySelection
backend/operating/ranking: Ranking*, ValueOrder, ContestRanking, IgnoreLists, WantedList,
    MostWanted, Alert
backend/operating/auto: Auto*, TargetChoice, CqWhenIdle, TxSlot, Leave, AutoMode
backend/operating/qso: Qso*, StandardQso, SpecialActivities, MessageChoice, QsoTransmit, HoldTx
backend/log: Log*, Logbook, CountryFile
backend/spots: Spots*, HearingFeed, SpotsReporting
backend/udp: Udp*, UdpSender
backend/audio: Audio*, AudioDevice, Capture, Endpoints, Playback
backend/radioControl: RadioControl*, CatControl, CatLifecycle, RadioFacts, RadioSetup
backend/flexAdapter: FlexAdapter*, FlexSession
frontend: BrowserClient*, OperatingScreen, BandActivityPane, SignalArea, QsoPane, LowerPanel,
    Settings
shared: Units, ModelBindings, ModelNotes
"""


def expected_tree() -> dict[str, str]:
    """Each file key of M21 with its package (M7.5: `Wstx` and the file name, `Part` added
    for a part's own file)."""
    found = {}
    for entry in M21.replace("\n    ", " ").strip().split("\n"):
        folder, names = entry.split(":")
        for name in names.split(","):
            plain = name.strip().rstrip("*")
            key = (folder.strip() + "/" if folder.strip() else "") + plain + ".sysml"
            found[key] = "Wstx" + plain + ("Part" if name.strip().endswith("*") else "")
    return found


def write_tree(folder: Path, files: dict[str, str]):
    for key, text in files.items():
        path = folder / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def accepted() -> dict[str, str]:
    files = {key: f"package {package} {{\n}}\n" for key, package in expected_tree().items()}
    files["data/hamlib-models.json"] = "[]\n"
    return files


def tree_lines(files: dict[str, str]) -> list[str]:
    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        write_tree(folder, files)
        return tool.fault_lines(tool.tree_faults(folder, tool.Model(folder)))


def catalog_error(files: dict[str, str]):
    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        write_tree(folder, files)
        try:
            tool.canonical_catalog(folder, folder)
        except ValueError as error:
            return str(error)
        return None


class TreeTest(unittest.TestCase):
    def test_tree_is_m21(self):
        """TR-03: the tool's tree is M2.1's, 116 files, each with its M7.5 package."""
        expected = expected_tree()
        self.assertEqual(len(expected), 116)
        self.assertEqual(tool.tree_files(), expected)

    def test_accepted_tree(self):
        """TR-03: the M2.1 tree with a data file in `data/` is accepted."""
        self.assertEqual(tree_lines(accepted()), [])

    def test_extra_model_file(self):
        """TR-03: a model file outside the tree is refused."""
        files = accepted()
        files["backend/clock/Extra.sysml"] = "package WstxExtra {\n}\n"
        self.assertEqual(tree_lines(files), ["model file outside the tree: backend/clock/Extra.sysml:1"])

    def test_listed_file_missing(self):
        """TR-03: a file of the tree that is missing is refused."""
        files = accepted()
        del files["backend/clock/StationClock.sysml"]
        self.assertEqual(tree_lines(files), ["model file of the tree missing: backend/clock/StationClock.sysml:0"])

    def test_reference_readme(self):
        """TR-03: a file beside the model files outside `data/` (`reference/README.md`) is refused."""
        files = accepted()
        files["reference/README.md"] = "# Reference\n"
        self.assertEqual(tree_lines(files), ["file outside the model files and data/: reference/README.md:0"])

    def test_required_packages_accepted(self):
        """TR-03: the tree, each required package declared once, passes the catalog."""
        self.assertIsNone(catalog_error(accepted()))

    def test_required_package_missing(self):
        """TR-03: a required package declared by no file is refused."""
        files = accepted()
        files["Context.sysml"] = "package WstxOutside {\n}\n"
        self.assertEqual(catalog_error(files), "Canonical model packages missing: WstxContext")

    def test_required_package_twice(self):
        """TR-03: a required package declared by two files is refused."""
        files = accepted()
        files["shared/Units.sysml"] = "package WstxContext {\n}\n"
        self.assertEqual(catalog_error(files),
                         "Duplicate canonical model package: WstxContext: Context.sysml, shared/Units.sysml")

    def test_real_model_tree(self):
        """TR-03: the real model `docs/sysml` is the M2.1 tree with only `data/` beside it."""
        folder = ROOT / "docs/sysml"
        self.assertEqual(tool.fault_lines(tool.tree_faults(folder, tool.Model(folder))), [])


if __name__ == "__main__":
    unittest.main()
