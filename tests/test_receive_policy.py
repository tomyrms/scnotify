"""Exercise the production C receive policy (not a Python reimplementation)."""
import ctypes as c
import math
from pathlib import Path
import tempfile
import unittest
from native_build import build_library, unload_library

ROOT = Path(__file__).resolve().parents[1]

class ReceivePolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        library = build_library(cls.tmp.name, 'policy', ROOT / 'Core/SNReceivePolicy.c',
                                ['sn_receive_kind', 'sn_receive_hint',
                                 'sn_receive_native_content_kind', 'sn_receive_source',
                                 'sn_receive_seconds', 'sn_receive_time_valid'])
        cls.lib = c.CDLL(str(library))
        for name in ('sn_receive_kind', 'sn_receive_hint'):
            f = getattr(cls.lib, name); f.argtypes = [c.c_char_p]; f.restype = c.c_int
        cls.lib.sn_receive_native_content_kind.argtypes = [c.c_char_p, c.c_char_p, c.c_int64]
        cls.lib.sn_receive_native_content_kind.restype = c.c_int
        cls.lib.sn_receive_source.argtypes = [c.c_char_p, c.c_char_p]
        cls.lib.sn_receive_source.restype = c.c_int
        cls.lib.sn_receive_seconds.argtypes = [c.c_double]
        cls.lib.sn_receive_seconds.restype = c.c_double
        cls.lib.sn_receive_time_valid.argtypes = [c.c_double, c.c_double]
        cls.lib.sn_receive_time_valid.restype = c.c_bool

    @classmethod
    def tearDownClass(cls):
        unload_library(cls.lib)
        cls.tmp.cleanup()


    def test_observed_native_content_type_one(self):
        # The device diagnostic reports this exact class and raw value 1.
        self.assertEqual(self.lib.sn_receive_native_content_kind(b'SCNMessagingMessageContent', b'14.17.1', 1), 1)

    def test_native_snap_zero_is_not_missing(self):
        self.assertEqual(self.lib.sn_receive_native_content_kind(b'SCNMessagingMessageContent', b'14.17.1', 0), 2)

    def test_native_numeric_version_boundary(self):
        for version in (None, b'', b'14.17.0', b'14.17.10', b'14.18.1', b'15.0.0'):
            for raw in (0, 1):
                with self.subTest(version=version, raw=raw):
                    self.assertEqual(self.lib.sn_receive_native_content_kind(b'SCNMessagingMessageContent', version, raw), 0)

    def test_native_class_boundary(self):
        for cls in (None, b'', b'Dictionary', b'SCNMessagingMessage', b'SCNMessagingReceiveMessageMetricsResult', b'SCNMessagingMessageContentOther'):
            self.assertEqual(self.lib.sn_receive_native_content_kind(cls, b'14.17.1', 1), 0)

    def test_native_unknown_numeric_types_not_guessed(self):
        for raw in (-2**63, -1, 2, 3, 4, 5, 6, 7, 42, 999, 2**63-1):
            self.assertEqual(self.lib.sn_receive_native_content_kind(b'SCNMessagingMessageContent', b'14.17.1', raw), 0)

    def test_metrics_are_not_message_callbacks(self):
        for selector in (b'onMessageReceived:', b'onMessagesReceived:'):
            self.assertEqual(self.lib.sn_receive_source(b'SCNativeBlizzardLoggerDelegateImpl', selector), 0)

    def test_actual_arroyo_callback_stays_snapshot(self):
        self.assertEqual(self.lib.sn_receive_source(b'SCArroyoConversationDataUpdateAnnouncer', b'onConversationUpdated:conversation:updatedMessages:removedMessages:'), 2)

    def test_numeric_types_remain_unmapped_outside_native_adapter(self):
        self.assertEqual(self.lib.sn_receive_kind(b'0'), 0)
        self.assertEqual(self.lib.sn_receive_kind(b'1'), 0)

    def test_chat_symbols(self):
        for name in ('CHAT', 'TEXT', 'CHAT_MESSAGE', 'RECEIVED_CHAT_MESSAGE', 'EXTERNAL_MEDIA', 'NOTE', 'STICKER'):
            with self.subTest(name=name): self.assertEqual(self.lib.sn_receive_kind(name.encode()), 1)

    def test_snap_symbols(self):
        for name in ('SNAP', 'RECEIVED_SNAP', 'SNAP_RECEIVED'):
            self.assertEqual(self.lib.sn_receive_kind(name.encode()), 2)

    def test_voice_symbols_are_messages(self):
        for name in ('AUDIO_NOTE', 'AUDIO_MESSAGE', 'VOICE_NOTE', 'VOICE_MESSAGE', 'VOICE_NOTE_MESSAGE'):
            for prefix in ('', 'CONTENT_TYPE_', 'MESSAGING_CONTENT_TYPE_'):
                with self.subTest(name=name, prefix=prefix):
                    self.assertEqual(self.lib.sn_receive_kind((prefix + name).encode()), 1)

    def test_voice_control_symbols_still_not_messages(self):
        for name in (b'VOICE_MESSAGE_PLAYED', b'VOICE_NOTE_READ', b'AUDIO_CALL', b'VOICE'):
            self.assertEqual(self.lib.sn_receive_kind(name), 0)

    def test_case(self):
        self.assertEqual(self.lib.sn_receive_kind(b'chat'), 1)
        self.assertEqual(self.lib.sn_receive_kind(b'Snap'), 2)

    def test_prefixes(self):
        for prefix in ('CONTENT_TYPE_', 'CONTENTTYPE_', 'MESSAGING_CONTENT_TYPE_'):
            self.assertEqual(self.lib.sn_receive_kind((prefix + 'SNAP').encode()), 2)

    def test_receipts_not_messages(self):
        for name in ('READ', 'READ_RECEIPT', 'DELIVERY_RECEIPT', 'DELIVERED', 'SNAP_OPENED', 'SNAP_STATE', 'STATUS_SAVED'):
            self.assertEqual(self.lib.sn_receive_kind(name.encode()), 3)

    def test_call_typing_presence_separate(self):
        for name in ('CALLER_PUSH', 'CALL_STARTED', 'PRESENCE', 'TYPING'):
            self.assertEqual(self.lib.sn_receive_kind(name.encode()), 3)

    def test_metadata_not_messages(self):
        for name in ('SAVE', 'UNSAVE', 'ERASE', 'DELETE', 'DELETED', 'REPLAY', 'SCREENSHOT', 'EDIT'):
            self.assertEqual(self.lib.sn_receive_kind(name.encode()), 3)

    def test_numeric_not_guessed(self):
        for name in (b'0', b'1', b'2', b'99', b'-1'):
            self.assertEqual(self.lib.sn_receive_kind(name), 0)

    def test_plain_words_not_enough(self):
        for name in (b'sync_trigger', b'hermod', b'contains_snap_somewhere', b'message', b'new snap received', b'typing then chat'):
            self.assertEqual(self.lib.sn_receive_kind(name), 0)

    def test_invalid_symbols(self):
        for name in (None, b'', b'a'*128, b'\xff', b'SNAP;', b'CHAT\n'):
            self.assertEqual(self.lib.sn_receive_kind(name), 0)

    def test_live_original(self):
        for selector in (b'didReceiveMessage:', b'didReceiveMessages:', b'didReceiveSnap:', b'didReceiveChatMessage:'):
            self.assertEqual(self.lib.sn_receive_source(b'SCMessageListener', selector), 1)

    def test_live_multi_arguments(self):
        self.assertEqual(self.lib.sn_receive_source(b'SCMessageListener', b'onMessagesReceived:conversation:metadata:completion:'), 1)
        self.assertEqual(self.lib.sn_receive_source(b'SCNMessagingListener', b'onMessagesReceived:metadata:'), 1)

    def test_separate_conversation(self):
        for selector in (b'conversation:didReceiveMessage:', b'conversationId:didReceiveMessages:'):
            self.assertEqual(self.lib.sn_receive_source(b'SCConversation', selector), 1)

    def test_snapshot_known_announcer(self):
        self.assertEqual(self.lib.sn_receive_source(b'SCChatConversationUpdaterListenerAnnouncer', b'didConversationViewModelChange:metricsTracker:'), 2)

    def test_snapshot_native_listener(self):
        for selector in (b'onConversationUpdated:', b'onMessageUpdated:', b'onMessagesUpdated:', b'onMessageAdded:', b'onNewMessages:'):
            self.assertEqual(self.lib.sn_receive_source(b'SCNMessagingConversationListener', selector), 2)

    def test_snapshot_requires_role(self):
        self.assertEqual(self.lib.sn_receive_source(b'SCConversationView', b'onMessagesUpdated:'), 0)
        self.assertEqual(self.lib.sn_receive_source(b'SCCallObserver', b'onMessagesUpdated:'), 0)

    def test_exact_presenters(self):
        self.assertEqual(self.lib.sn_receive_source(b'SCDefaultInAppNotificationPresentingPlugin', b'presentInAppNotificationAsync:delegate:'), 1)
        self.assertEqual(self.lib.sn_receive_source(b'OtherPlugin', b'presentInAppNotificationAsync:delegate:'), 0)

    def test_system_classes_ignored(self):
        for name in (b'NSObject', b'UIApplication', b'UNUserNotificationCenter', b'NSMessageObserver'):
            self.assertEqual(self.lib.sn_receive_source(name, b'didReceiveMessage:'), 0)

    def test_send_and_read_callbacks_not_received(self):
        for selector in (b'sendMessage:', b'onMessageSent:', b'onMessageRead:', b'onMessageDeleted:', b'onReceive:', b'setMessage:', b'initWithMessage:', b'dealloc', b'didReceiveMessageTelemetry:'):
            self.assertEqual(self.lib.sn_receive_source(b'SCMessageListener', selector), 0)

    def test_bad_selector(self):
        for cls, selector in ((None, b'didReceiveMessage:'), (b'SCMessage', None), (b'SCMessage', b''), (b'SCMessage', b'x'*500)):
            self.assertEqual(self.lib.sn_receive_source(cls, selector), 0)

    def test_hints(self):
        self.assertEqual(self.lib.sn_receive_hint(b'didReceiveSnap:'), 2)
        self.assertEqual(self.lib.sn_receive_hint(b'didReceiveChatMessage:context:'), 1)
        self.assertEqual(self.lib.sn_receive_hint(b'didReceiveMessage:'), 0)
        self.assertEqual(self.lib.sn_receive_hint(None), 0)

    def test_time_units(self):
        for factor in (1, 1000, 1000000, 1000000000):
            self.assertEqual(self.lib.sn_receive_seconds(1800000000*factor), 1800000000)

    def test_invalid_time(self):
        for raw in (float('nan'), float('inf'), -float('inf'), 0, -1):
            self.assertTrue(math.isnan(self.lib.sn_receive_seconds(raw)))

    def test_window(self):
        now = 1800000000
        for time in (now, now-300, now+60): self.assertTrue(self.lib.sn_receive_time_valid(time, now))
        for time in (now-301, now+61, 0, float('nan'), float('inf')): self.assertFalse(self.lib.sn_receive_time_valid(time, now))
        self.assertFalse(self.lib.sn_receive_time_valid(now, float('nan')))

if __name__ == '__main__':
    unittest.main()
