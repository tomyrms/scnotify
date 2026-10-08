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
        for(NSString *key in @[@"UUIDString",@"uuidString",@"stringValue",@"uuid",@"value"]) {
            id child=SNRead(value,key);if(child && child!=value){NSString *u=identifierDepth(child,depth+1);if(u)return u;}
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
    if(!part)return nil; NSMutableArray *out=[NSMutableArray array];
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:(typing?@"userId\\s*:\\s*([0-9a-fA-F-]{36})":@"([0-9a-fA-F-]{36})") options:0 error:NULL];
    for(NSTextCheckingResult *m in [re matchesInString:part options:0 range:NSMakeRange(0,part.length)]) {
        NSString *uid=SNIdentifier([part substringWithRange:[m rangeAtIndex:1]]);if(uid) [out addObject:@{@"uid":uid,@"rawState":@"unavailable"}];
        if(out.count>=256)break;
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
                if (desc.length<=65536 && ([cls containsString:@"Presence"] || [desc hasPrefix:@"<typedObject SCCPresencePlatformActiveConversationInfo:"])) {
                    uid=uid ?: SNIdentifier(match(desc,@"\\bconversationId\\s*:\\s*([0-9a-fA-F-]{36})"));
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
static NSString *eventID(id obj) {
    id value=first(obj,@[@"messageId",@"messageID",@"snapId",@"snapID",@"clientMessageId"]);
    if([value isKindOfClass:NSNumber.class])return [value longLongValue]>0?[value stringValue]:nil;
    if([value isKindOfClass:NSUUID.class])return [[value UUIDString] lowercaseString];
    if([value isKindOfClass:NSString.class] && [value length]>0 && [value length]<=128 && [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound && [value rangeOfString:@"|"].location==NSNotFound) return [value copy];
    return nil;
}
static void collectReceived(id obj, NSString *hint, NSMutableArray *out, unsigned depth, unsigned *budget) {
    if(!obj||depth>4||!*budget||out.count>=128)return;--*budget;
    if([obj isKindOfClass:NSArray.class]) {NSUInteger n=0;for(id c in obj){if(++n>128)break;collectReceived(c,hint,out,depth+1,budget);}return;}
    NSString *cls=NSStringFromClass(object_getClass(obj));NSString *kind=hint;
    if([cls isEqualToString:@"SOJUReceivedSnap"])kind=@"snap";
    NSString *type=first(obj,@[@"eventType",@"messageType",@"contentType"]);
    if([type isKindOfClass:NSString.class]) {
        NSString *upper=type.uppercaseString;
        if([@[@"READ",@"READ_RECEIPT",@"DELIVERED",@"DELIVERY_RECEIPT",@"SNAP_OPENED",@"SNAP_STATE",@"TYPING",@"CALLER_PUSH"] containsObject:upper])return;
        if([@[@"SNAP",@"RECEIVED_SNAP",@"SNAP_RECEIVED"] containsObject:upper])kind=@"snap";
        else if([@[@"CHAT",@"TEXT",@"CHAT_MESSAGE",@"MESSAGE_RECEIVED"] containsObject:upper])kind=@"message";
        /* Numeric/unknown protobuf enum values are deliberately not guessed. */
    }
    NSString *sender=SNIdentifier(first(obj,@[@"senderId",@"senderUserId",@"fromUserId"]));
    id senderObject=SNRead(obj,@"sender");
    sender=sender ?: SNIdentifier(first(senderObject,@[@"userId",@"userID",@"snapchatUserId"]));
    NSString *convo=SNIdentifier(first(obj,@[@"conversationId",@"conversationID"]));
    NSString *eid=eventID(obj);
    id outgoing=first(obj,@[@"isOutgoing",@"outgoing",@"isFromMe"]);
    id historical=first(obj,@[@"isHistorical",@"isHistory",@"fromHistory"]);
    if([historical isKindOfClass:NSNumber.class]&&[historical boolValue])return;
    if(kind&&sender&&convo&&eid&&!([outgoing isKindOfClass:NSNumber.class]&&[outgoing boolValue])) {
        NSMutableDictionary *r=[@{@"kind":kind,@"uid":sender,@"conversation":convo,@"event":eid} mutableCopy];
        NSDictionary *u=SNUserRecord(senderObject,sender);
        NSString *name=u[@"name"] ?: SNName(first(obj,@[@"senderDisplayName",@"senderUsername"]));
        if(name)r[@"name"]=name;
        id ts=first(obj,@[@"timestamp",@"createdAt",@"sentAt",@"creationTimestamp"]);
        if([ts isKindOfClass:NSNumber.class])r[@"timestamp"]=ts;
        if([ts isKindOfClass:NSDate.class])r[@"timestamp"]=@([ts timeIntervalSince1970]);
        [out addObject:[r copy]];
    }
    for(NSString *key in @[@"message",@"snap",@"receivedSnap",@"receivedMessage",@"messages",@"snaps",@"updates",@"items"]) {
        id child=SNRead(obj,key); if(child && child!=obj)collectReceived(child,hint,out,depth+1,budget);
    }
}
NSArray<NSDictionary *> *SNReceivedRecords(id obj, NSString *hint) {
    NSMutableArray *out=[NSMutableArray array];unsigned budget=256;collectReceived(obj,hint,out,0,&budget);return [out copy];
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
        unsigned argc=method_getNumberOfArguments(m);if(argc<2||argc>5)return NO;argc-=2;
        char *ret=method_copyReturnType(m);const char *r=unqualified(ret);
        BOOL isVoid=r&&r[0]=='v'&&r[1]==0;
        BOOL isObject=r&&r[0]=='@'&&r[1]!='?';free(ret);
        if(!isVoid&&!isObject)return NO;
        for(unsigned i=0;i<argc;i++) {
            char *raw=method_copyArgumentType(m,i+2);const char *t=unqualified(raw);
            BOOL ok=t&&t[0]=='@';free(raw);if(!ok)return NO;
        }
        IMP original=method_getImplementation(m);if(!original)return NO;
        SNHookObserver observe=[observer copy];IMP replacement=NULL;
        if(isVoid) switch(argc) {
            case 0: replacement=imp_implementationWithBlock(^(id self){((void(*)(id,SEL))original)(self,sel);SNInspect(^{observe(self,@[],nil);});});break;
            case 1: replacement=imp_implementationWithBlock(^(id self,id a){((void(*)(id,SEL,id))original)(self,sel,a);SNInspect(^{observe(self,@[a?:NSNull.null],nil);});});break;
            case 2: replacement=imp_implementationWithBlock(^(id self,id a,id b){((void(*)(id,SEL,id,id))original)(self,sel,a,b);SNInspect(^{observe(self,@[a?:NSNull.null,b?:NSNull.null],nil);});});break;
            case 3: replacement=imp_implementationWithBlock(^(id self,id a,id b,id c){((void(*)(id,SEL,id,id,id))original)(self,sel,a,b,c);SNInspect(^{observe(self,@[a?:NSNull.null,b?:NSNull.null,c?:NSNull.null],nil);});});break;
        }
        else switch(argc) {
            case 0: replacement=imp_implementationWithBlock(^id(id self){id v=((id(*)(id,SEL))original)(self,sel);SNInspect(^{observe(self,@[],v);});return v;});break;
            case 1: replacement=imp_implementationWithBlock(^id(id self,id a){id v=((id(*)(id,SEL,id))original)(self,sel,a);SNInspect(^{observe(self,@[a?:NSNull.null],v);});return v;});break;
            case 2: replacement=imp_implementationWithBlock(^id(id self,id a,id b){id v=((id(*)(id,SEL,id,id))original)(self,sel,a,b);SNInspect(^{observe(self,@[a?:NSNull.null,b?:NSNull.null],v);});return v;});break;
            default:return NO;
        }
        if(!replacement)return NO;
        method_setImplementation(m,replacement);[installed addObject:key];return YES;
    }
}
