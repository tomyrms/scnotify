#!/usr/bin/env python3
"""Asynchronous delivery ordering regressions against production C via ctypes."""
from __future__ import annotations
import ctypes as C
from pathlib import Path
import tempfile
import unittest
from native_build import build_library, unload_library

ROOT = Path(__file__).resolve().parents[1]
TEMP = tempfile.TemporaryDirectory(prefix='snapnotify-delivery-')
LIB = build_library(TEMP.name, 'delivery', ROOT / 'Core/SNDeliveryState.c',
                    ['sn_delivery_submit', 'sn_delivery_complete',
                     'sn_delivery_timeout', 'sn_delivery_timeout_attempt', 'sn_delivery_cancel'])
lib = C.CDLL(str(LIB))


def tearDownModule():
    unload_library(lib)
    TEMP.cleanup()


class State(C.Structure):
    _fields_ = [('phase', C.c_int), ('attempts', C.c_uint)]


WAITING, SUBMITTED, RETRY_WAIT, TIMED_OUT, CANCELLED, ACCEPTED, FAILED = range(7)
IGNORE, ACCEPT, RETRY, FAIL, DISCARD = range(5)
lib.sn_delivery_submit.argtypes = [C.POINTER(State)]
lib.sn_delivery_submit.restype = C.c_bool
lib.sn_delivery_complete.argtypes = [C.POINTER(State), C.c_bool, C.c_bool]
lib.sn_delivery_complete.restype = C.c_int
lib.sn_delivery_timeout.argtypes = [C.POINTER(State)]
lib.sn_delivery_timeout.restype = C.c_bool
lib.sn_delivery_timeout_attempt.argtypes = [C.POINTER(State), C.c_uint]
lib.sn_delivery_timeout_attempt.restype = C.c_bool
lib.sn_delivery_cancel.argtypes = [C.POINTER(State)]
lib.sn_delivery_cancel.restype = None


