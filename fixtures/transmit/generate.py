"""Regenerate the FT8 transmit oracle fixtures from an installed WSJT-X.

Usage (from the repository root, Windows):
    python fixtures/transmit/generate.py --bin C:/WSJT/wsjtx-3.3.0-beta5-reference/bin \
        [--compare-bin C:/WSJT/wsjtx-3.3.0-beta4-reference/bin]

Writes fixtures/transmit/ft8code-vectors.json (ft8code bits/CRC/parity/tones per
message) and the zero-noise ft8sim WAV references listed in WAVES. Only the WSJT-X
executables are the oracle; nothing here uses the Rust implementation. With
--compare-bin, the same messages are also run through a second release and the
script fails if any output differs (pinned baseline cross-check).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MESSAGES = [
    # i3=1 standard messages and every reply/report shape.
    "CQ K1ABC FN42", "CQ HB9BLA JN47", "CQ DX K1ABC FN42", "CQ 123 K1ABC FN42",
    "CQ 000 W9XYZ EN37", "CQ TEST K1ABC/R FN42", "CQ NA W9XYZ EN37", "CQ ABCD K1ABC FN42",
    "CQ K1ABC", "QRZ K1ABC FN42", "DE K1ABC FN42", "K1ABC W9XYZ EN37", "K1ABC W9XYZ",
    "W9XYZ K1ABC -11", "K1ABC W9XYZ R-09", "K1ABC W9XYZ +00", "K1ABC W9XYZ R+05",
    "K1ABC W9XYZ -30", "K1ABC W9XYZ -31", "K1ABC W9XYZ -50", "K1ABC W9XYZ +50",
    "K1ABC W9XYZ R-50", "W9XYZ K1ABC RRR", "K1ABC W9XYZ RR73", "K1ABC W9XYZ 73",
    "W9XYZ K1ABC R FN42", "K1ABC/R W9XYZ EN37", "W9XYZ K1ABC/R R FN42", "K1ABC/R W9XYZ/R RR73",
    "HB9BLA 2E0ABC AA00", "4X1AB 9A1A RR99", "A1B K1A -01", "cq  k1abc   fn42",
    "W9XYZ <PJ4/K1ABC> -11", "<PJ4/K1ABC> W9XYZ R-09", "<YW18FIFA> KA1ABC 73",
    "KA1ABC <YW18FIFA> -11", "<YW18FIFA> KA1ABC",
    # i3=2 (/P) messages.
    "CQ G4ABC/P IO91", "G4ABC/P PA9XYZ JO22", "PA9XYZ G4ABC/P RR73",
    # i3=4 nonstandard calls with 12-bit hashes.
    "CQ KH1/KH7Z", "CQ PJ4/K1ABC", "CQ YW18FIFA", "PJ4/K1ABC <W9XYZ>", "<W9XYZ> PJ4/K1ABC RRR",
    "PJ4/K1ABC <W9XYZ> 73", "<W9XYZ> YW18FIFA", "YW18FIFA <W9XYZ> RRR", "<KA1ABC> YW18FIFA RR73",
    "HB9BLA/P <K1ABC>", "<K1ABC> HB9BLA/QRP 73",
    # i3=0 n3=0 free text and n3=5 telemetry.
    "TNX BOB 73 GL", "HELLO", "73 GL", "ABCDEFGHIJKLM", "A.B/C-D+?", "Q1ABC W9XYZ", "QRP 5W DIPOLE",
    "123456789ABCDEF012", "7FFFFFFFFFFFFFFFFF", "000000000000000001",
    # Messages the Rust encoder must refuse: altered by WSJT-X or an unsupported family.
    "HELLO WORLD 123", "A", "CAFE", "TNX BOB 73 GL!", "K1ABC W9XYZ -51", "CQ <PJ4/K1ABC>",
    "K1ABC FN42 37", "PJ4/K1ABC 37", "K1A K2B 6A WI", "K1ABC W9XYZ R 17B EMA",
    "K1ABC RR73; W9XYZ <KH1/KH7Z> -08", "K1ABC W9XYZ 579 WI", "<PA9XYZ> <G4ABC/P> 570123 IO91NP",
]
# Zero-noise ft8sim references: message, f0, file.
WAVES = [("CQ K1ABC FN42", 1500.0, "ft8sim-cq-k1abc-fn42-1500.wav"),
         ("<W9XYZ> PJ4/K1ABC RRR", 637.5, "ft8sim-type4-637.5.wav")]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ft8code(exe: Path, message: str) -> dict:
    out = subprocess.run([str(exe), message], capture_output=True, text=True, check=True).stdout
    lines = [line.rstrip("\r") for line in out.splitlines()]
    row = next(line for line in lines if re.match(r"^ 1\. ", line))
    tail = row[79:]
    label = re.search(r"([0-9*]\.[0-9]?)\s+(.*)$", tail[3:])

    def after(header: str) -> str:
        i = next(k for k, line in enumerate(lines) if line.startswith(header))
        return lines[i + 1].strip()
    i = next(k for k, line in enumerate(lines) if line.startswith("Channel symbols"))
    tones = lines[i + 2].replace(" ", "")
    return {
        "message": message,
        "decoded": row[42:79].rstrip(),
        "altered": tail[:3].strip() == "*",
        "type": label.group(1) if label else None,
        "family": label.group(2).strip() if label else None,
        "bits77": after("Source-encoded message"),
        "crc14": after("14-bit CRC"),
        "parity83": after("83 Parity bits"),
        "tones79": tones,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", type=Path, required=True)
    parser.add_argument("--compare-bin", type=Path)
    args = parser.parse_args()
    code, sim = args.bin / "ft8code.exe", args.bin / "ft8sim.exe"
    version = subprocess.run([str(sim)], capture_output=True, text=True).stdout.splitlines()[0].strip()
    vectors = [ft8code(code, m) for m in MESSAGES]
    for v in vectors:
        assert len(v["bits77"]) == 77 and len(v["crc14"]) == 14 and len(v["parity83"]) == 83, v
        assert len(v["tones79"]) == 79, v
    compared = None
    if args.compare_bin:
        other = args.compare_bin / "ft8code.exe"
        for v in vectors:
            if ft8code(other, v["message"]) != v:
                raise SystemExit("baseline differs for " + v["message"])
        compared = {"bin": args.compare_bin.as_posix(), "ft8code_sha256": sha256(other),
                    "result": "identical for every message"}
    waves = []
    with tempfile.TemporaryDirectory() as tmp:
        for message, f0, name in WAVES:
            command = [str(sim), message, f"{f0}", "0.0", "0", "0", "1", "99"]
            subprocess.run(command, cwd=tmp, capture_output=True, check=True)
            shutil.copyfile(Path(tmp) / "000000_000001.wav", HERE / name)
            waves.append({"message": message, "f0_hz": f0, "file": name, "sha256": sha256(HERE / name),
                          "command": ["ft8sim.exe", *command[1:]]})
    document = {
        "tool": {"version": version, "bin": args.bin.as_posix(),
                 "ft8code_sha256": sha256(code), "ft8sim_sha256": sha256(sim),
                 "command": 'ft8code.exe "<message>"', "generator": "fixtures/transmit/generate.py"},
        "baseline_cross_check": compared,
        "ft8sim_waves": waves,
        "vectors": vectors,
    }
    (HERE / "ft8code-vectors.json").write_text(json.dumps(document, indent=1) + "\n", encoding="utf-8")
    print(f"{len(vectors)} vectors, {len(waves)} waves")


if __name__ == "__main__":
    main()
