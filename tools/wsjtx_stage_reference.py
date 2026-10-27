"""Run pinned source-built codec diagnostics without changing numerical settings."""
import argparse
import json
import pathlib

import wsjtx_reference as reference


def check_identity(original, traced):
    if original.get("source_revision") != reference.REVISION or traced.get("source_revision") != reference.REVISION:
        raise ValueError("Unexpected reference source revision")
    left = {case["id"]: case for case in original["cases"]}
    right = {case["id"]: case for case in traced["cases"]}
    if set(left) != set(right) or set(left) != {case["id"] for case in reference.CASES}:
        raise ValueError("Different or incomplete original/instrumented case catalogue")
    for case_id in left:
        for field in ("mode", "input_sha256", "pcm_sha256", "frames", "configure", "request_sha256", "rows", "events", "stdout_sha256"):
            if left[case_id][field] != right[case_id][field]:
                raise ValueError(f"Instrumentation changed {case_id}: {field}")
    return {"source_revision": reference.REVISION, "same_stdout_and_decoded_observations": True,
            "cases": [{"id": key, "rows": len(left[key]["rows"]),
                       "input_sha256": left[key]["input_sha256"],
                       "stdout_sha256": left[key]["stdout_sha256"]} for key in left],
            "scope": "These two pinned recordings only, not a universal numerical equivalence proof"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run")
    run.add_argument("--exe", type=pathlib.Path, required=True)
    run.add_argument("--expected-sha256", required=True)
    run.add_argument("--inputs", type=pathlib.Path, required=True)
    run.add_argument("--output", type=pathlib.Path, required=True)
    run.add_argument("--source-revision", required=True, choices=(reference.REVISION,))
    run.add_argument("--instrumented", action="store_true")
    compare = commands.add_parser("identity")
    compare.add_argument("--original", type=pathlib.Path, required=True)
    compare.add_argument("--traced", type=pathlib.Path, required=True)
    compare.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.command == "run":
        document = reference.run_codec(args.exe, args.inputs, args.output, 3, False,
                                      expected_sha256=args.expected_sha256,
                                      binary_provenance="Selected hosted diagnostic source build; " +
                                      ("instrumented stderr logging" if args.instrumented else "unmodified upstream"))
        document["source_revision"] = args.source_revision
        document["instrumented"] = args.instrumented
        reference.write_json(args.output / "reference.json", document)
    else:
        original = json.loads(args.original.read_text(encoding="utf-8"))
        traced = json.loads(args.traced.read_text(encoding="utf-8"))
        reference.write_json(args.output, check_identity(original, traced))


if __name__ == "__main__":
    main()
