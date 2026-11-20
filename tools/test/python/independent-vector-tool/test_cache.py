"""Independent fixture-cache integrity checks; no decoder or hardware is used."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
import cache


class CacheIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='wstx-input-integrity-')
        cls.root = Path(cls.temporary.name)
        cls.recipe = cache.recipes('quality')[0]
        record = cache.compose((str(cls.root), cls.recipe))
        assert record['wav_sha256'] == cls.recipe[2]
        cls.original = cls.root/cls.recipe[0]

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.directory = self.root/self.id().split('.')[-1]
        shutil.copytree(self.original, self.directory)
        self.metadata = self.directory/'fixture.json'

    def test_pcm_and_adjacent_hash_cannot_be_changed_together(self):
        pcm = self.directory/'000000_000000.wav'
        altered = bytearray(pcm.read_bytes())
        altered[100] ^= 1
        pcm.write_bytes(altered)
        metadata = json.loads(self.metadata.read_text(encoding='utf-8'))
        metadata['wav_sha256'] = hashlib.sha256(altered).hexdigest()
        self.metadata.write_text(json.dumps(metadata), encoding='utf-8')
        with self.assertRaisesRegex(AssertionError, 'frozen waveform hash'):
            cache.check(self.directory, self.recipe)

    def test_another_recipe_is_refused(self):
        metadata = json.loads(self.metadata.read_text(encoding='utf-8'))
        metadata['case']['seed'] += 1
        self.metadata.write_text(json.dumps(metadata), encoding='utf-8')
        with self.assertRaisesRegex(AssertionError, 'recipe changed'):
            cache.check(self.directory, self.recipe)

    def test_another_composer_is_refused(self):
        metadata = json.loads(self.metadata.read_text(encoding='utf-8'))
        metadata['generator_sha256'] = '0'*64
        self.metadata.write_text(json.dumps(metadata), encoding='utf-8')
        with self.assertRaisesRegex(AssertionError, 'composer changed'):
            cache.check(self.directory, self.recipe)


if __name__ == '__main__':
    unittest.main()
