#!/usr/bin/env python3
"""Tests execute the SAME C source linked into the iOS dylib, through ctypes."""
from __future__ import annotations
import ctypes as C
import json
import math
from pathlib import Path
import tempfile
import unittest
from native_build import build_library, unload_library

ROOT = Path(__file__).resolve().parents[1]
CONV = '11111111-1111-4111-8111-111111111111'
USER = '22222222-2222-4222-8222-222222222222'
CALL = '33333333-3333-4333-8333-333333333333'
TEMP = tempfile.TemporaryDirectory(prefix='snapnotify-tests-')
LIB = build_library(TEMP.name, 'core', ROOT / 'Core/SNCore.c',
                    ['sn_uuid', 'sn_decode_records', 'sn_decode_call',
                     'sn_presence_update', 'sn_ledger_reserve', 'sn_ledger_commit',
                     'sn_ledger_cancel', 'sn_ledger_mark'])
lib = C.CDLL(str(LIB))

def tearDownModule():
    unload_library(lib)
    TEMP.cleanup()

class Bytes(C.Structure):
    _fields_ = [('data', C.POINTER(C.c_uint8)), ('size', C.c_size_t)]
class Record(C.Structure):
    _fields_ = [('topic', C.c_char * 65), ('payload', Bytes)]
class Call(C.Structure):
    _fields_ = [('action', C.c_int), ('conversation', C.c_char * 37),
                ('sender', C.c_char * 37), ('call', C.c_char * 37),
                ('video', C.c_bool), ('skip_ringing', C.c_bool)]
class Presence(C.Structure):
    _fields_ = [('active', C.c_bool), ('observed', C.c_bool), ('notified', C.c_bool),
                ('last_activity', C.c_double), ('last_notification', C.c_double),
                ('session', C.c_uint64)]
class Entry(C.Structure):
    _fields_ = [('key', C.c_char * 384), ('ticket', C.c_uint64),
                ('expires', C.c_double), ('occupied', C.c_bool), ('committed', C.c_bool)]
class Ledger(C.Structure):
    _fields_ = [('entries', Entry * 512), ('serial', C.c_uint64)]
lib.sn_uuid.argtypes = [C.c_char_p, C.c_size_t, C.c_char_p]
lib.sn_uuid.restype = C.c_bool
lib.sn_decode_records.argtypes = [Bytes, C.POINTER(Record), C.POINTER(C.c_size_t)]
lib.sn_decode_records.restype = C.c_bool
lib.sn_decode_call.argtypes = [Bytes, C.POINTER(Call)]
lib.sn_decode_call.restype = C.c_bool
lib.sn_presence_update.argtypes = [C.POINTER(Presence), C.c_bool, C.c_double, C.c_double, C.c_double]
lib.sn_presence_update.restype = C.c_int
lib.sn_ledger_reserve.argtypes = [C.POINTER(Ledger), C.c_char_p, C.c_double, C.c_double]
lib.sn_ledger_reserve.restype = C.c_uint64
lib.sn_ledger_commit.argtypes = [C.POINTER(Ledger), C.c_uint64, C.c_double, C.c_double]
lib.sn_ledger_commit.restype = C.c_bool
lib.sn_ledger_cancel.argtypes = [C.POINTER(Ledger), C.c_uint64]
lib.sn_ledger_cancel.restype = None
lib.sn_ledger_mark.argtypes = [C.POINTER(Ledger), C.c_char_p, C.c_double, C.c_double]
lib.sn_ledger_mark.restype = None

def span(raw: bytes):
    backing = (C.c_uint8 * len(raw)).from_buffer_copy(raw)
    return Bytes(backing, len(raw)), backing

def varint(n: int) -> bytes:
    out = bytearray()
    while n > 127:
        out.append((n & 127) | 128); n >>= 7
    out.append(n)
    return bytes(out)

def field(n: int, value: bytes) -> bytes:
    return varint((n << 3) | 2) + varint(len(value)) + value

