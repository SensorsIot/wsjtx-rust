"""CR18 test-only upstream simulator execution and immutable PCM fixture checks."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, math, pathlib, re, shutil, struct, subprocess, wave

ROOT = pathlib.Path(__file__).resolve().parent
DECLARATIONS = next(p for p in (ROOT/"cases-proposed.json", ROOT/"cases-declaration.json",
                               ROOT.parent/"fixtures/decoder/simulator-cases.json") if p.exists())
REVISION = "0f7d5928449ec747c3d1f6da1306f8c94404c3a9"
FT4_SHA = "9af0e5e984b45a1de70f4407a65aa80d970b06b30b1b330481900bc2ad07dd00"
MASK = "01001010010111101000100110110100101100001000101001111001010101011011111000101"


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    pathlib.Path(path).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def declaration_hashes():
    # Git checkouts may differ only in newline representation, never in case values.
    lf = DECLARATIONS.read_bytes().replace(b"\r\n", b"\n")
    return {hashlib.sha256(lf).hexdigest(), hashlib.sha256(lf.replace(b"\n", b"\r\n")).hexdigest()}


def packed_message(message):
    """Independent standard type1 arithmetic, restricted to these declared cases."""
    def call(text):
        if text == "CQ":
            return 2
        word = (" " + text if text[1].isdigit() else text).ljust(6)
        if len(word) != 6:
            raise ValueError("unsupported fixture callsign")
        value = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".index(word[0])
        value = value * 36 + "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".index(word[1])
        value = value * 10 + int(word[2])
        for char in word[3:]:
            value = value * 27 + " ABCDEFGHIJKLMNOPQRSTUVWXYZ".index(char)
        return value + 2063592 + 4194304
    first, second, exchange = message.split()
    if re.fullmatch("[A-R]{2}[0-9]{2}", exchange):
        grid = ((ord(exchange[0]) - 65) * 18 + ord(exchange[1]) - 65) * 100 + int(exchange[2:])
    elif re.fullmatch("[+-][0-9]{2}", exchange):
        grid = 32400 + int(exchange) + 35
    else:
        raise ValueError("unsupported fixture exchange")
    return f"{call(first):028b}0{call(second):028b}00{grid:015b}001"


def parse_output(text, mode, wanted):
    match = re.search(r"(?:Decoded message:|Message:)\s*(.*?)\s+i3\.n3:", text)
    if not match or match[1].strip() != wanted:
        raise ValueError("simulator changed or refused the declared message")
    before, after = text.split("Channel symbols:", 1)
    vectors = [re.sub(r"\s", "", line) for line in before.splitlines()
               if re.fullmatch(r"\s*[01][01\s]+\s*", line)]
    emitted = next((value for value in reversed(vectors) if len(value) == 77), None)
    if emitted is None:
        raise ValueError("missing emitted77 vector")
    canonical = emitted if mode == "ft8" else "".join(str(int(a) ^ int(b)) for a, b in zip(emitted, MASK))
    if canonical != packed_message(wanted):
        raise ValueError("emitted payload differs from independent message packing")
    digits = []
    for line in after.lstrip().splitlines():
        if not re.fullmatch(r"[0-7]+", line.strip()):
            break
        digits.append(line.strip())
    tones = "".join(digits)
    if len(tones) != (79 if mode == "ft8" else 103):
        raise ValueError("wrong emitted tone count, including wrapped FT4 output")
    if "will be clipped" in text.lower():
        raise ValueError("upstream generator warned of clipping")
    return {"message": wanted, "emitted_bits77": emitted, "payload77": canonical, "tones": tones}


def inspect_wav(path, frames):
    with wave.open(str(path), "rb") as reader:
        if (reader.getnchannels(), reader.getsampwidth(), reader.getframerate(), reader.getcomptype(),
                reader.getnframes()) != (1, 2, 12000, "NONE", frames):
            raise ValueError("wrong or truncated PCM format/length")
        raw = reader.readframes(frames)
    if len(raw) != 2 * frames:
        raise ValueError("truncated PCM")
    values = [n[0] for n in struct.iter_unpack("<h", raw)]
    return {"sha256": sha(path), "pcm_sha256": hashlib.sha256(raw).hexdigest(), "frames": frames,
            "peak": max(map(abs, values)) / 32768, "rms": math.sqrt(sum(v*v for v in values)/frames)/32768,
            "fullscale_count": sum(v in (-32768, 32767) for v in values),
            "first_nonzero_frame": next((i for i, v in enumerate(values) if v), None),
            "last_nonzero_frame": next((frames-1-i for i, v in enumerate(reversed(values)) if v), None)}


def verify_frozen_wav(path, frames, expected_sha256):
    if sha(path) != expected_sha256:
        raise ValueError("frozen fixture hash mismatch")
    return inspect_wav(path, frames)


def verify_manifest(path, fixture_directory=None):
    path = pathlib.Path(path)
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema") != 1 or manifest.get("source_revision") != REVISION:
        raise ValueError("unknown manifest schema or source revision")
    mode = manifest.get("mode")
    if mode not in ("ft4", "ft8"):
        raise ValueError("unknown manifest mode")
    if manifest.get("cases_declaration_sha256") not in declaration_hashes():
        raise ValueError("case declaration identity changed")
    declarations = {c["id"]: c for c in json.loads(DECLARATIONS.read_text())["cases"]
                    if c["mode"] == mode}
    if fixture_directory is None:
        fixture_directory = path.parent.parent/"oracle"
        if not (fixture_directory/"independent-vector-tool/generate.py").exists():
            fixture_directory = ROOT.parent/"fixtures/decoder"
    fixture_directory = pathlib.Path(fixture_directory)
    if manifest.get("independent_oracle_sha256") != sha(fixture_directory/"independent-vector-tool/generate.py"):
        raise ValueError("independent oracle identity changed")
    oracle, matrices = load_oracle(fixture_directory)
    seen = set()
    for case in manifest["cases"]:
        if case["id"] in seen or case["id"] not in declarations:
            raise ValueError("unknown or duplicated fixture")
        seen.add(case["id"])
        for field, value in declarations[case["id"]].items():
            if case.get(field) != value:
                raise ValueError("fixture settings differ from declared contract")
        if case.get("filename") != case["id"] + ".wav":
            raise ValueError("final WAV filename differs from declared identity")
        verify_frozen_wav(path.parent/case["filename"], case["frames"], case["sha256"])
        if len(case["components"]) != len(case["known_expected_messages"]):
            raise ValueError("missing or extra component station")
        for index, (component, message) in enumerate(zip(case["components"], case["known_expected_messages"])):
            # Historical command paths remain provenance, not authority to read outside the dataset.
            folder = path.parent/case["id"]/f"component-{index}"
            verify_frozen_wav(folder/"000000_000001.wav", case["frames"], component["sha256"])
            if (sha(folder/"stdout.txt") != component["stdout_sha256"]
                    or sha(folder/"stderr.txt") != component["stderr_sha256"]):
                raise ValueError("component raw evidence changed")
            truth = parse_output((folder/"stdout.txt").read_text(), mode, message)
            for field, expected in truth.items():
                if component.get(field) != expected:
                    raise ValueError("component message, payload or tones changed")
            independent = oracle.channel(packed_message(message), mode, *matrices)
            expected_tones = independent["tones"] if mode == "ft8" else independent["tones"][1:-1]
            if truth["tones"] != expected_tones:
                raise ValueError("component tones differ from independent channel oracle")
    if seen != set(declarations):
        raise ValueError("expected exact four declared fixtures for manifest mode")
    return {"mode": manifest["mode"], "verified": len(seen)}


def mix_pcm(first, second, output, gains):
    with wave.open(str(first), "rb") as reader:
        params, a = reader.getparams(), reader.readframes(reader.getnframes())
    if (params.nchannels, params.sampwidth, params.framerate, params.comptype) != (1, 2, 12000, "NONE"):
        raise ValueError("mixture requires mono PCM16 at 12000 Hz")
    if params.nframes <= 0 or len(a) != 2 * params.nframes:
        raise ValueError("truncated first mixture component")
    with wave.open(str(second), "rb") as reader:
        if reader.getparams() != params:
            raise ValueError("mixture component formats differ")
        b = reader.readframes(reader.getnframes())
    if len(b) != 2 * params.nframes:
        raise ValueError("truncated second mixture component")
    if len(gains) != 2 or not all(math.isfinite(g) for g in gains):
        raise ValueError("invalid mixture gains")
    mixed = bytearray()
    for (x,), (y,) in zip(struct.iter_unpack("<h", a), struct.iter_unpack("<h", b)):
        # Preserve the explicitly reviewed normalized float64 operations and tie rule.
        value = round(32768 * (gains[0] * (x / 32768) + gains[1] * (y / 32768)))
        if not -32768 <= value <= 32767:
            raise ValueError("mixture would clip")
        mixed += struct.pack("<h", value)
    with wave.open(str(output), "wb") as writer:
        writer.setparams(params)
        writer.writeframes(mixed)


def load_oracle(directory):
    spec = importlib.util.spec_from_file_location("cr18_channel_oracle", directory / "independent-vector-tool/generate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    matrices = module.tables(directory / "protocol-data")
    return module, matrices


def generate(mode, exe, output, fixture_directory, expected_exe_hash):
    if sha(exe) != expected_exe_hash:
        raise ValueError("unverified simulator executable")
    output.mkdir(parents=True, exist_ok=False)
    declarations = json.loads(DECLARATIONS.read_text())["cases"]
    oracle, matrices = load_oracle(fixture_directory)
    records = []
    for case in (c for c in declarations if c["mode"] == mode):
        folder = output / case["id"]
        folder.mkdir()
        components = []
        for index, message in enumerate(case["known_expected_messages"]):
            work = folder / f"component-{index}"
            work.mkdir()
            freq = case["nominal_audio_hz"] if index == 0 else case["second_audio_hz"]
            command = [str(exe.resolve()), message, str(freq), str(case["nominal_dt_s"]),
                       str(case["watterson_frequency_spread_hz"]), str(case["watterson_path_delay_ms"]),
                       "1", str(case["snr_2500_db_argument"])]
            run = subprocess.run(command, cwd=work, capture_output=True, timeout=60, check=True)
            (work / "stdout.txt").write_bytes(run.stdout)
            (work / "stderr.txt").write_bytes(run.stderr)
            truth = parse_output(run.stdout.decode(), mode, message)
            independent = oracle.channel(truth["payload77"], mode, *matrices)
            expected_tones = independent["tones"] if mode == "ft8" else independent["tones"][1:-1]
            if truth["tones"] != expected_tones:
                raise ValueError("emitted tones differ from independent CRC/LDPC/Gray oracle")
            audio = work / "000000_000001.wav"
            checks = inspect_wav(audio, case["frames"])
            if case["scenario"] == "clean" or case["scenario"] == "overlap":
                if checks["first_nonzero_frame"] == 0 or checks["last_nonzero_frame"] == case["frames"]-1:
                    raise ValueError("unexpected clean waveform at circular-shift boundary")
            components.append({**truth, **checks, "command": command, "working_directory": str(work.resolve()),
                               "path": str(audio.resolve()), "stdout_sha256": sha(work/"stdout.txt"),
                               "stderr_sha256": sha(work/"stderr.txt")})
        final = output / (case["id"] + ".wav")
        if len(components) == 1:
            final.write_bytes(pathlib.Path(components[0]["path"]).read_bytes())
        else:
            mix_pcm(components[0]["path"], components[1]["path"], final, case["mix_gains"])
        records.append({**case, **inspect_wav(final, case["frames"]), "filename": final.name,
                        "components": components, "normalized_message_changed": False,
                        "seed_value": None, "seed_reason": "standard sgran uses OS entropy/time/PID",
                        "clipping_warning": False,
                        "fullscale_interpretation": "clean source normalizes to32766.9 before nearest rounding; fullscale integer alone is not clipping"})
    manifest = {"schema": 1, "source_revision": REVISION, "mode": mode, "simulator_sha256": sha(exe),
                "generator_script_sha256": sha(__file__), "cases_declaration_sha256": sha(DECLARATIONS),
                "independent_oracle_sha256": sha(fixture_directory/"independent-vector-tool/generate.py"),
                "cases": records}
    write_json(output / "manifest.json", manifest)
    return manifest


def admit_hosted_ft8(raw, simulator, output, fixture_directory):
    """Admit exact hosted outputs; never execute the Linux simulator locally."""
    raw, simulator = pathlib.Path(raw), pathlib.Path(simulator)
    host = json.loads((raw/"raw-manifest.json").read_text())
    declared_bytes = DECLARATIONS.read_bytes()
    if (host["source_revision"] != REVISION or host["simulator_sha256"] != sha(simulator)
            or host["case_declaration_sha256"] not in declaration_hashes()):
        raise ValueError("hosted simulator/source/case identity differs")
    declarations = [c for c in json.loads(declared_bytes)["cases"] if c["mode"] == "ft8"]
    expected_keys = {(c["id"], i) for c in declarations for i in range(len(c["known_expected_messages"]))}
    keys = [(c["case"], c["index"]) for c in host["components"]]
    if len(keys) != len(expected_keys) or set(keys) != expected_keys:
        raise ValueError("missing, duplicate or unexpected hosted components")
    oracle, matrices = load_oracle(fixture_directory)
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for case in declarations:
        components = []
        for index, message in enumerate(case["known_expected_messages"]):
            entry = next(c for c in host["components"] if (c["case"], c["index"]) == (case["id"], index))
            source = raw/case["id"]/f"component-{index}"
            freq = case["nominal_audio_hz"] if index == 0 else case["second_audio_hz"]
            wanted_args = [message, str(freq), str(case["nominal_dt_s"]),
                           str(case["watterson_frequency_spread_hz"]), str(case["watterson_path_delay_ms"]),
                           "1", str(case["snr_2500_db_argument"])]
            if entry["command"][1:] != wanted_args:
                raise ValueError("hosted command differs from declared signal")
            if set(entry["hashes"]) != {"000000_000001.wav", "stdout.txt", "stderr.txt"}:
                raise ValueError("incomplete hosted evidence")
            for name, expected in entry["hashes"].items():
                if sha(source/name) != expected:
                    raise ValueError("hosted evidence hash differs")
            truth = parse_output((source/"stdout.txt").read_text(), "ft8", message)
            if truth["tones"] != oracle.channel(packed_message(message), "ft8", *matrices)["tones"]:
                raise ValueError("hosted tones differ from independent channel oracle")
            checks = inspect_wav(source/"000000_000001.wav", case["frames"])
            if case["scenario"] in ("clean", "overlap") and (
                    checks["first_nonzero_frame"] == 0 or checks["last_nonzero_frame"] == case["frames"]-1):
                raise ValueError("unexpected clean waveform at circular-shift boundary")
            folder = output/case["id"]/f"component-{index}"
            folder.mkdir(parents=True)
            for name in entry["hashes"]:
                shutil.copyfile(source/name, folder/name)
            components.append({**truth, **checks, "command": entry["command"],
                               "working_directory": f"reference-output/cr18-ft8-components/{case['id']}/component-{index}",
                               "working_directory_basis": "relative to hosted workspace, prescribed by generation command",
                               "path": str((folder/"000000_000001.wav").resolve()),
                               "stdout_sha256": sha(folder/"stdout.txt"), "stderr_sha256": sha(folder/"stderr.txt")})
        final = output/(case["id"]+".wav")
        if len(components) == 1:
            shutil.copyfile(components[0]["path"], final)
        else:
            mix_pcm(components[0]["path"], components[1]["path"], final, case["mix_gains"])
        records.append({**case, **inspect_wav(final, case["frames"]), "filename": final.name,
                        "components": components, "normalized_message_changed": False,
                        "seed_value": None, "seed_reason": host["seed_reason"], "clipping_warning": False,
                        "fullscale_interpretation": "upstream32766.9 normalization before nearest rounding; integer fullscale alone is not clipping"})
    manifest = {"schema": 1, "mode": "ft8", "source_revision": REVISION,
                "simulator_sha256": sha(simulator), "generator_script_sha256": sha(__file__),
                "cases_declaration_sha256": sha(DECLARATIONS),
                "independent_oracle_sha256": sha(fixture_directory/"independent-vector-tool/generate.py"),
                "hosted_raw_manifest_sha256": sha(raw/"raw-manifest.json"),
                "hosted_declaration_sha256": host["case_declaration_sha256"],
                "hosted_declaration_difference": "CRLF/LF normalization only",
                "hosted_generator_sha256": host["generator_sha256"],
                "data_origin": "upstream Fortran simulator built/run in GitHub Actions; local independent admission/mixing",
                "cases": records}
    write_json(output/"manifest.json", manifest)
    verify_manifest(output/"manifest.json", fixture_directory)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["ft8", "ft4"])
    parser.add_argument("--simulator", type=pathlib.Path)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--verify-manifest", type=pathlib.Path)
    parser.add_argument("--admit-hosted-ft8", type=pathlib.Path)
    parser.add_argument("--fixture-directory", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.verify_manifest:
        result = verify_manifest(args.verify_manifest, args.fixture_directory)
    elif args.admit_hosted_ft8:
        if not args.simulator or not args.output:
            parser.error("hosted admission requires --simulator and --output")
        result = admit_hosted_ft8(args.admit_hosted_ft8, args.simulator, args.output, args.fixture_directory)
    else:
        if not all((args.mode, args.simulator, args.expected_sha256, args.output)):
            parser.error("generation requires --mode, --simulator, --expected-sha256 and --output")
        result = generate(args.mode, args.simulator, args.output, args.fixture_directory, args.expected_sha256)
    print(json.dumps(result, indent=2))
