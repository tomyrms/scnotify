#import "SNRuntime.h"
#import "../Core/SNCore.h"
#import <objc/message.h>
#include <stdlib.h>
#include <string.h>

static _Thread_local BOOL inspecting = NO;
void SNInspect(dispatch_block_t block) {
    if (inspecting || !block) return;
    inspecting=YES;
    @try { block(); } @catch (__unused NSException *exception) { /* Host callbacks must continue. */ }
    @finally { inspecting=NO; }
}
static const char *unqualified(const char *t) {
    while (t && *t && strchr("rnNoORV",*t)) t++;
    return t;
}
id SNRead(id obj, NSString *key) {
    if (!obj || obj==NSNull.null || !key.length) return nil;
    @try {
        if ([obj isKindOfClass:NSDictionary.class]) return obj[key];
        SEL s=NSSelectorFromString(key);
        if ([obj respondsToSelector:s]) {
            NSMethodSignature *sig=[obj methodSignatureForSelector:s];
            if (!sig || sig.numberOfArguments!=2) return nil;
            const char *t=unqualified(sig.methodReturnType);
            if (!t || !*t) return nil;
            NSInvocation *inv=[NSInvocation invocationWithMethodSignature:sig];
            inv.target=obj; inv.selector=s;
            /* Do not invoke arbitrary void/block/pointer getters. */
            BOOL object=t[0]=='@' && t[1]!='?';
            BOOL scalar=strchr("cCsSiIlLqQBfd",t[0])!=NULL && t[1]==0;
            if (!object&&!scalar) return nil;
            [inv invoke];
            if (object) { __unsafe_unretained id value=nil; [inv getReturnValue:&value]; return value; }
#define SN_BOX(code, type) case code: { type v=0; [inv getReturnValue:&v]; return @(v); }
            switch(t[0]) {
                SN_BOX('c',signed char) SN_BOX('C',unsigned char) SN_BOX('s',short) SN_BOX('S',unsigned short)
                SN_BOX('i',int) SN_BOX('I',unsigned int) SN_BOX('l',long) SN_BOX('L',unsigned long)
                SN_BOX('q',long long) SN_BOX('Q',unsigned long long) SN_BOX('B',BOOL) SN_BOX('f',float) SN_BOX('d',double)
                default: return nil;
            }
#undef SN_BOX
        }
        for (NSString *candidate in @[key, [@"_" stringByAppendingString:key]]) {
            Ivar iv=class_getInstanceVariable(object_getClass(obj),candidate.UTF8String);
            const char *type=iv?unqualified(ivar_getTypeEncoding(iv)):NULL;
            if (type && type[0]=='@' && type[1]!='?') return object_getIvar(obj,iv);
        }
    } @catch (__unused NSException *exception) {}
    return nil;
}
static id first(id obj, NSArray<NSString *> *keys) {
    for (NSString *key in keys) { id v=SNRead(obj,key); if (v && v!=NSNull.null) return v; }
    return nil;
}
static NSString *identifierDepth(id value, unsigned depth) {
    if (!value || value==NSNull.null || depth>2) return nil;
    NSString *s=nil;
    if ([value isKindOfClass:NSString.class]) s=value;
    else if ([value isKindOfClass:NSUUID.class]) s=[value UUIDString];
    else if ([value isKindOfClass:NSData.class] && [value length]==16) {
        s=[[[NSUUID alloc] initWithUUIDBytes:[value bytes]] UUIDString];
    } else {
        for(NSString *key in @[@"UUIDString",@"uuidString",@"stringValue",@"toString",@"uuid",@"value",@"id"]) {
            id child=SNRead(value,key);if([key isEqual:@"id"] && ![child isKindOfClass:NSData.class] && ![child isKindOfClass:NSUUID.class])continue;if(child && child!=value){NSString *u=identifierDepth(child,depth+1);if(u)return u;}
        }
    }
    if (!s) return nil;
    NSData *data=[s dataUsingEncoding:NSUTF8StringEncoding]; char uuid[SN_UUID_SIZE];
    return sn_uuid(data.bytes,data.length,uuid) ? @(uuid) : nil;
}
NSString *SNIdentifier(id value) {return identifierDepth(value,0);}