def batch(topic: str, payload: bytes) -> bytes:
    return field(1, field(1, topic.encode()) + field(2, payload))

def call_payload(**kwargs) -> bytes:
    data = dict(messageType='CALLER_PUSH', callAction='START', callUuid=CALL,
                media='audio_video', skipRinging=False)
    data.update(kwargs)
    return envelope(json.dumps(data, separators=(',', ':')).encode())

def envelope(raw_json: bytes, conv: str = CONV, uid: str = USER) -> bytes:
    return field(2, conv.encode()) + field(3, uid.encode()) + field(5, raw_json)

def decode_records(raw: bytes):
    s, backing = span(raw)
    out = (Record * 64)(); count = C.c_size_t(999)
    ok = lib.sn_decode_records(s, out, C.byref(count))
    return ok, [(out[i].topic.decode(), C.string_at(out[i].payload.data, out[i].payload.size))
                for i in range(count.value)], count.value

def decode_call(raw: bytes):
    s, backing = span(raw); out = Call()
    return bool(lib.sn_decode_call(s, C.byref(out))), out

def step(p: Presence, active: bool, time: float, idle: float = 8, gap: float = 1.5):
    return lib.sn_presence_update(C.byref(p), active, time, idle, gap)

class UUIDTests(unittest.TestCase):
    def norm(self, value: bytes):
        out = C.create_string_buffer(37)
        return lib.sn_uuid(value, len(value), out), out.value
    def test_uppercase_normalized(self):
        raw = b'ABCD1234-ABCD-4321-ABCD-123456ABCDEF'
        self.assertEqual(self.norm(raw), (True, raw.lower()))
    def test_invalid_ids(self):
        for value in [b'', b'0'*36, b'00000000-0000-0000-0000-000000000000',
                      CONV.encode()+b'x', b'Optional('+CONV.encode()+b')', b'Z'+CONV.encode()[1:]]:
            with self.subTest(value=value): self.assertFalse(self.norm(value)[0])

class WireTests(unittest.TestCase):
    def test_real_shape(self):
        ok, records, n = decode_records(batch('volatile', call_payload()))
        self.assertTrue(ok); self.assertEqual(n, 1); self.assertEqual(records[0][0], 'volatile')
    def test_multiple_records(self):
        self.assertEqual(decode_records(batch('presence', b'')+batch('volatile', call_payload()))[2], 2)
    def test_unknown_outer_fields(self):
        self.assertTrue(decode_records(field(99,b'opaque')+batch('presence',b'x'))[0])
    def test_no_keyword_search(self):
        ok, records, _ = decode_records(batch('volatile', b'presence message snap typing'))
        self.assertTrue(ok); self.assertEqual(records[0][0], 'volatile')
    def test_malformed_batch_transactional(self):
        good = batch('presence', b'abc')
        ok, records, n = decode_records(good+b'\x0a\xff')
        self.assertFalse(ok); self.assertEqual(records, []); self.assertEqual(n, 0)
    def test_all_truncations(self):
        p = batch('volatile', call_payload())
        for i in range(len(p)):
            self.assertFalse(decode_records(p[:i])[0], i)
    def test_duplicate_record_fields(self):
        self.assertFalse(decode_records(field(1, field(1,b'volatile')+field(1,b'presence')+field(2,b'x')))[0])
    def test_bad_tags_and_overflow(self):
        for raw in [b'\x00', b'\x0b', b'\x0a'+b'\xff'*10, b'\x0a\x05xx', b'\xff'*12,
                    b'\x0dxx', b'\x09xx']:
            with self.subTest(raw=raw): self.assertFalse(decode_records(raw)[0])
    def test_bounded_records(self):
        self.assertTrue(decode_records(batch('presence',b'')*64)[0])
        self.assertFalse(decode_records(batch('presence',b'')*65)[0])
    def test_oversize_packet(self):
        self.assertFalse(decode_records(b'x'*(1024*1024+1))[0])
    def test_invalid_topic(self):
        self.assertFalse(decode_records(batch('call\x00snap',b'x'))[0])

