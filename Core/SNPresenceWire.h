#ifndef SN_PRESENCE_WIRE_H
#define SN_PRESENCE_WIRE_H
#include "SNCore.h"
#ifdef __cplusplus
extern "C" {
#endif

#define SN_WIRE_PRESENCE_MAX 256u
#define SN_WIRE_PRESENCE_COMPOSING (UINT64_C(1) << 4)
#define SN_WIRE_PRESENCE_VOICE (UINT64_C(1) << 6)

typedef struct {
    char uid[SN_UUID_SIZE];
    uint64_t flags;
} SNWirePresenceParticipant;
typedef struct {
    char conversation[SN_UUID_SIZE];
    size_t count;
    SNWirePresenceParticipant participants[SN_WIRE_PRESENCE_MAX];
} SNWirePresence;

/* Decode the payload of a duplex record whose topic is exactly "presence".
   Field 6 is the conversation UUID. Each field 4 participant has a field 1
   uuid:session identifier and a field 2 state containing field 1 uint64 flags.
   Bit 4 is composing; voice requires BOTH bits 4 and 6. Other bits are retained.
   These are wire flags, NOT the SCCPresencePlatform typingState enum.

   Transactional: failure clears the entire result, including count. A malformed
   participant must never become an absent participant / synthesized STOP.
   Equal duplicate users are coalesced; conflicting states are rejected. The
   parser validates a payload, but does not establish snapshot freshness. */
bool sn_decode_presence(SNBytes payload, SNWirePresence *out);

#ifdef __cplusplus
}
#endif
#endif