NSString *SNName(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *s=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length || s.length>128 || SNIdentifier(s)) return nil;
    if ([s rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return nil;
    if ([@[@"null",@"nil",@"(null)",@"(none)",@"undefined",@"<null>"] containsObject:s.lowercaseString]) return nil;
    if ([s hasPrefix:@"<"] && [s hasSuffix:@">"]) return nil;
    return [s copy];
}
NSDictionary *SNUserRecord(id obj, NSString *explicitID) {
    if (!obj) return nil;
    NSString *uid=SNIdentifier(explicitID) ?: SNIdentifier(first(obj,@[@"userId",@"userID",@"snapchatUserId",@"snapchatterId"]));
    if(!uid && [NSStringFromClass(object_getClass(obj)) hasPrefix:@"SCSnapchatter"])uid=SNIdentifier(SNRead(obj,@"id"));
    NSString *display=SNName(SNRead(obj,@"displayName")) ?: SNName(SNRead(obj,@"displayUsername"));
    NSString *username=SNName(SNRead(obj,@"username")) ?: SNName(SNRead(obj,@"userName"));
    /* A resolver's returned string is already associated with its explicit ID. */
    if (explicitID && [obj isKindOfClass:NSString.class]) display=SNName(obj);
    if (!uid || !(display ?: username)) return nil;
    return @{@"uid":uid,@"name":display ?: username,@"quality":display?@2:@1};
}
static void collectUsers(id obj, NSMutableArray *out, NSHashTable *seen, unsigned depth, unsigned *budget) {
    if (!obj || depth>5 || !*budget || out.count>=256 || [seen containsObject:obj]) return;
    --*budget; [seen addObject:obj];
    if ([obj isKindOfClass:NSArray.class] || [obj isKindOfClass:NSSet.class]) {
        NSUInteger n=0; for (id child in obj) { if (++n>256) break; collectUsers(child,out,seen,depth+1,budget); } return;
    }
    NSDictionary *u=SNUserRecord(obj,nil); if(u) [out addObject:u];
    for(NSString *key in @[@"sender",@"user",@"snapchatter",@"userInfo",@"users",@"friends",@"participants",@"members",@"results",@"items"]) {
        id child=SNRead(obj,key); if(child) collectUsers(child,out,seen,depth+1,budget);
    }
    /* A UUID-keyed user dictionary is unambiguous; do not bind a conversation
       title, recipient name or arbitrary key containing 'name' to a sender. */
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSUInteger n=0;
        for(id key in obj) { if(++n>256) break; NSString *uid=SNIdentifier(key); if(!uid)continue;
            id value=obj[key]; NSDictionary *v=SNUserRecord(value,uid); if(v) [out addObject:v];
        }
    }
}
NSArray<NSDictionary *> *SNUserRecords(id obj) {
    NSMutableArray *out=[NSMutableArray array]; unsigned budget=512;
    NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality|NSPointerFunctionsStrongMemory];
    collectUsers(obj,out,seen,0,&budget); return [out copy];
}
/* Description fallback is limited to one typed conversation object. It cannot
   merge participants from different conversations, unlike first-match regexes
   over an entire array. It never parses a name from a description. */
