"""Build and verify independently composed modem inputs; never executes the Rust decoder."""
from __future__ import annotations
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time
import wave

FIXTURES = Path(__file__).resolve().parents[1]
COMPOSER = Path(__file__).with_name('generate.py')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def recipes(kind):
    if kind == 'quality':
        document = json.loads((FIXTURES/'quality-cases.json').read_text(encoding='utf-8-sig'))
        assert document['generator_sha256'] == digest(COMPOSER)
        return [(case['id'], case, None) for case in document['cases']]
    document = json.loads((FIXTURES/'independent-vectors/manifest.json').read_text(encoding='utf-8-sig'))
    result = []
    for vector in document['vectors']:
        w = vector['waveform']
        case = dict(rate_hz=12000, frames=w['frames'], noise_std=0, signals=[dict(
            mode=vector['mode'], payload77=vector['payload77'], start_frame=w['start_frame'],
            frequency_hz=w['frequency_hz'], amplitude=w['amplitude'], phase_radians=w['phase_radians'])])
        result.append((vector['mode']+'-'+vector['id'], case, w['sha256']))
    return result


def check(directory, recipe):
    name, case, frozen_sha = recipe
    metadata = json.loads((directory/'fixture.json').read_text(encoding='utf-8-sig'))
    assert metadata['case'] == case, f'{name}: recipe changed'
    assert metadata['generator_sha256'] == digest(COMPOSER), f'{name}: composer changed'
    wav = directory/'000000_000000.wav'
    sha = digest(wav)
    assert sha == metadata['wav_sha256'], f'{name}: PCM changed'
    if frozen_sha is not None:
        assert sha == frozen_sha, f'{name}: differs from frozen waveform hash'
    with wave.open(str(wav), 'rb') as audio:
        assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getnframes()) == (
            1, 2, 12000, case['frames']), f'{name}: format changed'
    return dict(id=name, wav_sha256=sha, frames=case['frames'])


def compose(task):
    output, recipe = task
    output = Path(output)
    name = recipe[0]
    target = output/name
    if target.exists():
        return check(target, recipe)
    pending = Path(tempfile.mkdtemp(prefix=name+'.pending-', dir=output))
    try:
        spec = importlib.util.spec_from_file_location('independent_composer', COMPOSER)
        composer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(composer)
        composer.generate(recipe[1], pending, FIXTURES/'protocol-data')
        record = check(pending, recipe)
        os.replace(pending, target)
        return record
    finally:
        if pending.exists():
            shutil.rmtree(pending)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=['frozen', 'quality'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--workers', type=int, default=4, choices=range(1, 9))
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    assert not output.is_relative_to(FIXTURES), 'generated audio belongs outside tracked fixtures'
    cases = recipes(args.kind)
    assert len(cases) == (38 if args.kind == 'frozen' else 2286)
    if args.verify_only:
        records = [check(output/recipe[0], recipe) for recipe in cases]
    else:
        output.mkdir(parents=True, exist_ok=True)
        lock = output.with_name(output.name+'.generation-lock')
        deadline = time.monotonic()+600
        while True:
            try:
                lock.mkdir()
                break
            except FileExistsError:
                if time.monotonic()>deadline:
                    raise RuntimeError(f'another fixture producer holds {lock}; inspect its process')
                time.sleep(0.2)
        try:
            with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
                records = list(pool.map(compose, ((str(output), recipe) for recipe in cases), chunksize=4))
        finally:
            lock.rmdir()
    manifest = dict(kind=args.kind, composer_sha256=digest(COMPOSER), inputs='independent fixed recipes; not decoder outcomes', cases=records)
    manifest_sha = hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    print(json.dumps(dict(kind=args.kind, cases=len(records), manifest_sha256=manifest_sha, output=str(output))))


if __name__ == '__main__':
    main()