class CallTests(unittest.TestCase):
    def test_start(self):
        ok, c = decode_call(call_payload())
        self.assertTrue(ok); self.assertEqual(c.action,1); self.assertEqual(c.sender.decode(),USER)
        self.assertEqual(c.conversation.decode(),CONV); self.assertEqual(c.call.decode(),CALL); self.assertTrue(c.video)
    def test_stop_is_not_start(self):
        ok, c = decode_call(call_payload(callAction='STOP'))
        self.assertTrue(ok); self.assertEqual(c.action,2)
    def test_streamer_is_not_message_or_call(self):
        self.assertFalse(decode_call(call_payload(messageType='STREAMER_DATA_VC2'))[0])
    def test_wrong_type_with_call_word(self):
        self.assertFalse(decode_call(call_payload(messageType='CHAT_MESSAGE', text='CALLER_PUSH START'))[0])
    def test_unknown_action(self):
        self.assertFalse(decode_call(call_payload(callAction='JOIN'))[0])
    def test_silent_call_explicit(self):
        ok,c=decode_call(call_payload(skipRinging=True)); self.assertTrue(ok); self.assertTrue(c.skip_ringing)
    def test_missing_ring_policy(self):
        d=dict(messageType='CALLER_PUSH',callAction='START',callUuid=CALL)
        self.assertFalse(decode_call(envelope(json.dumps(d).encode()))[0])
    def test_string_boolean_is_invalid(self):
        self.assertFalse(decode_call(call_payload(skipRinging='false'))[0])
    def test_invalid_uuid(self):
        self.assertFalse(decode_call(call_payload(callUuid='not-a-uuid'))[0])
    def test_duplicate_json_semantic_key(self):
        j=json.dumps(dict(messageType='CALLER_PUSH',callAction='START',callUuid=CALL,skipRinging=False))[:-1]+',"callAction":"STOP"}'
        self.assertFalse(decode_call(envelope(j.encode()))[0])
    def test_nested_spoof_does_not_classify(self):
        self.assertFalse(decode_call(envelope(json.dumps(dict(nested=dict(messageType='CALLER_PUSH',callAction='START',callUuid=CALL))).encode()))[0])
    def test_valid_json_unicode_and_escaped_required_key(self):
        data=json.dumps(dict(messageType='CALLER_PUSH',callAction='START',callUuid=CALL,skipRinging=False,
                             ignored='João 日本語 😀',nested=[None,True,False,1,-1,2.3e9]))
        data=data.replace('CALLER_PUSH','CALLER\\u005fPUSH')
        self.assertTrue(decode_call(envelope(data.encode()))[0])
    def test_raw_utf8(self):
        self.assertTrue(decode_call(call_payload(ignored='João 日本語 😀'))[0])
        data=json.dumps(dict(messageType='CALLER_PUSH',callAction='START',callUuid=CALL,skipRinging=False, ignored='João'),ensure_ascii=False).encode()
        self.assertTrue(decode_call(envelope(data))[0])
    def test_json_failures(self):
        valid=json.dumps(dict(messageType='CALLER_PUSH',callAction='START',callUuid=CALL,skipRinging=False)).encode()
        for raw in [valid+b'x',valid[:-1]+b',}',valid.replace(b'false',b'False'),
                    valid.replace(b'false',b'null'),valid.replace(b'CALLER_PUSH',b'CALLER\x00PUSH'),
                    valid[:-1]+b',"x":"\xc0\xaf"}',valid[:-1]+b',"x":01}',
                    valid[:-1]+b',"x":"\\uD800"}',valid[:-1]+b',"x":1.}',
                    valid[:-1]+b',"x":'+b'['*18+b'0'+b']'*18+b'}']:
            with self.subTest(raw=raw): self.assertFalse(decode_call(envelope(raw))[0])
    def test_duplicate_envelope_fields(self):
        self.assertFalse(decode_call(call_payload()+field(2,CONV.encode()))[0])
    def test_permuted_envelope_fields(self):
        j=json.dumps(dict(messageType='CALLER_PUSH',callAction='START',callUuid=CALL,skipRinging=False)).encode()
        self.assertTrue(decode_call(field(5,j)+field(3,USER.encode())+field(2,CONV.encode()))[0])

