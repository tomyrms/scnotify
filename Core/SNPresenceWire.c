#include "SNPresenceWire.h"
#include <string.h>

/* Wire layout corroborated by SnapEnhance / SE-Extended's presence decoder:
   https://github.com/CoffeeBrewer64/SE-Extended/blob/be815bbf435d8ece4514b390dc6dbbf2ee81c0aa/core/src/main/kotlin/me/rhunk/snapenhance/core/features/impl/spying/FriendTracker.kt#L169-L189
   Only the interoperable schema is used here; this validating implementation
   shares SNCore's bounded wire reader, with no third-party implementation code. */
static bool presence_wire_state(SNBytes bytes, uint64_t *flags) {
    SNWire wire={.bytes=bytes}; SNField field; int rc; bool seen=false;
    while ((rc=sn_wire_next(&wire,&field))==1) {
        if (field.number!=1) continue;
        if (seen || field.type!=0) return false;
        *flags=field.integer; seen=true;
    }
    return rc==0 && seen;
}

static bool presence_wire_participant(SNBytes bytes, SNWirePresenceParticipant *out) {
    SNWire wire={.bytes=bytes}; SNField field; int rc; unsigned seen=0;
    memset(out,0,sizeof(*out));
    while ((rc=sn_wire_next(&wire,&field))==1) {
        if (field.number==1) {
            /* A bare UUID or empty session is not the observed participant key.
               Inspect the suffix too: truncation/NUL/control bytes are invalid. */
            if ((seen&1) || field.type!=2 || field.bytes.size<38 || field.bytes.size>256 ||
                field.bytes.data[36]!=':' ||
                !sn_uuid((const char *)field.bytes.data,36,out->uid)) return false;
            for (size_t i=37;i<field.bytes.size;i++)
                if (field.bytes.data[i]<0x21 || field.bytes.data[i]>0x7e) return false;
            seen|=1;
        } else if (field.number==2) {
            if ((seen&2) || field.type!=2 || !presence_wire_state(field.bytes,&out->flags)) return false;
            seen|=2;
        }
    }
    return rc==0 && seen==3;
}

bool sn_decode_presence(SNBytes payload, SNWirePresence *out) {
    if (!out) return false;
    memset(out,0,sizeof(*out));
    if (!payload.data || !payload.size || payload.size>SN_PACKET_MAX) return false;
    SNWirePresence result={0}; SNWire wire={.bytes=payload}; SNField field;
    int rc; bool conversation_seen=false; size_t members_seen=0;
    while ((rc=sn_wire_next(&wire,&field))==1) {
        if (field.number==6) {
            if (conversation_seen || field.type!=2 ||
                !sn_uuid((const char *)field.bytes.data,field.bytes.size,result.conversation)) return false;
            conversation_seen=true;
        } else if (field.number==4) {
            SNWirePresenceParticipant participant;
            if (field.type!=2 || ++members_seen>SN_WIRE_PRESENCE_MAX ||
                !presence_wire_participant(field.bytes,&participant)) return false;
            size_t index=0;
            while (index<result.count && strcmp(result.participants[index].uid,participant.uid)!=0) index++;
            if (index<result.count) {
                if (result.participants[index].flags!=participant.flags) return false;
            } else result.participants[result.count++]=participant;
        }
    }
    if (rc!=0 || !conversation_seen) return false;
    *out=result;
    return true;
}
