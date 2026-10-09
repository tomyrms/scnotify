#!/usr/bin/env python3
"""Generate the dylib's embedded notification audio from the checked-in PCM WAV."""
from pathlib import Path
import argparse
import hashlib
import io
import wave

ROOT = Path(__file__).resolve().parents[1]

def render(data):
    with wave.open(io.BytesIO(data), 'rb') as audio:
        if (audio.getcomptype() != 'NONE' or audio.getsampwidth() != 2
                or audio.getnchannels() not in (1, 2)
                or not 0 < audio.getnframes() / audio.getframerate() < 30):
            raise ValueError('Expected a PCM16 mono/stereo WAV shorter than 30 seconds')
    if len(data) > 1024 * 1024:
        raise ValueError('Embedded notification audio exceeds 1 MiB')
    digest = hashlib.sha256(data).hexdigest()
    lines = ['/* Generated from Resources/SnapchatNotification.wav; see docs/SOUND_RC9.md. */',
             '#ifndef SN_SNAPCHAT_SOUND_DATA_H', '#define SN_SNAPCHAT_SOUND_DATA_H',
             f'#define SN_SNAPCHAT_SOUND_FILENAME "snapnotify-snapchat-{digest[:12]}.wav"',
             'static const unsigned char SNSnapchatSoundBytes[] = {']
    lines += ['    ' + ','.join(f'0x{x:02x}' for x in data[i:i+16]) + ',' for i in range(0, len(data), 16)]
    return '\n'.join(lines + ['};', '#endif', ''])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    output = ROOT / 'Sources/SNSnapchatSoundData.h'
    expected = render((ROOT / 'Resources/SnapchatNotification.wav').read_bytes())
    if args.check:
        if output.read_text(encoding='utf-8') != expected:
            raise SystemExit('Embedded sound differs; run python3 scripts/embed_sound.py')
        print('Embedded notification sound matches the WAV resource')
    else:
        output.write_text(expected, encoding='utf-8', newline='\n')

if __name__ == '__main__':
    main()