class PresenceTests(unittest.TestCase):
    def test_first_and_duplicate(self):
        p=Presence(); self.assertEqual(step(p,True,0),1); self.assertEqual(step(p,True,0.001),0)
    def test_stop_then_restart(self):
        p=Presence();step(p,True,10);self.assertEqual(step(p,False,12),2);self.assertEqual(step(p,True,14),1)
    def test_two_minutes_later_without_stop(self):
        p=Presence();self.assertEqual(step(p,True,10),1);self.assertEqual(step(p,True,130),1)
        self.assertEqual(p.session,2)
    def test_no_periodic_spam_during_continuous_typing(self):
        p=Presence();self.assertEqual(step(p,True,0),1)
        for t in range(1,120): self.assertEqual(step(p,True,t),0)
    def test_missing_stop_expires(self):
        p=Presence();step(p,True,0);self.assertEqual(step(p,True,8),1)
    def test_bounce_is_rearmable(self):
        p=Presence();step(p,True,0);step(p,False,.1)
        self.assertEqual(step(p,True,.2),0);self.assertEqual(step(p,True,2),1)
    def test_two_users_are_independent(self):
        p,q=Presence(),Presence();self.assertEqual(step(p,True,0),1);self.assertEqual(step(q,True,0),1)
    def test_out_of_order_ignored(self):
        p=Presence();step(p,True,10);self.assertEqual(step(p,False,9),0);self.assertTrue(p.active)
    def test_invalid_time_and_configuration(self):
        for t,idle,gap in [(math.nan,8,1),(-1,8,1),(math.inf,8,1),(1,0,1),(1,8,-1)]:
            p=Presence();self.assertEqual(step(p,True,t,idle,gap),0);self.assertFalse(p.active)

