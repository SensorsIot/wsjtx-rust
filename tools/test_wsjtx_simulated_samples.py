"""Proves CL-007-03/04; TC-004-003 fixture arithmetic/refusal subcases."""
import hashlib, math, pathlib, struct, tempfile, unittest, wave
from wsjtx_simulated_samples import inspect_wav, mix_pcm, packed_message, sha, verify_frozen_wav


def audio(path, values):
    with wave.open(str(path), "wb") as out:
        out.setparams((1, 2, 12000, 0, "NONE", "not compressed"))
        out.writeframes(struct.pack("<" + "h" * len(values), *values))


class FixtureArithmetic(unittest.TestCase):
    def test_one_changed_sample_refused_even_when_pcm_shape_remains_valid(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=pathlib.Path(tmp)/"a.wav";audio(path,[0,0,0,0]);expected=sha(path)
            verify_frozen_wav(path,4,expected)
            changed=bytearray(path.read_bytes());changed[-2]=1;path.write_bytes(changed)
            self.assertEqual(inspect_wav(path,4)["frames"],4)
            with self.assertRaisesRegex(ValueError,"hash mismatch"):
                verify_frozen_wav(path,4,expected)

    def test_standard_payload_matches_existing_independent_cq_vector(self):
        self.assertEqual(packed_message("CQ K1ABC FN42"),
            "00000000000000000000000000100000010011011110111100011010100010100001100110001")

    def test_round_ties_even_preserves_scale_and_signed_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp); a, b, out = [root / n for n in ("a.wav", "b.wav", "out.wav")]
            audio(a, [1, 3, -1, -3]); audio(b, [0]*4)
            mix_pcm(a, b, out, [.5, 0])
            with wave.open(str(out), "rb") as reader:
                self.assertEqual(struct.unpack("<4h", reader.readframes(4)), (0, 2, 0, -2))

    def test_clipping_and_nonfinite_mixture_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp); a,b,out=[root/n for n in ("a.wav","b.wav","out.wav")]
            audio(a, [32767]); audio(b, [32767])
            for gains in ([1, 1], [float("nan"), 0], [float("inf"), 0]):
                with self.subTest(gains=gains), self.assertRaises(ValueError):
                    mix_pcm(a, b, out, gains)

    def test_format_length_and_truncated_pcm_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=pathlib.Path(tmp)/"a.wav";audio(path,[0]*4)
            self.assertEqual(inspect_wav(path,4)["frames"],4)
            with self.assertRaises(ValueError): inspect_wav(path,5)
            path.write_bytes(path.read_bytes()[:-1])
            with self.assertRaises(ValueError): inspect_wav(path,4)

    def test_mixer_refuses_actual_short_pcm_despite_matching_headers(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);a,b,out=[root/n for n in ("a.wav","b.wav","out.wav")]
            audio(a,[1,2,3,4]);audio(b,[5,6,7,8])
            b.write_bytes(b.read_bytes()[:-4])
            with self.assertRaisesRegex(ValueError,"truncated"):
                mix_pcm(a,b,out,[.25,.125])


"""Proves CL-007-03/04: mutation tests on the actual frozen CR18 FT4 sample set."""
import copy, json, os, pathlib, shutil, tempfile, unittest
from wsjtx_simulated_samples import verify_manifest

STORE=pathlib.Path(os.environ.get("WSTX_SIMULATOR_SAMPLE_DIR",
                                 str(pathlib.Path(__file__).resolve().parent.parent/"fixtures/decoder/simulator-samples/ft4")))
ORACLE=pathlib.Path(os.environ.get("WSTX_SIMULATOR_ORACLE_DIR",STORE.parent/"oracle"))


