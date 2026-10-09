#include "SNDeliveryState.h"

bool sn_delivery_submit(SNDeliveryState *state) {
    if (!state) return false;
    if (!((state->phase == SN_DELIVERY_WAITING && state->attempts == 0) ||
          (state->phase == SN_DELIVERY_RETRY_WAIT && state->attempts == 1))) return false;
    state->phase = SN_DELIVERY_SUBMITTED;
    state->attempts++;
    return true;
}

SNDeliveryResult sn_delivery_complete(SNDeliveryState *state, bool success, bool retryable) {
    if (!state) return SN_DELIVERY_IGNORE;
    if (state->phase == SN_DELIVERY_CANCELLED) return SN_DELIVERY_DISCARD;
    if ((state->phase != SN_DELIVERY_SUBMITTED && state->phase != SN_DELIVERY_TIMED_OUT) ||
        state->attempts == 0 || state->attempts > 2) return SN_DELIVERY_IGNORE;
    if (success) {
        state->phase = SN_DELIVERY_ACCEPTED;
        return SN_DELIVERY_ACCEPT;
    }
    if (state->phase == SN_DELIVERY_SUBMITTED && state->attempts == 1 && retryable) {
        state->phase = SN_DELIVERY_RETRY_WAIT;
        return SN_DELIVERY_RETRY;
    }
    state->phase = SN_DELIVERY_FAILED;
    return SN_DELIVERY_FAIL;
}

bool sn_delivery_timeout(SNDeliveryState *state) {
    if (!state) return false;
    if (state->phase == SN_DELIVERY_SUBMITTED) {
        state->phase = SN_DELIVERY_TIMED_OUT;
        return true;
    }
    if (state->phase == SN_DELIVERY_WAITING || state->phase == SN_DELIVERY_RETRY_WAIT)
        state->phase = SN_DELIVERY_FAILED;
    return false;
}

bool sn_delivery_timeout_attempt(SNDeliveryState *state, unsigned attempt) {
    if (!state || state->phase != SN_DELIVERY_SUBMITTED || state->attempts != attempt)
        return false;
    return sn_delivery_timeout(state);
}

void sn_delivery_cancel(SNDeliveryState *state) {
    if (!state) return;
    switch (state->phase) {
        case SN_DELIVERY_WAITING:
        case SN_DELIVERY_SUBMITTED:
        case SN_DELIVERY_RETRY_WAIT:
        case SN_DELIVERY_TIMED_OUT:
            state->phase = SN_DELIVERY_CANCELLED;
            break;
        default:
            break;
    }
}
