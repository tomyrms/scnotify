#ifndef SN_CORE_H
#define SN_CORE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

#define SN_PACKET_MAX (1024u * 1024u)
#define SN_RECORD_MAX 64u
#define SN_UUID_SIZE 37u
#define SN_LEDGER_SIZE 512u
#define SN_KEY_SIZE 384u

typedef struct { const uint8_t *data; size_t size; } SNBytes;
typedef struct { SNBytes bytes; size_t offset; unsigned fields; bool failed; } SNWire;
typedef struct { uint32_t number; unsigned type; uint64_t integer; SNBytes bytes; } SNField;
/* 1 = field, 0 = end, -1 = malformed/unsupported. No allocation; no overreads. */
int sn_wire_next(SNWire *wire, SNField *field);
bool sn_uuid(const char *text, size_t length, char out[SN_UUID_SIZE]);

typedef struct { char topic[65]; SNBytes payload; } SNRecord;
/* Transactional: a malformed batch returns zero records, never a partial batch. */
bool sn_decode_records(SNBytes packet, SNRecord records[SN_RECORD_MAX], size_t *count);

typedef enum { SN_CALL_NONE=0, SN_CALL_START=1, SN_CALL_STOP=2 } SNCallAction;
typedef struct {
    SNCallAction action;
    char conversation[SN_UUID_SIZE];
    char sender[SN_UUID_SIZE];
    char call[SN_UUID_SIZE];
    bool video;
    bool skip_ringing;
} SNCall;
/* Observed volatile schema: fields 2=conversation UUID, 3=sender UUID, 5=JSON.
   Only CALLER_PUSH START/STOP is a call. Other volatile packets are ignored. */
bool sn_decode_call(SNBytes payload, SNCall *call);

typedef struct {
    bool active, observed, notified;
    double last_activity, last_notification;
    uint64_t session;
} SNPresence;
typedef enum { SN_PRESENCE_NONE=0, SN_PRESENCE_START=1, SN_PRESENCE_STOP=2 } SNPresenceChange;
/* Time is monotonic seconds supplied by the caller. An unknown state must not
   be passed as false. A missing member of a complete snapshot is a real stop. */
SNPresenceChange sn_presence_update(SNPresence *state, bool active, double now,
                                    double idle_timeout, double restart_gap);

typedef struct {
    char key[SN_KEY_SIZE];
    uint64_t ticket;
    double expires;
    bool occupied, committed;
} SNLedgerEntry;
typedef struct { SNLedgerEntry entries[SN_LEDGER_SIZE]; uint64_t serial; } SNLedger;
/* Single-queue owned. Zero means duplicate, invalid key or invalid time. */
uint64_t sn_ledger_reserve(SNLedger *ledger, const char *key, double now, double pending_ttl);
bool sn_ledger_commit(SNLedger *ledger, uint64_t ticket, double now, double ttl);
void sn_ledger_cancel(SNLedger *ledger, uint64_t ticket);
/* Tombstone a stopped call to suppress late START retransmissions. */
void sn_ledger_mark(SNLedger *ledger, const char *key, double now, double ttl);
#ifdef __cplusplus
}
#endif
#endif
