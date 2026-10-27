"""Test-only WSJT-X reference acquisition, execution and Rust comparison.

This tool never changes decoder acceptance thresholds or candidate expected files.
The upstream numerical decoder is executed, not emulated here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import struct
import time
import urllib.request
import wave

REVISION = "0f7d5928449ec747c3d1f6da1306f8c94404c3a9"
PREBUILT_SHA256 = "a2d0b111d91248bf3fd74be016c5afbb82b37fa11bf0e9563a420623bdd1b6ab"
CODEC_SHA256 = "c3263d36e08e012c4a1856c8046564db97af38dfd589374f56c9ad19934a2655"
CASES = [
    {"id": "ft8-official", "mode": "ft8", "filename": "210703_133430.wav",
     "sha256": "9feb99c275770a6618538026da7decc6b09eb6cf63121e5168fa86dcdf00c2f5",
     "source_path": "samples/FT8/210703_133430.wav"},
    {"id": "ft4-current", "mode": "ft4", "filename": "000000_000002.wav",
     "sha256": "d9e91fa04ba138a7b9f41b4103823c77ca1c3a9775101f6b14d60935bcd3813b",
     "source_path": "samples/FT4/000000_000002.wav"},
]
ROW = re.compile(r"^\s*(\d{6})\s+(-?\d+)\s+(-?\d+(?:\.\d+)?)\s+(\d+)\s+([~+])\s{1,2}(.+?)\s*$")
FINISHED = re.compile(r"^<DecodeFinished>\s+(\d+)\s+(\d+)\s+(\d+)\s*$")


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def verify_pcm(path, expected):
    if sha(path) != expected:
        raise ValueError(f"Input hash differs: {path}")
    with wave.open(str(path), "rb") as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (1, 2, 12000, "NONE"):
            raise ValueError(f"Expected uncompressed 12 kHz mono PCM16: {path}")
        pcm = audio.readframes(audio.getnframes())
        return {"sample_rate_hz": 12000, "channels": 1, "sample_bits": 16,
                "frames": audio.getnframes(), "pcm_sha256": hashlib.sha256(pcm).hexdigest()}


def acquire(inputs):
    inputs.mkdir(parents=True, exist_ok=True)
    for case in CASES:
        path = inputs / case["filename"]
        if not path.exists():
            url = f"https://raw.githubusercontent.com/WSJTX/wsjtx/{REVISION}/{case['source_path']}"
            # Never publish partially downloaded or unverified input as a fixture.
            data = urllib.request.urlopen(url, timeout=60).read()
            if hashlib.sha256(data).hexdigest() != case["sha256"]:
                raise ValueError(f"Downloaded bytes differ: {case['id']}")
            path.write_bytes(data)
        verify_pcm(path, case["sha256"])


def reference_command(exe, audio, cwd, mode, depth):
    return [str(exe), "-8" if mode == "ft8" else "-5",
            "-p", "15" if mode == "ft8" else "7.5", "-d", str(depth),
            "-L", "200", "-H", "3500", "-f", "1500", "-w", "0", "-m", "1", "-X", "0", "-Q", "0",
            "-c", "b", "-x", "b", "-a", str(cwd), "-t", str(cwd), str(audio)]


def parse_reference_output(text, mode, expected_attempts):
    """Retain every emission; each completion closes exactly its own attempt."""
    attempts, rows = [], []
    for line in text.splitlines():
        match = ROW.fullmatch(line)
        if match:
            utc, snr, dt, frequency, marker, message = match.groups()
            if marker != ("~" if mode == "ft8" else "+"):
                raise ValueError(f"Wrong mode marker: {line}")
            rows.append({"text": message[:37].rstrip(), "suffix": message[37:].strip(),
                         "frequency_hz": int(frequency), "snr_db": int(snr),
                         "display_dt_seconds": float(dt), "filename_utc_label": utc})
            continue
        finished = FINISHED.fullmatch(line)
        if finished:
            synchronized, decoded, average = map(int, finished.groups())
            if decoded != len(rows):
                raise ValueError("Inconsistent per-attempt completion count")
            attempts.append({"attempt": len(attempts) + 1,
                             "synchronized": synchronized, "decoded": decoded,
                             "average": average, "rows": rows})
            rows = []
        elif line.strip():
            raise ValueError(f"Unparsed decoder output: {line}")
    if rows or len(attempts) != expected_attempts:
        raise ValueError(f"Missing or unexpected completion: expected {expected_attempts}, got {len(attempts)}")
    return attempts


def run_reference(exe, inputs, output, depth, cases=None):
    cases = cases or CASES
    exe = exe.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if sha(exe) != PREBUILT_SHA256:
        raise ValueError("Expected the pinned official WSJT-X beta4 Windows prebuilt jt9 executable")
    version = subprocess.run([str(exe), "--version"], capture_output=True, text=True, check=True, timeout=10).stdout.strip()
    records = []
    for case in cases:
        audio = (inputs / case["filename"]).resolve()
        pcm = verify_pcm(audio, case["sha256"])
        cwd = (output / case["id"]).resolve()
        cwd.mkdir(parents=True, exist_ok=True)
        cmd = reference_command(exe, audio, cwd, case["mode"], depth)
        start = time.perf_counter()
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=120)
        seconds = time.perf_counter() - start
        (cwd / "stdout.txt").write_bytes(result.stdout)
        (cwd / "stderr.txt").write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError(f"Reference failed {case['id']}: {result.returncode}: {result.stderr!r}")
        attempts = parse_reference_output(result.stdout.decode("utf-8", errors="strict"), case["mode"], 1)
        rows = [row for attempt in attempts for row in attempt["rows"]]
        records.append({**case, **pcm, "input_sha256": sha(audio), "command": cmd,
                        "wall_seconds": seconds, "stdout_sha256": sha(cwd / "stdout.txt"),
                        "attempts": attempts, "rows": rows})
    document = {"schema": 1, "reference_source_revision": REVISION, "version": version,
                "binary_provenance": "Pinned official prebuilt binary, not a source build performed by this tool",
                "executable_sha256": sha(exe), "depth": depth, "ap_policy": "upstream-default-on",
                "output_protocol": "official-prebuilt-single",
                "observation_policy": "All emitted rows across all attempts, including repeats; no deduplication or final-set inference",
                "settings": {"frequency_low_hz": 200, "frequency_high_hz": 3500,
                             "my_call": "", "his_call": "", "experience_flags": 0,
                             "multithread_ft8": False, "fft_threads": 1,
                             "gain_normalization": "none", "input_window": "entire original PCM"},
                "cases": records}
    write_json(output / "reference.json", document)
    return document


def stream_frame(kind, body):
    return bytes([kind]) + struct.pack("<I", len(body)) + body


def codec_configure(mode, depth, ap):
    # FT4 has no ft8_ap_on-equivalent switch: Fast depth excludes its AP passes.
    actual_depth = 1 if mode == "ft4" and not ap else depth
    return {"v": 1, "t": "configure", "mode": mode.upper(),
            "trperiod": 15 if mode == "ft8" else 7.5, "depth": actual_depth,
            "mycall": "", "mygrid": "", "his_call": "", "his_grid": "",
            "nfa": 200, "nfb": 3500, "rxfreq": 1500, "ntol": 1000,
            "multithreaded_ft8": False, "ft8_ap_on": ap,
            "ap_cq_only": False, "ap_my_call": False,
            "nutc": 133430 if mode == "ft8" else 2}


def parse_codec_output(text, mode):
    events = [json.loads(line) for line in text.splitlines() if line.strip()]
    if not events or events[0].get("t") != "ready":
        raise ValueError("Missing initial stream ready event")
    rows, ready, finished = [], 0, False
    for event in events:
        if event.get("v") != 1:
            raise ValueError("Unexpected stream protocol version")
        kind = event.get("t")
        if kind == "ready":
            ready += 1
            if ready != 1 or mode.upper() not in event.get("modes", []):
                raise ValueError("Inconsistent ready event")
        elif kind == "decode":
            if finished or event.get("mode") != mode.upper():
                raise ValueError("Decode after completion or wrong mode")
            rows.append({"text": event["message"], "frequency_hz": event["freq"],
                         "snr_db": event["snr"], "display_dt_seconds": event["dt"],
                         "time_label": event["time"]})
        elif kind == "decode_finished":
            if finished:
                raise ValueError("Multiple stream completions for one input period")
            finished = True
        else:
            raise ValueError(f"Stream error or unsupported event: {event}")
    if not finished:
        raise ValueError("Missing stream completion")
    return events, rows


def run_codec(exe, inputs, output, depth, ap, *, expected_sha256=CODEC_SHA256,
              binary_provenance="Official beta4 wsjt-codec prebuilt; no source build"):
    """Use the standard prebuilt stream interface to explicitly control FT8 AP."""
    exe = exe.resolve()
    if sha(exe) != expected_sha256:
        raise ValueError("The codec executable differs from its declared SHA256")
    version = subprocess.run([str(exe), "--version"], capture_output=True, text=True,
                             check=True, timeout=10).stdout.strip()
    records = []
    for case in CASES:
        audio = (inputs / case["filename"]).resolve()
        pcm_info = verify_pcm(audio, case["sha256"])
        with wave.open(str(audio), "rb") as reader:
            pcm = reader.readframes(reader.getnframes())
        cwd = (output / case["id"]).resolve()
        cwd.mkdir(parents=True, exist_ok=True)
        config = codec_configure(case["mode"], depth, ap)
        packet = b"WSJT" + bytes([0, 1]) + struct.pack("<H", 12)
        packet += stream_frame(2, json.dumps(config).encode("utf-8"))
        packet += b"".join(stream_frame(1, pcm[i:i + 24000]) for i in range(0, len(pcm), 24000))
        packet += stream_frame(2, b'{"t":"halt"}')
        (cwd / "request.bin").write_bytes(packet)
        write_json(cwd / "configure.json", config)
        cmd = reference_command(exe, audio, cwd, case["mode"], config["depth"])
        cmd = cmd[:-1] + ["--stream"]
        start = time.perf_counter()
        result = subprocess.run(cmd, input=packet, cwd=cwd, capture_output=True, timeout=120)
        seconds = time.perf_counter() - start
        (cwd / "stdout.ndjson").write_bytes(result.stdout)
        (cwd / "stderr.txt").write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError(f"Stream reference failed: {case['id']}: {result.returncode}")
        events, rows = parse_codec_output(result.stdout.decode("utf-8", errors="strict"), case["mode"])
        records.append({**case, **pcm_info, "input_sha256": sha(audio), "command": cmd,
                        "wall_seconds": seconds, "configure": config,
                        "request_sha256": sha(cwd / "request.bin"),
                        "stdout_sha256": sha(cwd / "stdout.ndjson"), "events": events, "rows": rows})
    document = {"schema": 1, "version": version, "executable_sha256": sha(exe),
                "binary_provenance": binary_provenance,
                "ap_policy": "Explicit FT8 AP " + ("on" if ap else "off; FT4 Fast depth1 unassisted"),
                "configuration_evidence": "Exact configure frames retained; protocol has no configuration readback/ack",
                "cases": records}
    write_json(output / "reference.json", document)
    return document


def run_rust(exe, inputs, output, revision, cases=None):
    exe = exe.resolve()
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for case in cases or CASES:
        audio = (inputs / case["filename"]).resolve()
        pcm = verify_pcm(audio, case["sha256"])
        with wave.open(str(audio), "rb") as reader:
            raw = reader.readframes(reader.getnframes())
        samples = b"".join(struct.pack("<f", n[0] / 32768.0) for n in struct.iter_unpack("<h", raw))
        target = output / (case["id"] + ".f32")
        target.write_bytes(samples)
        command = [str(exe), case["mode"], str(target.resolve())]
        result = subprocess.run(command, capture_output=True, timeout=120)
        (output / (case["id"] + ".stdout.json")).write_bytes(result.stdout)
        (output / (case["id"] + ".stderr.txt")).write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError(f"Rust failed: {case['id']}: {result.returncode}: {result.stderr!r}")
        decoded = json.loads(result.stdout)
        rows = [{"text": row.get("text"), "payload77": row["payload77"],
                 "status": row["status"], "frequency_hz": row["frequency_hz"],
                 "start_frame": row["start_frame"], "snr_db": row["snr_db"]} for row in decoded["decoded"]]
        records.append({**case, **pcm, "input_sha256": sha(audio), "float32_sha256": sha(target),
                        "conversion": "Each signed PCM16 sample /32768, exact in float32; no trim/pad/gain",
                        "command": command, "wall_seconds": decoded["wall_seconds"], "rows": rows})
    document = {"schema": 1, "rust_revision": revision, "executable_sha256": sha(exe), "cases": records}
    write_json(output / "rust.json", document)
    return document


def canonical(text):
    return text.replace(" R -", " R-").replace(" R +", " R+")


def compare(reference, rust, tolerance):
    results = []
    for ref in reference["cases"]:
        candidate = next((c for c in rust["cases"] if c["id"] == ref["id"]), None)
        if candidate is None:
            raise ValueError(f"Missing Rust case: {ref['id']}")
        for key in ("mode", "input_sha256", "pcm_sha256", "frames"):
            if candidate[key] != ref[key]:
                raise ValueError(f"Not identical input: {ref['id']} {key}")
        candidate_rows = candidate["rows"]
        # Maximum one-to-one matching avoids losing a valid same-message pair
        # merely because the first row's nearest candidate was needed by another.
        edges, assigned = [], {}
        for row in ref["rows"]:
            edges.append(sorted((i for i, r in enumerate(candidate_rows)
                         if r.get("text") is not None and canonical(r["text"]) == canonical(row["text"])
                         and abs(r["frequency_hz"] - row["frequency_hz"]) <= tolerance),
                         key=lambda i: (abs(candidate_rows[i]["frequency_hz"] - row["frequency_hz"]), i)))

        def assign(index, seen):
            for i in edges[index]:
                if i in seen:
                    continue
                seen.add(i)
                if i not in assigned or assign(assigned[i], seen):
                    assigned[i] = index
                    return True
            return False

        for index in range(len(edges)):
            assign(index, set())
        by_reference = {ref_index: candidate_index for candidate_index, ref_index in assigned.items()}
        matches, missing = [], []
        for index, row in enumerate(ref["rows"]):
            if index not in by_reference:
                missing.append(row)
                continue
            found = candidate_rows[by_reference[index]]
            delta = abs(found["frequency_hz"] - row["frequency_hz"])
            matches.append({"text": row["text"], "reference_frequency_hz": row["frequency_hz"],
                            "rust_frequency_hz": found["frequency_hz"], "frequency_delta_hz": delta,
                            "rust_payload77": found.get("payload77"),
                            "rust_start_frame": found.get("start_frame"),
                            "reference_display_dt_seconds": row["display_dt_seconds"],
                            "reference_snr_db": row["snr_db"], "rust_snr_db": found.get("snr_db")})
        results.append({"id": ref["id"], "reference_count": len(ref["rows"]),
                        "rust_count": len(candidate_rows), "match_count": len(matches),
                        "matches": matches, "missing_from_rust": missing,
                        "rust_only": [r for i, r in enumerate(candidate_rows) if i not in assigned],
                        "same_messages_within_frequency_tolerance": not missing and len(assigned) == len(candidate_rows)})
    return {"schema": 1, "frequency_tolerance_hz": tolerance, "cases": results,
            "equivalence": "message text plus nearest frequency, one-to-one; arrival order ignored",
            "limitations": ["Reference is an external observation, not independent RF ground truth.",
                            "jt9 stdout does not expose raw77; identical displayed text does not prove identical payload.",
                            "DT and waveform-origin frames use different conventions; reported but not equated.",
                            "SNR estimators differ; reported side by side, not asserted equal.",
                            "AP-enabled references are not equivalent to the unassisted Rust decoder.",
                            "The standard reference CLI exposes no AP-off flag; -X 0 disables experience flags, not AP.",
                            "No missing reference row is silently removed or accepted as equivalent."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    get = sub.add_parser("acquire")
    get.add_argument("--inputs", type=pathlib.Path, required=True)
    run = sub.add_parser("run")
    run.add_argument("--exe", type=pathlib.Path, required=True)
    run.add_argument("--inputs", type=pathlib.Path, required=True)
    run.add_argument("--output", type=pathlib.Path, required=True)
    run.add_argument("--depth", type=int, choices=(1, 2, 3), default=3)
    run.add_argument("--cases", type=pathlib.Path)
    codec = sub.add_parser("run-codec")
    codec.add_argument("--exe", type=pathlib.Path, required=True)
    codec.add_argument("--inputs", type=pathlib.Path, required=True)
    codec.add_argument("--output", type=pathlib.Path, required=True)
    codec.add_argument("--depth", type=int, choices=(1, 2, 3), default=3)
    codec.add_argument("--ap", choices=("on", "off"), default="off")
    rust = sub.add_parser("run-rust")
    rust.add_argument("--exe", type=pathlib.Path, required=True)
    rust.add_argument("--inputs", type=pathlib.Path, required=True)
    rust.add_argument("--output", type=pathlib.Path, required=True)
    rust.add_argument("--revision", required=True)
    rust.add_argument("--cases", type=pathlib.Path)
    comp = sub.add_parser("compare")
    comp.add_argument("--reference", type=pathlib.Path, required=True)
    comp.add_argument("--rust", type=pathlib.Path, required=True)
    comp.add_argument("--output", type=pathlib.Path, required=True)
    comp.add_argument("--frequency-tolerance-hz", type=float, default=5.0)
    args = parser.parse_args()
    if args.command == "acquire":
        acquire(args.inputs)
    elif args.command == "run":
        cases = json.loads(args.cases.read_text(encoding="utf-8")) if args.cases else None
        run_reference(args.exe, args.inputs, args.output, args.depth, cases)
    elif args.command == "run-rust":
        cases = json.loads(args.cases.read_text(encoding="utf-8")) if args.cases else None
        run_rust(args.exe, args.inputs, args.output, args.revision, cases)
    elif args.command == "run-codec":
        run_codec(args.exe, args.inputs, args.output, args.depth, args.ap == "on")
    else:
        if not 0 < args.frequency_tolerance_hz <= 5:
            raise ValueError("Frequency tolerance must be >0 and <= existing 5Hz reference bound")
        write_json(args.output, compare(json.loads(args.reference.read_text(encoding="utf-8")),
                                       json.loads(args.rust.read_text(encoding="utf-8")),
                                       args.frequency_tolerance_hz))


if __name__ == "__main__":
    main()
