#ifndef SN_DELIVERY_STATE_H
#define SN_DELIVERY_STATE_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SN_DELIVERY_WAITING = 0,
    SN_DELIVERY_SUBMITTED,
    SN_DELIVERY_RETRY_WAIT,
    SN_DELIVERY_TIMED_OUT,
    SN_DELIVERY_CANCELLED,
    SN_DELIVERY_ACCEPTED,
    SN_DELIVERY_FAILED
} SNDeliveryPhase;

typedef struct {
    SNDeliveryPhase phase;
    unsigned attempts;
} SNDeliveryState;

typedef enum {
    SN_DELIVERY_IGNORE = 0,
    SN_DELIVERY_ACCEPT,
    SN_DELIVERY_RETRY,
    SN_DELIVERY_FAIL,
    SN_DELIVERY_DISCARD
} SNDeliveryResult;

/* Single-queue owned; zero initialization starts in WAITING. A submission is
   permitted initially or after the one explicitly requested retry. */
bool sn_delivery_submit(SNDeliveryState *state);
/* A submission timeout does not prove rejection: a late success is accepted.
   An error after timeout fails without retry. Cancellation instead discards
   any completion. Duplicates outside a submitted/timed-out phase are ignored. */
SNDeliveryResult sn_delivery_complete(SNDeliveryState *state, bool success, bool retryable);
/* True only for SUBMITTED -> TIMED_OUT, where a completion remains possible.
   A request never submitted, or waiting to retry, fails. Other phases stay. */
bool sn_delivery_timeout(SNDeliveryState *state);
/* A submission's delayed deadline must not expire the subsequent retry or
   the wait before it. Capture attempts when scheduling that deadline. */
bool sn_delivery_timeout_attempt(SNDeliveryState *state, unsigned attempt);
/* Cancel any active/timed-out attempt; accepted/failed results stay final. */
void sn_delivery_cancel(SNDeliveryState *state);

#ifdef __cplusplus
}
#endif
#endif
