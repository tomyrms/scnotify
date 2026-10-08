/* Seeded bounded-input smoke fuzzing, not proof over all input space. */
#include "../Core/SNReceivePolicy.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <math.h>
static uint32_t rng=0x736e7232;
static uint32_t next(void){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
int main(void) {
    for(unsigned i=0;i<100000;i++) {
        char s[513],cls[96];size_t n=next()%512;
        for(size_t k=0;k<n;k++)s[k]=(char)(1+next()%255);
        s[n]=0;memset(cls,0,sizeof(cls));memcpy(cls,"SCMessageListener",17);
        SNReceiveKind kind=sn_receive_kind(s);assert(kind>=SN_RX_NONE&&kind<=SN_RX_CONTROL);
        SNReceiveSource source=sn_receive_source(cls,s);assert(source>=SN_SOURCE_NONE&&source<=SN_SOURCE_SNAPSHOT);
        (void)sn_receive_hint(s);
        uint64_t bits=((uint64_t)next()<<32)|next();double raw;memcpy(&raw,&bits,sizeof(raw));
        double seconds=sn_receive_seconds(raw);
        if(!isfinite(raw)||raw<=0)assert(isnan(seconds));
        else assert(isfinite(seconds)&&seconds>0&&seconds<=raw);
        (void)sn_receive_time_valid(raw,1800000000);
    }
    puts("receive policy: 100000 seeded inputs completed");return 0;
}
