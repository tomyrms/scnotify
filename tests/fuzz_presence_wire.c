#include "../Core/SNPresenceWire.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint64_t rng=UINT64_C(0x14a7171c0de);
static uint32_t next_random(void) {
    rng^=rng<<13; rng^=rng>>7; rng^=rng<<17; return (uint32_t)rng;
}
static void check(const uint8_t *data,size_t size) {
    SNWirePresence presence;
    memset(&presence,0xa5,sizeof(presence));
    if (sn_decode_presence((SNBytes){data,size},&presence)) {
        assert(presence.count<=SN_WIRE_PRESENCE_MAX);
        assert(strlen(presence.conversation)==36);
        for (size_t i=0;i<presence.count;i++) {
            assert(strlen(presence.participants[i].uid)==36);
            for (size_t j=0;j<i;j++) assert(strcmp(presence.participants[i].uid,presence.participants[j].uid)!=0);
        }
    } else {
        const uint8_t *bytes=(const uint8_t *)&presence;
        for (size_t i=0;i<sizeof(presence);i++) assert(bytes[i]==0);
    }
}
int main(void) {
    /* Valid synthetic presence payload: one recording user; conversation last. */
    static const uint8_t seed[]= {
        0x22,0x2e,0x0a,0x28,
        '2','2','2','2','2','2','2','2','-','2','2','2','2','-','4','2','2','2','-',
        '8','2','2','2','-','2','2','2','2','2','2','2','2','2','2','2','2',':','d','e','v',
        0x12,0x02,0x08,0x50,0x32,0x24,
        '1','1','1','1','1','1','1','1','-','1','1','1','1','-','4','1','1','1','-',
        '8','1','1','1','-','1','1','1','1','1','1','1','1','1','1','1','1'
    };
    SNWirePresence sanity;
    assert(sn_decode_presence((SNBytes){seed,sizeof(seed)},&sanity));
    assert(sanity.count==1 && sanity.participants[0].flags==80);
    uint8_t data[4096];
    for (size_t i=0;i<=sizeof(seed);i++) check(seed,i);
    for (unsigned i=0;i<100000;i++) {
        size_t size;
        if (i&1) {
            size=sizeof(seed); memcpy(data,seed,size);
            unsigned changes=1+next_random()%8;
            while (changes--) data[next_random()%size]=(uint8_t)next_random();
        } else {
            size=next_random()%sizeof(data);
            for (size_t j=0;j<size;j++) data[j]=(uint8_t)next_random();
        }
        check(data,size);
    }
    puts("presence: 100000 deterministic mutation/random inputs + every seed truncation passed.");
    return 0;
}
