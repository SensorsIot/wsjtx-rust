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
    "<K1ABC> <W9XYZ>",
    # Type 1 shapes whose round trip fails: WSJT-X falls through to free text.
    "AB1 W9XYZ", "AB1 W9XYZ -10", "CQ AB1 FN42",
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
    "<PJ4/K1ABC> <W9XYZ>", "<K1ABC> <PJ4/W9XYZ>", "<K1ABC/P> <W9XYZ>", "<PJ4/K1ABC> <W9XYZ> -10",
]
# Zero-noise ft8sim references: message, f0, file.
WAVES = [("CQ K1ABC FN42", 1500.0, "ft8sim-cq-k1abc-fn42-1500.wav"),
         ("<W9XYZ> PJ4/K1ABC RRR", 637.5, "ft8sim-type4-637.5.wav")]
# Zero-noise ft4sim references (complex genft4 waveform, real part written).
FT4_WAVES = [("CQ K1ABC FN42", 1500.0, "ft4sim-cq-k1abc-fn42-1500.wav"),
             ("<W9XYZ> PJ4/K1ABC RRR", 637.5, "ft4sim-type4-637.5.wav")]
FT4_EXTRA = ["HB9BLA K1ABC -12", "K1ABC HB9BLA R-07", "HB9BLA K1ABC RR73"]
# genft4.f90 data symbol positions (0-based in the 103 tones): three blocks of 29.
FT4_DATA = [*range(4, 33), *range(37, 66), *range(70, 99)]
FT4_GRAY_INVERSE = {0: 0, 1: 1, 3: 2, 2: 3}
# genft4.f90 rvec, used only to cross-check the codeword read back from the tones.
FT4_RVEC = "01001010010111101000100110110100101100001000101001111001010101011011111000101"


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


def ft4sim(exe: Path, message: str, f0: float, cwd: str) -> dict:
    command = [str(exe), message, f"{f0}", "0.0", "0", "0", "1", "99"]
    run = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    lines = [line.rstrip("\r") for line in run.stdout.splitlines()]
    normalized = " ".join(message.upper().split())
    if run.returncode != 0 or not any(line.startswith("Message: ") for line in lines):
        return {"message": message, "encoded": False, "output": run.stdout.strip()}
    row = next(line for line in lines if line.startswith("Message: "))
    decoded = row[9:46].rstrip()
    i3, n3 = (int(x) for x in re.search(r"i3\.n3: (\d)\.(\d)", row).groups())
    k = next(i for i, line in enumerate(lines) if line.startswith("f0:"))
    k = next(i for i in range(k + 1, len(lines)) if re.fullmatch(r"[01 ]{77,}", lines[i]))
    scrambled = lines[k].replace(" ", "")  # genft4 returns the payload XOR rvec
    k = next(i for i, line in enumerate(lines) if line.startswith("Channel symbols"))
    tones = lines[k + 1].strip() + lines[k + 2].strip()
    assert len(scrambled) == 77 and len(tones) == 103 and set(tones) <= set("0123"), (message, tones)
    codeword = "".join(f"{FT4_GRAY_INVERSE[int(tones[p])]:02b}" for p in FT4_DATA)
    assert codeword[:77] == scrambled, message
    bits = "".join(str(int(a) ^ int(b)) for a, b in zip(scrambled, FT4_RVEC))
    return {"message": message, "encoded": True, "decoded": decoded, "altered": decoded != normalized,
            "i3": i3, "n3": n3, "bits77": bits, "scrambled77": scrambled, "codeword174": codeword,
            "tones103": tones}


def ft4(exe: Path) -> None:
    out = HERE / "ft4"
    out.mkdir(exist_ok=True)
    version = subprocess.run([str(exe)], capture_output=True, text=True).stdout.strip()
    vectors, waves = [], []
    with tempfile.TemporaryDirectory() as tmp:
        for message in [*MESSAGES, *FT4_EXTRA]:
            vectors.append(ft4sim(exe, message, 1500.0, tmp))
        for message, f0, name in FT4_WAVES:
            v = ft4sim(exe, message, f0, tmp)
            assert v["encoded"] and not v["altered"], v
            shutil.copyfile(Path(tmp) / "000000_000001.wav", out / name)
            waves.append({"message": message, "f0_hz": f0, "file": name, "sha256": sha256(out / name),
                          "command": ["ft4sim.exe", message, f"{f0}", "0.0", "0", "0", "1", "99"]})
    # FT4 and FT8 share pack77: unaltered messages must carry the ft8code payload bits.
    ft8 = {v["message"]: v for v in json.loads((HERE / "ft8code-vectors.json").read_text())["vectors"]}
    shared = 0
    for v in vectors:
        f = ft8.get(v["message"])
        if v["encoded"] and not v["altered"] and f and not f["altered"]:
            assert v["bits77"] == f["bits77"], v["message"]
            shared += 1
    document = {
        "tool": {"usage": version.splitlines(), "exe": exe.as_posix(), "ft4sim_sha256": sha256(exe),
                 "release": "WSJT-X 3.3.0-beta5 windows-x86_64 utilities",
                 "command": 'ft4sim.exe "<message>" 1500.0 0.0 0 0 1 99',
                 "bits77": "ft4sim printed bits XOR genft4.f90 rvec; equal to ft8code bits77 for every shared unaltered message",
                 "codeword": "inverse Gray map 0,1,3,2 of tones at genft4.f90 data positions 5-33, 38-66, 71-99",
                 "altered": "ft4sim Message: text differs from the input upper-cased with blank runs collapsed",
                 "generator": "fixtures/transmit/generate.py --ft4sim"},
        "ft8code_cross_check": f"{shared} messages identical",
        "ft4sim_waves": waves,
        "vectors": vectors,
    }
    (out / "ft4sim-vectors.json").write_text(json.dumps(document, indent=1) + "\n", encoding="utf-8")
    print(f"FT4: {len(vectors)} vectors, {len(waves)} waves")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", type=Path)
    parser.add_argument("--compare-bin", type=Path)
    parser.add_argument("--ft4sim", type=Path)
    args = parser.parse_args()
    if args.ft4sim:
        ft4(args.ft4sim)
    if not args.bin:
        return
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