class LedgerTests(unittest.TestCase):
    def setUp(self): self.l=Ledger()
    def reserve(self,key=b'call|one',now=0,ttl=15):return lib.sn_ledger_reserve(C.byref(self.l),key,now,ttl)
    def test_duplicate_does_not_extend_window(self):
        t=self.reserve();self.assertTrue(t);self.assertEqual(self.reserve(now=14),0);self.assertTrue(self.reserve(now=16))
    def test_distinct_snaps_from_same_sender(self):
        self.assertTrue(self.reserve(b'snap|same-convo|same-user|id-1'))
        self.assertTrue(self.reserve(b'snap|same-convo|same-user|id-2'))
    def test_failure_rollback(self):
        t=self.reserve();lib.sn_ledger_cancel(C.byref(self.l),t);self.assertTrue(self.reserve(now=.1))
    def test_success_commit(self):
        t=self.reserve();self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),t,1,300))
        self.assertEqual(self.reserve(now=120),0);self.assertTrue(self.reserve(now=302))
    def test_stop_tombstone(self):
        lib.sn_ledger_mark(C.byref(self.l),b'call|one',1,300);self.assertEqual(self.reserve(now=2),0)
    def test_old_callback_cannot_cancel_new_ticket(self):
        old=self.reserve();new=self.reserve(now=16);lib.sn_ledger_cancel(C.byref(self.l),old)
        self.assertEqual(self.reserve(now=17),0);self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),new,17,10))
    def test_invalid_keys_rejected_not_truncated(self):
        for key in [b'',b'x'*384,b'x'*1000]: self.assertEqual(self.reserve(key),0)
    def test_bounded_capacity(self):
        for i in range(2000):
            ticket=self.reserve(str(i).encode(),i,3000)
            self.assertTrue(ticket)
            self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),ticket,i,3000))
        self.assertEqual(sum(x.occupied for x in self.l.entries),512)
    def test_full_pending_ledger_rejects_new_instead_of_losing_ticket(self):
        tickets=[self.reserve(str(i).encode(),0,15) for i in range(512)]
        self.assertTrue(all(tickets))
        self.assertEqual(self.reserve(b'overflow',1,15),0)
        self.assertEqual(self.reserve(b'0',1,15),0)
        self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),tickets[0],1,300))
        self.assertTrue(self.reserve(b'overflow',2,15))
        self.assertEqual(self.reserve(b'1',2,15),0)
        self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),tickets[1],2,300))
    def test_pending_ticket_survives_pressure_from_completed_events(self):
        pending=self.reserve(b'pending',0,15)
        for i in range(511):
            ticket=self.reserve(str(i).encode(),0,15)
            self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),ticket,0,86400))
        self.assertTrue(self.reserve(b'new-event',1,15))
        self.assertEqual(self.reserve(b'pending',1,15),0)
        self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),pending,1,300))
    def test_stop_invalidates_inflight_start_ticket(self):
        ticket=self.reserve()
        lib.sn_ledger_mark(C.byref(self.l),b'call|one',1,300)
        lib.sn_ledger_cancel(C.byref(self.l),ticket)
        self.assertFalse(lib.sn_ledger_commit(C.byref(self.l),ticket,2,1))
        self.assertEqual(self.reserve(now=300),0)
        self.assertTrue(self.reserve(now=302))
    def test_completed_ticket_cannot_be_cancelled(self):
        ticket=self.reserve()
        self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),ticket,1,300))
        lib.sn_ledger_cancel(C.byref(self.l),ticket)
        self.assertEqual(self.reserve(now=2),0)
    def test_repeated_commit_cannot_shorten_dedup_window(self):
        ticket=self.reserve()
        self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),ticket,1,300))
        self.assertTrue(lib.sn_ledger_commit(C.byref(self.l),ticket,2,1))
        self.assertEqual(self.reserve(now=300),0)
    def test_expired_ticket_cannot_be_committed(self):
        ticket=self.reserve()
        self.assertFalse(lib.sn_ledger_commit(C.byref(self.l),ticket,15,300))
        self.assertTrue(self.reserve(now=16))
    def test_expired_call_not_permanent(self):
        t=self.reserve();lib.sn_ledger_commit(C.byref(self.l),t,0,300);self.assertTrue(self.reserve(now=301))

class ReplayTests(unittest.TestCase):
    def test_supplied_log_calls_replay_as_one_background_call_not_three_messages(self):
        fixtures=json.loads((ROOT/'tests/fixtures/volatile_sanitized.json').read_text())
        ledger=Ledger(); emitted=[]; decoded=0; ignored=0
        for frame in fixtures:
            ok,records,_=decode_records(bytes.fromhex(frame['hex']));self.assertTrue(ok)
            for topic,payload in records:
                self.assertEqual(topic,'volatile');ok,call=decode_call(payload)
                self.assertEqual(bool(ok),frame['expected']!='ignored')
                if not ok:ignored+=1;continue
                decoded+=1
                key=b'call|'+call.conversation+b'|'+call.sender+b'|'+call.call
                t=frame['seconds']
                if call.action==2:lib.sn_ledger_mark(C.byref(ledger),key,t,300);continue
                ticket=lib.sn_ledger_reserve(C.byref(ledger),key,t,15)
                if ticket:
                    lib.sn_ledger_commit(C.byref(ledger),ticket,t,300)
                    if frame['state']=='BG':emitted.append(call.call.decode())
        self.assertEqual(decoded,10);self.assertEqual(ignored,4);self.assertEqual(len(emitted),1)

if __name__=='__main__': unittest.main(verbosity=2)
