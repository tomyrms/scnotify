#!/usr/bin/env python3
"""Execute the production presence wire decoder; fixtures are synthetic schema tests.

They verify parser behavior, not an on-device Snapchat 14.17.1 recording capture.
"""
from __future__ import annotations
import ctypes as C
from pathlib import Path
import tempfile
import unittest
from native_build import build_library, unload_library

ROOT = Path(__file__).resolve().parents[1]
CONV = '11111111-1111-4111-8111-111111111111'
USER = '22222222-2222-4222-8222-222222222222'
USER2 = '33333333-3333-4333-8333-333333333333'
TEMP = tempfile.TemporaryDirectory(prefix='snapnotify-presence-')
# Compile both unmodified production sources with the existing one-source helper.
WRAPPER = Path(TEMP.name) / 'presence_all.c'
WRAPPER.write_text(''.join('#include "' + (ROOT / path).as_posix() + '"\n'
                         for path in ['Core/SNCore.c', 'Core/SNPresenceWire.c']))
LIB = build_library(TEMP.name, 'presence_wire', WRAPPER, ['sn_decode_presence'])
lib = C.CDLL(str(LIB))


class Bytes(C.Structure):
    _fields_ = [('data', C.POINTER(C.c_uint8)), ('size', C.c_size_t)]


class Participant(C.Structure):
    _fields_ = [('uid', C.c_char * 37), ('flags', C.c_uint64)]


class Presence(C.Structure):
    _fields_ = [('conversation', C.c_char * 37), ('count', C.c_size_t),
                ('participants', Participant * 256)]


lib.sn_decode_presence.argtypes = [Bytes, C.POINTER(Presence)]
lib.sn_decode_presence.restype = C.c_bool


def tearDownModule():
    unload_library(lib)
    TEMP.cleanup()


def varint(value):
    out = bytearray()
    while value > 127:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def integer(number, value):
    return varint(number << 3) + varint(value)


def field(number, value):
    return varint((number << 3) | 2) + varint(len(value)) + value


def participant(flags=16, user=USER, session='device', extra=b''):
    return field(4, field(1, (user + ':' + session).encode()) +
                 field(2, integer(1, flags)) + extra)


def packet(*members, conversation=CONV):
    # Put conversation last so every nonempty prefix is invalid, making the
    # exhaustive truncation test meaningful even at protobuf field boundaries.
    return b''.join(members) + field(6, conversation.encode())


def decode(raw):
    backing = (C.c_uint8 * len(raw)).from_buffer_copy(raw)
    result = Presence()
    C.memset(C.byref(result), 0xa5, C.sizeof(result))
    ok = bool(lib.sn_decode_presence(Bytes(backing, len(raw)), C.byref(result)))
    return ok, result


