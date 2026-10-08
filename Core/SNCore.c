#include "SNCore.h"
#include <string.h>
#include <math.h>
#include <limits.h>

static bool varint(SNWire *w, uint64_t *out) {
    uint64_t v=0;
    for (unsigned n=0;n<10;n++) {
        if (w->offset>=w->bytes.size) return false;
        uint8_t b=w->bytes.data[w->offset++];
        if (n==9 && (b & 0xfe)) return false;
        v |= (uint64_t)(b & 0x7f) << (7*n);
        if (!(b & 0x80)) { *out=v; return true; }
    }
    return false;
}
int sn_wire_next(SNWire *w, SNField *f) {
    if (!w || !f || w->failed) return -1;
    memset(f,0,sizeof(*f));
    if (w->offset==w->bytes.size) return 0;
    if (!w->bytes.data || w->offset>w->bytes.size || ++w->fields>4096) goto fail;
    uint64_t tag=0,len=0;
    if (!varint(w,&tag) || (tag>>3)==0 || (tag>>3)>0x1fffffff) goto fail;
    f->number=(uint32_t)(tag>>3); f->type=(unsigned)(tag & 7);
    switch (f->type) {
        case 0: if (!varint(w,&f->integer)) goto fail; return 1;
        case 1: len=8; break;
        case 2: if (!varint(w,&len)) goto fail; break;
        case 5: len=4; break;
        default: goto fail; /* Groups deliberately unsupported; fail closed. */
    }
    if (len > w->bytes.size-w->offset) goto fail;
    f->bytes=(SNBytes){w->bytes.data+w->offset,(size_t)len};
    w->offset+=(size_t)len;
    return 1;
fail: w->failed=true; return -1;
}
static int hex(unsigned char c) {
    if (c>='0' && c<='9') return c-'0';
    if (c>='a' && c<='f') return c-'a'+10;
    if (c>='A' && c<='F') return c-'A'+10;
    return -1;
}
bool sn_uuid(const char *s, size_t n, char out[SN_UUID_SIZE]) {
    if (!out) return false;
    out[0]=0;
    if (!s || n!=36) return false;
    char tmp[SN_UUID_SIZE]; bool nonzero=false;
    for (size_t i=0;i<36;i++) {
        if (i==8||i==13||i==18||i==23) { if (s[i]!='-') return false; tmp[i]='-'; }
        else { int h=hex((unsigned char)s[i]); if (h<0) return false;
               tmp[i]="0123456789abcdef"[h]; nonzero |= h!=0; }
    }
    if (!nonzero) return false;
    tmp[36]=0; memcpy(out,tmp,sizeof(tmp)); return true;
}
static bool record(SNBytes bytes, SNRecord *r) {
    SNWire w={.bytes=bytes}; SNField f; int rc; unsigned seen=0;
    memset(r,0,sizeof(*r));
    while ((rc=sn_wire_next(&w,&f))==1) {
        if (f.number==1) {
            if ((seen&1)||f.type!=2||!f.bytes.size||f.bytes.size>64) return false;
            for (size_t i=0;i<f.bytes.size;i++) {
                uint8_t c=f.bytes.data[i];
                if (!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.')) return false;
            }
            memcpy(r->topic,f.bytes.data,f.bytes.size); seen|=1;
        } else if (f.number==2) {
            if ((seen&2)||f.type!=2) return false;
            r->payload=f.bytes; seen|=2;
        }
    }
    return rc==0 && seen==3;
}
bool sn_decode_records(SNBytes p, SNRecord out[SN_RECORD_MAX], size_t *count) {
    if (count) *count=0;
    if (!out||!count||!p.data||!p.size||p.size>SN_PACKET_MAX) return false;
    SNWire w={.bytes=p}; SNField f; size_t n=0; int rc;
    while ((rc=sn_wire_next(&w,&f))==1) {
        if (f.number!=1) continue;
        if (f.type!=2||n>=SN_RECORD_MAX||!record(f.bytes,&out[n])) return false;
        n++;
    }
    if (rc<0||n==0) return false;
    *count=n; return true;
}

/* Small validating JSON reader. It does not search arbitrary substrings.
   Only a few top-level scalar keys are retained. Unknown fields are validated
   then skipped; depth, input size and token counts are bounded. */
typedef struct { const uint8_t *s; size_t n,p; unsigned tokens; } JSON;
typedef struct {
    char type[64],action[32],uuid[SN_UUID_SIZE],media[32];
    bool skip, has_skip; unsigned seen;
} CallJSON;
static void ws(JSON *j) { while(j->p<j->n && (j->s[j->p]==' '||j->s[j->p]=='\n'||j->s[j->p]=='\r'||j->s[j->p]=='\t')) j->p++; }
static bool put(char *out,size_t cap,size_t *n,uint8_t c) {
    if (out) { if (*n+1>=cap) return false; out[*n]=(char)c; }
    (*n)++; return true;
}
static bool u4(JSON *j,uint32_t *v) {
    if (j->n-j->p<4) return false;
    *v=0;
    for(int i=0;i<4;i++){int h=hex(j->s[j->p++]);if(h<0)return false;*v=(*v<<4)|(unsigned)h;}
    return true;
}
static bool jstring(JSON *j,char *out,size_t cap) {
    if(j->p>=j->n||j->s[j->p++]!='"') return false;
    size_t n=0;
    while(j->p<j->n) {
        uint8_t c=j->s[j->p++];
        if(c=='"') { if(out) out[n]=0; return true; }
        if(c<0x20) return false;
        if(c=='\\') {
            if(j->p>=j->n) return false;
            c=j->s[j->p++];
            if(c=='u') {
                uint32_t cp; if(!u4(j,&cp))return false;
                if(cp>=0xd800&&cp<=0xdbff) {
                    if(j->n-j->p<6||j->s[j->p++]!='\\'||j->s[j->p++]!='u') return false;
                    uint32_t lo; if(!u4(j,&lo)||lo<0xdc00||lo>0xdfff)return false;
                    cp=0x10000+((cp-0xd800)<<10)+(lo-0xdc00);
                } else if(cp>=0xdc00&&cp<=0xdfff) return false;
                /* NUL is invalid in the protocol fields we retain. */
                if(out && cp==0)return false;
                if(cp<0x80) {if(!put(out,cap,&n,(uint8_t)cp))return false;}
                else if(cp<0x800) {if(!put(out,cap,&n,0xc0|(cp>>6))||!put(out,cap,&n,0x80|(cp&63)))return false;}
                else if(cp<0x10000) {if(!put(out,cap,&n,0xe0|(cp>>12))||!put(out,cap,&n,0x80|((cp>>6)&63))||!put(out,cap,&n,0x80|(cp&63)))return false;}
                else {if(!put(out,cap,&n,0xf0|(cp>>18))||!put(out,cap,&n,0x80|((cp>>12)&63))||!put(out,cap,&n,0x80|((cp>>6)&63))||!put(out,cap,&n,0x80|(cp&63)))return false;}
                continue;
            }
            switch(c) { case '"':case '\\':case '/':break;case 'b':c=8;break;case 'f':c=12;break;case 'n':c=10;break;case 'r':c=13;break;case 't':c=9;break;default:return false; }
        } else if(c>=0x80) {
            /* Validate raw UTF-8 too; overlong and surrogate encodings rejected. */
            unsigned extra; uint32_t cp,min;
            if(c>=0xc2&&c<=0xdf){extra=1;cp=c&31;min=0x80;}
            else if(c>=0xe0&&c<=0xef){extra=2;cp=c&15;min=0x800;}
            else if(c>=0xf0&&c<=0xf4){extra=3;cp=c&7;min=0x10000;}
            else return false;
            if(!put(out,cap,&n,c)||j->n-j->p<extra)return false;
            for(unsigned k=0;k<extra;k++){uint8_t b=j->s[j->p++];if((b&0xc0)!=0x80||!put(out,cap,&n,b))return false;cp=(cp<<6)|(b&63);}
            if(cp<min||cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff))return false;
            continue;
        }
        if(!put(out,cap,&n,c))return false;
    }
    return false;
}
static bool literal(JSON *j,const char *s) {
    size_t n=strlen(s); if(j->n-j->p<n||memcmp(j->s+j->p,s,n))return false;j->p+=n;return true;
}
static bool digit(JSON *j) {return j->p<j->n&&j->s[j->p]>='0'&&j->s[j->p]<='9';}
static bool number(JSON *j) {
    if(j->p<j->n&&j->s[j->p]=='-')j->p++;
    if(!digit(j))return false;
    if(j->s[j->p]=='0')j->p++;else while(digit(j))j->p++;
    if(j->p<j->n&&j->s[j->p]=='.'){j->p++;if(!digit(j))return false;while(digit(j))j->p++;}
    if(j->p<j->n&&(j->s[j->p]=='e'||j->s[j->p]=='E')){j->p++;if(j->p<j->n&&(j->s[j->p]=='+'||j->s[j->p]=='-'))j->p++;if(!digit(j))return false;while(digit(j))j->p++;}
    return true;
}
static bool value(JSON *j,unsigned depth);
static bool collection(JSON *j,unsigned depth,bool object) {
    char end=object?'}':']'; j->p++;ws(j);
    if(j->p<j->n&&j->s[j->p]==end){j->p++;return true;}
    for(;;) {
        if(object){if(!jstring(j,NULL,0))return false;ws(j);if(j->p>=j->n||j->s[j->p++]!=':')return false;}
        if(!value(j,depth+1))return false;ws(j);
        if(j->p>=j->n)return false;
        char c=(char)j->s[j->p++];if(c==end)return true;if(c!=',')return false;ws(j);
    }
}
static bool value(JSON *j,unsigned depth) {
    if(depth>16||++j->tokens>4096)return false;ws(j);if(j->p>=j->n)return false;
    switch(j->s[j->p]){case '"':return jstring(j,NULL,0);case '{':return collection(j,depth,true);case '[':return collection(j,depth,false);case 't':return literal(j,"true");case 'f':return literal(j,"false");case 'n':return literal(j,"null");default:return number(j);}
}
static bool call_json(SNBytes b,CallJSON *out) {
    if(!b.data||b.size>65536)return false;
    JSON j={.s=b.data,.n=b.size};memset(out,0,sizeof(*out));ws(&j);
    if(j.p>=j.n||j.s[j.p++]!='{')return false;ws(&j);
    if(j.p<j.n&&j.s[j.p]=='}')return false;
    for(;;) {
        char key[128];if(++j.tokens>4096||!jstring(&j,key,sizeof(key)))return false;ws(&j);
        if(j.p>=j.n||j.s[j.p++]!=':')return false;ws(&j);
        unsigned bit=0;char *dst=NULL;size_t cap=0;
        if(!strcmp(key,"messageType")){bit=1;dst=out->type;cap=sizeof(out->type);}
        else if(!strcmp(key,"callAction")){bit=2;dst=out->action;cap=sizeof(out->action);}
        else if(!strcmp(key,"callUuid")){bit=4;dst=out->uuid;cap=sizeof(out->uuid);}
        else if(!strcmp(key,"media")){bit=8;dst=out->media;cap=sizeof(out->media);}
        else if(!strcmp(key,"skipRinging"))bit=16;
        if(bit&&(out->seen&bit))return false;out->seen|=bit;
        if(dst){if(!jstring(&j,dst,cap))return false;}
        else if(bit==16){out->has_skip=true;if(literal(&j,"true"))out->skip=true;else if(literal(&j,"false"))out->skip=false;else return false;}
        else if(!value(&j,1))return false;
        ws(&j);if(j.p>=j.n)return false;char c=(char)j.s[j.p++];
        if(c=='}')break;if(c!=',')return false;ws(&j);
    }
    ws(&j);return j.p==j.n&&(out->seen&7)==7;
}
bool sn_decode_call(SNBytes p,SNCall *out) {
    if(!out)return false;memset(out,0,sizeof(*out));
    if(!p.data||!p.size||p.size>SN_PACKET_MAX)return false;
    SNWire w={.bytes=p};SNField f;unsigned seen=0;SNBytes json={0};SNCall c={0};int rc;
    while((rc=sn_wire_next(&w,&f))==1){
        unsigned bit=f.number==2?1:f.number==3?2:f.number==5?4:0;
        if(!bit)continue;
        if((seen&bit)||f.type!=2)return false;seen|=bit;
        if(bit==1&&!sn_uuid((const char *)f.bytes.data,f.bytes.size,c.conversation))return false;
        if(bit==2&&!sn_uuid((const char *)f.bytes.data,f.bytes.size,c.sender))return false;
        if(bit==4)json=f.bytes;
    }
    if(rc<0||seen!=7)return false;
    CallJSON j;if(!call_json(json,&j)||strcmp(j.type,"CALLER_PUSH")||!sn_uuid(j.uuid,strlen(j.uuid),c.call))return false;
    if(!strcmp(j.action,"START"))c.action=SN_CALL_START;
    else if(!strcmp(j.action,"STOP"))c.action=SN_CALL_STOP;
    else return false;
    /* Require explicit ring policy for START. Unknown policy is not permission. */
    if(c.action==SN_CALL_START&&!j.has_skip)return false;
    c.skip_ringing=j.skip;c.video=!strcmp(j.media,"audio_video");*out=c;return true;
}

