#include "../Core/SNCore.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
static uint64_t rng=0x762495aca13;
static uint32_t next(void){rng^=rng<<13;rng^=rng>>7;rng^=rng<<17;return (uint32_t)rng;}
static void check(const uint8_t *p,size_t n){
    SNRecord records[SN_RECORD_MAX];size_t count=0;SNCall c;
    if(sn_decode_records((SNBytes){p,n},records,&count)) {
        assert(count>0&&count<=SN_RECORD_MAX);
        for(size_t i=0;i<count;i++) {
            assert(records[i].payload.data>=p&&records[i].payload.data<=p+n);
            assert(records[i].payload.size<=(size_t)(p+n-records[i].payload.data));
            sn_decode_call(records[i].payload,&c);
        }
    } else assert(count==0);
    if(sn_decode_call((SNBytes){p,n},&c)) {
        assert(c.action==SN_CALL_START||c.action==SN_CALL_STOP);
        assert(strlen(c.conversation)==36&&strlen(c.sender)==36&&strlen(c.call)==36);
    } else assert(c.action==SN_CALL_NONE);
}
int main(int argc,char **argv){
    if(argc!=2){fprintf(stderr,"usage: fuzz_core call_start.bin\n");return 2;}
    uint8_t seed[4096],data[4096];FILE *f=fopen(argv[1],"rb");if(!f)return 2;
    size_t size=fread(seed,1,sizeof(seed),f);fclose(f);if(!size)return 2;
    for(size_t i=0;i<=size;i++)check(seed,i);
    for(unsigned i=0;i<100000;i++){
        size_t n;if(i&1){n=size;memcpy(data,seed,size);unsigned changes=1+next()%8;while(changes--)data[next()%n]=(uint8_t)next();}
        else {n=next()%sizeof(data);for(size_t k=0;k<n;k++)data[k]=(uint8_t)next();}
        check(data,n);
    }
    puts("core: 100000 deterministic mutation/random inputs + every seed truncation passed.");return 0;
}
