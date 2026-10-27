"""Generate raw upstream FT8 components; final admission/checks remain local."""
import argparse, hashlib, json, pathlib, subprocess


def generate(exe, declarations, output):
    exe, declarations = exe.resolve(), declarations.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = json.loads(declarations.read_text(encoding="utf-8"))
    components = []
    for case in source["cases"]:
        if case["mode"] != "ft8":
            continue
        for index, message in enumerate(case["known_expected_messages"]):
            work = output / case["id"] / f"component-{index}"
            work.mkdir(parents=True)
            freq = case["nominal_audio_hz"] if index == 0 else case["second_audio_hz"]
            command = [str(exe), message, str(freq), str(case["nominal_dt_s"]),
                       str(case["watterson_frequency_spread_hz"]), str(case["watterson_path_delay_ms"]),
                       "1", str(case["snr_2500_db_argument"])]
            run = subprocess.run(command, cwd=work, capture_output=True, timeout=60, check=True)
            (work/"stdout.txt").write_bytes(run.stdout)
            (work/"stderr.txt").write_bytes(run.stderr)
            hashes = {name: hashlib.sha256((work/name).read_bytes()).hexdigest()
                      for name in ("000000_000001.wav", "stdout.txt", "stderr.txt")}
            components.append({"case": case["id"], "index": index, "command": command, "hashes": hashes})
    if len(components) != 5:
        raise ValueError("expected exactly five FT8 components for four cases")
    manifest = {"source_revision": source["source_revision"], "phase": "raw generated components; not admitted fixtures",
                "simulator_sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
                "case_declaration_sha256": hashlib.sha256(declarations.read_bytes()).hexdigest(),
                "generator_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
                "seed_value": None, "seed_reason": "upstream OS entropy/time/PID, no exposed control",
                "components": components}
    (output/"raw-manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--exe", type=pathlib.Path, required=True)
    parser.add_argument("--cases", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args=parser.parse_args()
    print(json.dumps(generate(args.exe, args.cases, args.output), indent=2))