SNPresenceChange sn_presence_update(SNPresence *s,bool active,double now,double idle,double gap) {
    if(!s||!isfinite(now)||now<0||!isfinite(idle)||idle<=0||!isfinite(gap)||gap<0)return SN_PRESENCE_NONE;
    if(s->observed&&now<s->last_activity) return SN_PRESENCE_NONE;
    bool expired=s->active&&s->observed&&now-s->last_activity>=idle;
    bool was=s->active;
    s->last_activity=now;s->observed=true;
    if(!active){s->active=false;return was?SN_PRESENCE_STOP:SN_PRESENCE_NONE;}
    if(was&&!expired)return SN_PRESENCE_NONE;
    /* A bounced restart stays re-armable instead of being locked on forever. */
    if(s->notified&&now-s->last_notification<gap){s->active=false;return SN_PRESENCE_NONE;}
    s->active=true;s->notified=true;s->last_notification=now;s->session++;
    return SN_PRESENCE_START;
}
static bool time_ok(double now,double ttl) {return isfinite(now)&&now>=0&&isfinite(ttl)&&ttl>0&&isfinite(now+ttl);}
uint64_t sn_ledger_reserve(SNLedger *l,const char *key,double now,double ttl) {
    if(!l||!key||!time_ok(now,ttl))return 0;
    size_t len=strnlen(key,SN_KEY_SIZE);if(!len||len>=SN_KEY_SIZE)return 0;
    size_t slot=0;double oldest=INFINITY;bool available=false;
    for(size_t i=0;i<SN_LEDGER_SIZE;i++){
        SNLedgerEntry *e=&l->entries[i];
        if(e->occupied&&e->expires>now&&!strcmp(e->key,key))return 0;
        if(!e->occupied||e->expires<=now){if(!available){slot=i;available=true;}}
        else if(!available&&e->expires<oldest){oldest=e->expires;slot=i;}
    }
    SNLedgerEntry *e=&l->entries[slot];memset(e,0,sizeof(*e));memcpy(e->key,key,len+1);
    e->ticket=++l->serial;if(!e->ticket)e->ticket=++l->serial;
    e->expires=now+ttl;e->occupied=true;return e->ticket;
}
bool sn_ledger_commit(SNLedger *l,uint64_t ticket,double now,double ttl) {
    if(!l||!ticket||!time_ok(now,ttl))return false;
    for(size_t i=0;i<SN_LEDGER_SIZE;i++)if(l->entries[i].occupied&&l->entries[i].ticket==ticket){l->entries[i].committed=true;l->entries[i].expires=now+ttl;return true;}
    return false;
}
void sn_ledger_cancel(SNLedger *l,uint64_t ticket) {
    if(!l||!ticket)return;
    for(size_t i=0;i<SN_LEDGER_SIZE;i++)if(l->entries[i].occupied&&l->entries[i].ticket==ticket){memset(&l->entries[i],0,sizeof(l->entries[i]));return;}
}
void sn_ledger_mark(SNLedger *l,const char *key,double now,double ttl) {
    if(!l||!key||!time_ok(now,ttl))return;
    for(size_t i=0;i<SN_LEDGER_SIZE;i++)if(l->entries[i].occupied&&!strcmp(l->entries[i].key,key)){l->entries[i].expires=now+ttl;l->entries[i].committed=true;return;}
    uint64_t t=sn_ledger_reserve(l,key,now,ttl);if(t)sn_ledger_commit(l,t,now,ttl);
}