class DeliveryTests(unittest.TestCase):
    def setUp(self): self.state = State()
    def submit(self): return lib.sn_delivery_submit(C.byref(self.state))
    def complete(self, success, retryable=True):
        return lib.sn_delivery_complete(C.byref(self.state), success, retryable)
    def timeout(self): return lib.sn_delivery_timeout(C.byref(self.state))
    def cancel(self): lib.sn_delivery_cancel(C.byref(self.state))
    def assert_state(self, phase, attempts):
        self.assertEqual((self.state.phase, self.state.attempts), (phase, attempts))

    def test_initial_submission_and_acceptance(self):
        self.assert_state(WAITING, 0)
        self.assertTrue(self.submit())
        self.assert_state(SUBMITTED, 1)
        self.assertFalse(self.submit())
        self.assertEqual(self.complete(True), ACCEPT)
        self.assert_state(ACCEPTED, 1)

    def test_late_success_after_timeout_remains_accepted(self):
        self.assertTrue(self.submit())
        self.assertTrue(self.timeout())
        self.assert_state(TIMED_OUT, 1)
        self.assertFalse(self.submit())
        self.assertEqual(self.complete(True), ACCEPT)
        self.assert_state(ACCEPTED, 1)

    def test_error_after_timeout_fails_without_retry(self):
        for retryable in (True, False):
            with self.subTest(retryable=retryable):
                self.state = State()
                self.assertTrue(self.submit())
                self.assertTrue(self.timeout())
                self.assertEqual(self.complete(False, retryable), FAIL)
                self.assert_state(FAILED, 1)
                self.assertFalse(self.submit())

    def test_single_retry_can_succeed(self):
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(False), RETRY)
        self.assert_state(RETRY_WAIT, 1)
        self.assertTrue(self.submit())
        self.assert_state(SUBMITTED, 2)
        self.assertEqual(self.complete(True), ACCEPT)
        self.assert_state(ACCEPTED, 2)

    def test_second_error_never_requests_third_submission(self):
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(False), RETRY)
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(False), FAIL)
        self.assert_state(FAILED, 2)
        self.assertFalse(self.submit())

    def test_nonretryable_error_is_final(self):
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(False, False), FAIL)
        self.assert_state(FAILED, 1)
        self.assertFalse(self.submit())

    def test_timeout_before_submission_fails(self):
        self.assertFalse(self.timeout())
        self.assert_state(FAILED, 0)
        self.assertFalse(self.submit())
        self.assertEqual(self.complete(True), IGNORE)

    def test_timeout_during_retry_wait_prevents_delayed_retry(self):
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(False), RETRY)
        self.assertFalse(self.timeout())
        self.assert_state(FAILED, 1)
        self.assertFalse(self.submit())
        self.assertEqual(self.complete(True), IGNORE)

    def test_retry_submission_can_be_accepted_after_its_timeout(self):
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(False), RETRY)
        self.assertTrue(self.submit())
        self.assertTrue(self.timeout())
        self.assertEqual(self.complete(True), ACCEPT)
        self.assert_state(ACCEPTED, 2)

    def test_first_attempt_deadline_cannot_expire_retry_wait_or_second_submission(self):
        # Attempt 1 starts at t=0, fails at t=14.5, retry starts at t=15.5.
        # Its original t=15 deadline must neither kill the scheduled retry nor
        # shorten attempt 2's deadline if worker scheduling delays that timer.
        self.assertTrue(self.submit())
        first_attempt = self.state.attempts
        self.assertEqual(self.complete(False), RETRY)
        self.assertFalse(lib.sn_delivery_timeout_attempt(C.byref(self.state), first_attempt))
        self.assert_state(RETRY_WAIT, 1)
        self.assertTrue(self.submit())
        second_attempt = self.state.attempts
        self.assertFalse(lib.sn_delivery_timeout_attempt(C.byref(self.state), first_attempt))
        self.assert_state(SUBMITTED, 2)
        self.assertTrue(lib.sn_delivery_timeout_attempt(C.byref(self.state), second_attempt))
        self.assert_state(TIMED_OUT, 2)
        self.assertEqual(self.complete(True), ACCEPT)
        self.assert_state(ACCEPTED, 2)

    def test_attempt_deadline_ignores_non_submitted_and_mismatched_states(self):
        self.assertFalse(lib.sn_delivery_timeout_attempt(None, 1))
        for phase, attempts in ((WAITING, 0), (RETRY_WAIT, 1), (TIMED_OUT, 1),
                                (CANCELLED, 1), (ACCEPTED, 1), (FAILED, 1)):
            with self.subTest(phase=phase):
                self.state = State(phase, attempts)
                self.assertFalse(lib.sn_delivery_timeout_attempt(C.byref(self.state), attempts))
                self.assert_state(phase, attempts)
        self.state = State(SUBMITTED, 1)
        for attempt in (0, 2):
            with self.subTest(attempt=attempt):
                self.assertFalse(lib.sn_delivery_timeout_attempt(C.byref(self.state), attempt))
                self.assert_state(SUBMITTED, 1)

    def test_repeated_timeout_preserves_late_completion(self):
        self.assertTrue(self.submit())
        self.assertTrue(self.timeout())
        self.assertFalse(self.timeout())
        self.assert_state(TIMED_OUT, 1)
        self.assertEqual(self.complete(True), ACCEPT)

    def test_cancellation_discards_completions_in_all_active_phases(self):
        for phase, attempts in ((WAITING, 0), (SUBMITTED, 1),
                                (RETRY_WAIT, 1), (TIMED_OUT, 1)):
            for success in (True, False):
                with self.subTest(phase=phase, success=success):
                    self.state = State(phase, attempts)
                    self.cancel()
                    self.assert_state(CANCELLED, attempts)
                    self.assertFalse(self.submit())
                    self.assertFalse(self.timeout())
                    self.assertEqual(self.complete(success), DISCARD)
                    self.assert_state(CANCELLED, attempts)

    def test_accepted_result_survives_late_cancel_timeout_and_duplicate(self):
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(True), ACCEPT)
        self.cancel()
        self.assertFalse(self.timeout())
        self.assertEqual(self.complete(True), IGNORE)
        self.assertEqual(self.complete(False), IGNORE)
        self.assert_state(ACCEPTED, 1)

    def test_failed_result_survives_late_cancel_timeout_and_duplicate(self):
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(False, False), FAIL)
        self.cancel()
        self.assertFalse(self.timeout())
        self.assertEqual(self.complete(True), IGNORE)
        self.assert_state(FAILED, 1)

    def test_unsolicited_completion_does_not_change_waiting_state(self):
        self.assertEqual(self.complete(True), IGNORE)
        self.assertEqual(self.complete(False), IGNORE)
        self.assert_state(WAITING, 0)

    def test_duplicate_completion_during_retry_wait_is_ignored(self):
        self.assertTrue(self.submit())
        self.assertEqual(self.complete(False), RETRY)
        self.assertEqual(self.complete(False), IGNORE)
        self.assertEqual(self.complete(True), IGNORE)
        self.assert_state(RETRY_WAIT, 1)

    def test_timed_out_delivery_does_not_affect_next_message(self):
        first = State()
        second = State()
        self.assertTrue(lib.sn_delivery_submit(C.byref(first)))
        self.assertTrue(lib.sn_delivery_timeout(C.byref(first)))
        self.assertTrue(lib.sn_delivery_submit(C.byref(second)))
        self.assertEqual(lib.sn_delivery_complete(C.byref(second), True, True), ACCEPT)
        self.assertEqual(lib.sn_delivery_complete(C.byref(first), True, True), ACCEPT)
        self.assertEqual((first.phase, second.phase), (ACCEPTED, ACCEPTED))

    def test_null_state_is_ignored(self):
        self.assertFalse(lib.sn_delivery_submit(None))
        self.assertFalse(lib.sn_delivery_timeout(None))
        self.assertEqual(lib.sn_delivery_complete(None, True, True), IGNORE)
        lib.sn_delivery_cancel(None)

    def test_invalid_submission_history_is_rejected(self):
        for phase, attempts in ((WAITING, 1), (RETRY_WAIT, 0), (RETRY_WAIT, 2), (99, 0)):
            with self.subTest(phase=phase, attempts=attempts):
                self.state = State(phase, attempts)
                self.assertFalse(self.submit())
                self.assertEqual(self.complete(True), IGNORE)
                self.assert_state(phase, attempts)
        for attempts in (0, 3, 4294967295):
            with self.subTest(attempts=attempts):
                self.state = State(SUBMITTED, attempts)
                self.assertEqual(self.complete(True), IGNORE)
                self.assert_state(SUBMITTED, attempts)


if __name__ == '__main__': unittest.main(verbosity=2)