class ActualManifestIntegrity(unittest.TestCase):
    def test_actual_frozen_set_is_admitted(self):
        self.assertEqual(verify_manifest(STORE/"manifest.json",ORACLE),{"mode":"ft4","verified":4})

    def test_wrong_mode_source_schema_or_declarations_are_refused(self):
        original=json.loads((STORE/"manifest.json").read_text())
        for field,value in [("mode","ft8"),("schema",999),("source_revision","wrong"),
                            ("cases_declaration_sha256","0"*64)]:
            with self.subTest(field=field),tempfile.TemporaryDirectory() as tmp:
                root=pathlib.Path(tmp)
                for case in original["cases"]:
                    shutil.copyfile(STORE/case["filename"],root/case["filename"])
                    shutil.copytree(STORE/case["id"],root/case["id"])
                changed=copy.deepcopy(original);changed[field]=value
                (root/"manifest.json").write_text(json.dumps(changed))
                with self.assertRaises(ValueError):verify_manifest(root/"manifest.json",ORACLE)

    def test_changed_component_truth_or_missing_station_is_refused(self):
        original=json.loads((STORE/"manifest.json").read_text())
        for field in ("payload77","emitted_bits77","tones","message","missing-second-station"):
            with self.subTest(field=field),tempfile.TemporaryDirectory() as tmp:
                root=pathlib.Path(tmp)
                for case in original["cases"]:
                    shutil.copyfile(STORE/case["filename"],root/case["filename"])
                    shutil.copytree(STORE/case["id"],root/case["id"])
                changed=copy.deepcopy(original)
                if field=="missing-second-station":changed["cases"][-1]["components"].pop()
                elif field=="message":changed["cases"][0]["components"][0][field]="CQ WRONG FN42"
                else:
                    vector=changed["cases"][0]["components"][0][field]
                    changed["cases"][0]["components"][0][field]=("1" if vector[0]=="0" else "0")+vector[1:]
                (root/"manifest.json").write_text(json.dumps(changed))
                with self.assertRaises(ValueError):verify_manifest(root/"manifest.json",ORACLE)


class LiteralFilenameAdmission(unittest.TestCase):
    """Proves TC-004-003: valid bytes cannot authorize another final-WAV name."""

    def check_filename(self, mode, variant):
        from unittest import mock
        import wsjtx_simulated_samples as simulator
        with tempfile.TemporaryDirectory(prefix="cr18-filename-") as tmp:
            root = pathlib.Path(tmp)
            dataset = root / mode
            shutil.copytree(STORE.parent / mode, dataset)
            manifest_path = dataset / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            case = next(c for c in manifest["cases"] if c["id"] == f"SIM18-{mode.upper()}-CLEAN")
            basename = case["id"] + ".wav"
            self.assertEqual(case["filename"], basename)
            valid = dataset / basename
            self.assertEqual(hashlib.sha256(valid.read_bytes()).hexdigest(), case["sha256"])
            if variant == "absolute":
                case["filename"] = str(valid.resolve())
            elif variant == "escape":
                shutil.copyfile(valid, root / basename)
                case["filename"] = "../" + basename
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            final_reads = []
            original_reader = simulator.verify_frozen_wav

            def reader_spy(path, frames, expected_sha256):
                if pathlib.Path(path).name == basename:
                    final_reads.append(str(path))
                return original_reader(path, frames, expected_sha256)

            with mock.patch.object(simulator, "verify_frozen_wav", side_effect=reader_spy):
                if variant == "exact":
                    self.assertEqual(simulator.verify_manifest(manifest_path, ORACLE),
                                     {"mode": mode, "verified": 4})
                    self.assertEqual(len(final_reads), 1)
                else:
                    with self.assertRaisesRegex(ValueError, "filename"):
                        simulator.verify_manifest(manifest_path, ORACLE)
                    self.assertEqual(final_reads, [], "refused filename reached final-WAV reader")

    def test_ft4_exact(self): self.check_filename("ft4", "exact")
    def test_ft4_absolute(self): self.check_filename("ft4", "absolute")
    def test_ft4_escape(self): self.check_filename("ft4", "escape")
    def test_ft8_exact(self): self.check_filename("ft8", "exact")
    def test_ft8_absolute(self): self.check_filename("ft8", "absolute")
    def test_ft8_escape(self): self.check_filename("ft8", "escape")


if __name__ == "__main__": unittest.main()