class PresenceWireTests(unittest.TestCase):
    def reject(self, raw):
        ok, result = decode(raw)
        self.assertFalse(ok)
        self.assertEqual(bytes(result), bytes(C.sizeof(result)))

    def test_text_and_voice_bits_remain_distinct(self):
        for flags in [0, 16, 64, 80, 81, 272, 336, (1 << 64) - 1]:
            with self.subTest(flags=flags):
                ok, result = decode(packet(participant(flags)))
                self.assertTrue(ok)
                self.assertEqual(result.count, 1)
                self.assertEqual(result.participants[0].flags, flags)
                self.assertEqual(result.participants[0].uid.decode(), USER)
                self.assertEqual(result.conversation.decode(), CONV)

    def test_empty_participant_snapshot(self):
        ok, result = decode(packet())
        self.assertTrue(ok)
        self.assertEqual(result.count, 0)

    def test_two_distinct_users(self):
        ok, result = decode(packet(participant(16), participant(80, USER2)))
        self.assertTrue(ok)
        self.assertEqual(result.count, 2)
        self.assertEqual([result.participants[i].flags for i in range(2)], [16, 80])

    def test_uuid_case_normalized(self):
        uid = 'ABCDEFAB-ABCD-4BCD-8BCD-ABCDEFABCDEF'
        ok, result = decode(packet(participant(user=uid), conversation=uid))
        self.assertTrue(ok)
        self.assertEqual(result.conversation.decode(), uid.lower())
        self.assertEqual(result.participants[0].uid.decode(), uid.lower())

    def test_duplicate_users_same_flags_coalesced(self):
        ok, result = decode(packet(participant(80, session='one'), participant(80, session='two')))
        self.assertTrue(ok)
        self.assertEqual(result.count, 1)

    def test_conflicting_user_states_reject_entire_packet(self):
        self.reject(packet(participant(16), participant(80)))

    def test_unknown_fields_validated_and_skipped(self):
        extra = integer(9, 32) + field(10, b'future')
        ok, result = decode(extra + packet(participant(extra=extra)) + extra)
        self.assertTrue(ok)
        self.assertEqual(result.count, 1)

    def test_missing_conversation(self):
        self.reject(participant())

    def test_duplicate_conversation(self):
        self.reject(packet() + packet())

    def test_bad_conversations(self):
        for value in ['', CONV + ':device', CONV[:-1], '00000000-0000-0000-0000-000000000000', 'x' * 36]:
            with self.subTest(value=value):
                self.reject(packet(participant(), conversation=value))

    def test_wrong_known_field_wire_types(self):
        for raw in [integer(6, 0), integer(4, 0), field(4, integer(1, 0)),
                    field(4, field(1, (USER + ':d').encode()) + integer(2, 0))]:
            self.reject(packet(participant()) + raw)

    def test_missing_user_or_flags(self):
        for member in [b'', field(1, (USER + ':d').encode()), field(2, integer(1, 80)),
                       field(1, (USER + ':d').encode()) + field(2, b'')]:
            self.reject(packet(participant(), field(4, member)))

    def test_duplicate_user_or_state_fields(self):
        uid = field(1, (USER2 + ':d').encode())
        state = field(2, integer(1, 16))
        for body in [uid + uid + state, uid + state + state,
                     uid + field(2, integer(1, 16) + integer(1, 16))]:
            self.reject(packet(participant(), field(4, body)))

    def test_invalid_participant_keys(self):
        for value in [USER, USER + ':', USER + ':a\x00b', USER + ':a b',
                      USER + ':\n', USER + ':é', 'invalid:device', USER + ':' + 'd' * 220]:
            member = field(4, field(1, value.encode()) + field(2, integer(1, 80)))
            self.reject(packet(participant(), member))

    def test_every_truncation_rejected_without_partial_output(self):
        raw = packet(participant(16), participant(80, USER2))
        for length in range(len(raw)):
            with self.subTest(length=length):
                self.reject(raw[:length])

    def test_corrupt_tail_cannot_publish_valid_prefix(self):
        for tail in [b'\x80', b'\x00', b'\x12\xff\xff', b'\x1b', b'\x08' + b'\xff' * 10]:
            self.reject(packet(participant()) + tail)

    def test_nested_flag_overflow_and_wrong_type(self):
        for flags in [b'\x08' + b'\xff' * 10, field(1, b'80'), b'\x08\x80']:
            self.reject(packet(field(4, field(1, (USER + ':d').encode()) + field(2, flags))))

    def test_participant_limit(self):
        ok, result = decode(packet(*[participant() for _ in range(256)]))
        self.assertTrue(ok)
        self.assertEqual(result.count, 1)
        self.reject(packet(*[participant() for _ in range(257)]))

    def test_max_distinct_participants(self):
        members = [participant(user=f'{i + 1:08x}-1111-4111-8111-111111111111') for i in range(256)]
        ok, result = decode(packet(*members))
        self.assertTrue(ok)
        self.assertEqual(result.count, 256)

    def test_packet_and_field_limits(self):
        self.reject(packet(participant()) + field(20, b'x' * (1024 * 1024)))
        self.reject(packet(participant()) + integer(20, 0) * 4096)

    def test_null_arguments(self):
        result = Presence()
        C.memset(C.byref(result), 0xa5, C.sizeof(result))
        self.assertFalse(lib.sn_decode_presence(Bytes(None, 1), C.byref(result)))
        self.assertEqual(bytes(result), bytes(C.sizeof(result)))
        self.assertFalse(lib.sn_decode_presence(Bytes(None, 0), None))


if __name__ == '__main__':
    unittest.main()
