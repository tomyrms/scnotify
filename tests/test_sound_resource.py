"""Validate the actual alert audio and the bytes shipped in the dylib."""
import hashlib
import io
from pathlib import Path
import re
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]

class NotificationAudioTests(unittest.TestCase):
    def test_alert_is_supported_pcm_and_short_enough(self):
        with wave.open(str(ROOT / 'Resources/SnapchatNotification.wav'), 'rb') as audio:
            self.assertEqual(audio.getcomptype(), 'NONE')
            self.assertEqual(audio.getsampwidth(), 2)
            self.assertEqual(audio.getnchannels(), 2)
            self.assertEqual(audio.getframerate(), 44100)
            self.assertGreater(audio.getnframes(), 0)
            self.assertLess(audio.getnframes() / audio.getframerate(), 30)
            # Preserve the sample stream, without normalization or another chime.
            self.assertEqual(audio.getnframes(), 19536)

    def test_dylib_bytes_match_validated_resource(self):
        data = (ROOT / 'Resources/SnapchatNotification.wav').read_bytes()
        header = (ROOT / 'Sources/SNSnapchatSoundData.h').read_text()
        embedded = bytes(int(b, 16) for b in re.findall(r'0x([0-9a-f]{2})', header))
        self.assertEqual(embedded, data)
        digest = hashlib.sha256(data).hexdigest()
        self.assertIn(f'snapnotify-snapchat-{digest[:12]}.wav', header)

    def test_extracted_sound_provenance_is_stable(self):
        data = (ROOT / 'Resources/SnapchatNotification.wav').read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(),
                         '4f34eac8c53d24d151daaa0185a8053d0ae875c652b92560021a2434e9a2f0db')