static NSString *section(NSString *s, NSString *key) {
    NSString *p=[NSString stringWithFormat:@"\\b%@\\s*:\\s*\\[",key];
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:p options:0 error:NULL];
    NSTextCheckingResult *m=[re firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];
    if(!m)return nil; NSUInteger start=NSMaxRange(m.range), level=1;
    for(NSUInteger i=start;i<s.length;i++) { unichar c=[s characterAtIndex:i]; if(c=='[')level++;if(c==']'&&!--level)return [s substringWithRange:NSMakeRange(start,i-start)]; }
    return nil;
}
static NSString *match(NSString *s, NSString *p) {
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:p options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m=[re firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];
    return m && m.numberOfRanges>1 && [m rangeAtIndex:1].location!=NSNotFound ? [s substringWithRange:[m rangeAtIndex:1]] : nil;
}
static NSArray *descriptionMembers(NSString *part, BOOL typing) {
    if(!part)return nil;
    part=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!part.length)return @[];
    /* Split only between complete entries. A nonempty unreadable list must
       remain unknown; returning [] would synthesize STOP for every member. */
    NSMutableArray *entries=[NSMutableArray array],*out=[NSMutableArray array];
    unichar stack[32];NSUInteger level=0,start=0;
    for(NSUInteger i=0;i<part.length;i++) {
        unichar c=[part characterAtIndex:i];
        if(c=='<'||c=='{'||c=='[') {if(level>=32)return nil;stack[level++]=c;}
        else if(c=='>'||c=='}'||c==']') {
            unichar opening=c=='>'?'<':c=='}'?'{':'[';
            if(!level||stack[level-1]!=opening)return nil;level--;
        } else if(c==','&&!level) {
            if(entries.count>=256)return nil;
            [entries addObject:[part substringWithRange:NSMakeRange(start,i-start)]];start=i+1;
        }
    }
    if(level||entries.count>=256)return nil;
    [entries addObject:[part substringFromIndex:start]];
    NSRegularExpression *fields=[NSRegularExpression regularExpressionWithPattern:@"\\buserId\\s*:" options:0 error:NULL];
    for(NSString *entry in entries) {
        NSString *uid=nil;
        if(typing) {
            if([fields numberOfMatchesInString:entry options:0 range:NSMakeRange(0,entry.length)]!=1)return nil;
            uid=SNIdentifier(match(entry,@"\\buserId\\s*:\\s*([^\\s,}\\]>]+)"));
        } else uid=SNIdentifier([entry stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
        if(!uid)return nil;
        [out addObject:@{@"uid":uid,@"rawState":@"unavailable"}];
    }
    return out;
}
static NSArray *members(id list, BOOL typing) {
    if(![list isKindOfClass:NSArray.class]&&![list isKindOfClass:NSSet.class])return nil;
    NSMutableArray *out=[NSMutableArray array];NSUInteger n=0;
    for(id v in list) {
        if(++n>256)return nil; NSString *uid=SNIdentifier(typing?first(v,@[@"userId",@"userID"]):v);
        if(!uid)return nil; id state=typing?SNRead(v,@"typingState"):nil;
        NSMutableDictionary *r=[@{@"uid":uid,@"rawState":[state isKindOfClass:NSNumber.class]||[state isKindOfClass:NSString.class]? [state copy] : @"unavailable"} mutableCopy];
        id flag=typing?SNRead(v,@"isTyping"):nil;
        if([flag isKindOfClass:NSNumber.class])r[@"active"]=@([flag boolValue]);
        [out addObject:[r copy]];
    }
    return out;
}
NSArray<NSDictionary *> *SNPresenceRecords(id obj) {
    id list=obj;
    if(![list isKindOfClass:NSArray.class])list=first(obj,@[@"activeConversations",@"conversations"]);
    if(![list isKindOfClass:NSArray.class] || [list count]>256)return nil;
    NSMutableArray *out=[NSMutableArray array];
    for(id convo in list) {
        NSString *uid=SNIdentifier(SNRead(convo,@"conversationId"));
        NSArray *typing=members(SNRead(convo,@"remoteTypingParticipants"),YES);
        NSArray *peeking=members(SNRead(convo,@"remotePeekingParticipantUserIds"),NO);
        BOOL fallback=NO;
        if(!uid||!typing||!peeking) {
            NSString *cls=NSStringFromClass(object_getClass(convo));
            /* NSDictionary descriptions are not a stable wire protocol. */
            if (![convo isKindOfClass:NSDictionary.class]) {
                NSString *desc=nil; @try {desc=[convo description];} @catch(__unused NSException *e) {}
                if ([desc isKindOfClass:NSString.class] && desc.length>0 && desc.length<=65536 && ([cls containsString:@"Presence"] || [desc hasPrefix:@"<typedObject SCCPresencePlatformActiveConversationInfo:"])) {
                    uid=uid ?: SNIdentifier(match(desc,@"\\bconversationId\\s*:\\s*([^\\s,}\\]>]+)"));
                    typing=typing ?: descriptionMembers(section(desc,@"remoteTypingParticipants"),YES);
                    peeking=peeking ?: descriptionMembers(section(desc,@"remotePeekingParticipantUserIds"),NO);
                    fallback=YES;
                }
            }
        }
        if(!uid||!typing)return nil; /* Do not synthesize a STOP from an unreadable snapshot. */
        [out addObject:@{@"conversation":uid,@"typing":typing,@"peeking":peeking ?: @[],@"peekingKnown":@(peeking!=nil),@"fallback":@(fallback)}];
    }
    return [out copy];
}
static BOOL ownedFamily(NSString *s) {
    /* Objective-C method families carry +1 return ownership; the generic +0
       wrappers below must not replace them (init/new/copy/alloc). */
    return [s hasPrefix:@"init"]||[s hasPrefix:@"new"]||[s hasPrefix:@"copy"]||[s hasPrefix:@"mutableCopy"]||[s hasPrefix:@"alloc"];
}
BOOL SNInstallHook(Class cls, SEL sel, SNHookObserver observer) {
    if (!cls||!sel||!observer)return NO;
    static NSMutableSet *installed; static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once,^{installed=[NSMutableSet set];lock=[NSObject new];});
    @synchronized(lock) {
        NSString *name=NSStringFromSelector(sel);
        if(ownedFamily(name)||[name isEqualToString:@"dealloc"]||[name hasPrefix:@"."]||[name isEqualToString:@"applicationWillTerminate:"])return NO;
        NSString *key=[NSString stringWithFormat:@"%p/%@",cls,name];if([installed containsObject:key])return NO;
        /* Only this class's own method table. No inherited Method mutation. */
        unsigned count=0;Method *list=class_copyMethodList(cls,&count);Method m=NULL;
        for(unsigned i=0;i<count;i++)if(method_getName(list[i])==sel){m=list[i];break;}free(list);
        if(!m)return NO;
        unsigned argc=method_getNumberOfArguments(m);if(argc<2||argc>6)return NO;argc-=2;
        char *ret=method_copyReturnType(m);const char *r=unqualified(ret);
        BOOL isVoid=r&&r[0]=='v'&&r[1]==0;
        BOOL isObject=r&&r[0]=='@'&&r[1]!='?';
        char booleanType=(r&&r[1]==0&&(r[0]=='B'||r[0]=='c'))?r[0]:0;free(ret);
        if(!isVoid&&!isObject&&!booleanType)return NO;
        for(unsigned i=0;i<argc;i++) {
            char *raw=method_copyArgumentType(m,i+2);const char *t=unqualified(raw);
            BOOL ok=t&&t[0]=='@';free(raw);if(!ok)return NO;
        }
        IMP original=method_getImplementation(m);if(!original)return NO;
        SNHookObserver observe=[observer copy];IMP replacement=NULL;
        if(isVoid) {
            if(argc==0) replacement=imp_implementationWithBlock(^(id self){((void(*)(id,SEL))original)(self,sel);SNInspect(^{observe(self,@[],nil);});});
            else if(argc==1) replacement=imp_implementationWithBlock(^(id self,id a){((void(*)(id,SEL,id))original)(self,sel,a);SNInspect(^{observe(self,@[a?:NSNull.null],nil);});});
            else if(argc==2) replacement=imp_implementationWithBlock(^(id self,id a,id b){((void(*)(id,SEL,id,id))original)(self,sel,a,b);SNInspect(^{observe(self,@[a?:NSNull.null,b?:NSNull.null],nil);});});
            else if(argc==3) replacement=imp_implementationWithBlock(^(id self,id a,id b,id c){((void(*)(id,SEL,id,id,id))original)(self,sel,a,b,c);SNInspect(^{observe(self,@[a?:NSNull.null,b?:NSNull.null,c?:NSNull.null],nil);});});
            else if(argc==4) replacement=imp_implementationWithBlock(^(id self,id a,id b,id c,id d){((void(*)(id,SEL,id,id,id,id))original)(self,sel,a,b,c,d);SNInspect(^{observe(self,@[a?:NSNull.null,b?:NSNull.null,c?:NSNull.null,d?:NSNull.null],nil);});});
        } else if(booleanType) {
            /* B is C _Bool; c is signed char (BOOL on some runtimes). Keep
               the original ABI and return value, including NO. No void cast. */
#define SN_BOOL_WRAPPERS(T) \
            if(argc==0) replacement=imp_implementationWithBlock(^T(id self){T v=((T(*)(id,SEL))original)(self,sel);SNInspect(^{observe(self,@[],@(v));});return v;}); \
            else if(argc==1) replacement=imp_implementationWithBlock(^T(id self,id a){T v=((T(*)(id,SEL,id))original)(self,sel,a);SNInspect(^{observe(self,@[a?:NSNull.null],@(v));});return v;}); \
            else if(argc==2) replacement=imp_implementationWithBlock(^T(id self,id a,id b){T v=((T(*)(id,SEL,id,id))original)(self,sel,a,b);SNInspect(^{observe(self,@[a?:NSNull.null,b?:NSNull.null],@(v));});return v;}); \
            else return NO;
            if(booleanType=='B'){SN_BOOL_WRAPPERS(_Bool)}else{SN_BOOL_WRAPPERS(signed char)}
#undef SN_BOOL_WRAPPERS
        } else {
            if(argc==0) replacement=imp_implementationWithBlock(^id(id self){id v=((id(*)(id,SEL))original)(self,sel);SNInspect(^{observe(self,@[],v);});return v;});
            else if(argc==1) replacement=imp_implementationWithBlock(^id(id self,id a){id v=((id(*)(id,SEL,id))original)(self,sel,a);SNInspect(^{observe(self,@[a?:NSNull.null],v);});return v;});
            else if(argc==2) replacement=imp_implementationWithBlock(^id(id self,id a,id b){id v=((id(*)(id,SEL,id,id))original)(self,sel,a,b);SNInspect(^{observe(self,@[a?:NSNull.null,b?:NSNull.null],v);});return v;});
            else return NO;
        }
        if(!replacement)return NO;
        method_setImplementation(m,replacement);[installed addObject:key];return YES;
    }
}
