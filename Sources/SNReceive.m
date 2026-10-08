#import "SNReceive.h"
#import "SNRuntime.h"
#import "SNContent.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

static id rxFirst(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) { id value=SNRead(object,key); if(value && value!=NSNull.null)return value; }
    return nil;
}
static BOOL rxTrue(id object, NSArray<NSString *> *keys) {
    /* OR all flags: false in one alias must not hide true in another. */
    for(NSString *key in keys){id value=SNRead(object,key);if([value isKindOfClass:NSNumber.class]&&[value boolValue])return YES;}
    return NO;
}
NSString *SNMessageIdentifier(id value) {
    if([value isKindOfClass:NSUUID.class])return [[value UUIDString] lowercaseString];
    if([value isKindOfClass:NSNumber.class]) {
        /* longLongValue rejects valid uint64 server IDs above INT64_MAX.
           Use the lossless decimal representation; reject floats and bools. */
        if(CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())return nil;
        const char *type=[value objCType];
        if(!type||strchr("fd",type[0]))return nil;
        NSString *s=[value stringValue];
        if(!s.length||[s isEqual:@"0"]||[s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound)return nil;
        return s;
    }
    if(![value isKindOfClass:NSString.class]||![value length]||[value length]>128)return nil;
    if([value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound||[value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound||[value rangeOfString:@"|"].location!=NSNotFound||[value isEqual:@"0"])return nil;
    return SNIdentifier(value) ?: [value copy];
}
static id rxDescriptor(id object) {
    id fallback=nil;
    for(NSString *key in @[@"descriptor",@"messageDescriptor"]) {
        id candidate=SNRead(object,key);if(!candidate||candidate==NSNull.null)continue;
        if(!fallback)fallback=candidate;
        /* GPBMessage may expose a schema descriptor as well as a message's
           own descriptor. Do not let the schema hide messageDescriptor. */
        if(rxFirst(candidate,@[@"messageId",@"messageID",@"conversationId",@"conversationID"]))return candidate;
    }
    return fallback;
}
static NSString *rxConversation(id object) {
    NSString *cid=SNIdentifier(rxFirst(object,@[@"conversationId",@"conversationID",@"conversationUuid"]));
    id descriptor=rxDescriptor(object);
    return cid ?: SNIdentifier(rxFirst(descriptor,@[@"conversationId",@"conversationID"]));
}
NSString *SNCallbackConversation(NSString *selector, NSArray *arguments) {
    /* Only explicitly named conversation parameters establish this context.
       A UUID in an arbitrary argument is never assumed to be a conversation. */
    NSArray *labels=[selector componentsSeparatedByString:@":"];
    NSSet *accepted=[NSSet setWithArray:@[@"conversation",@"conversationId",@"conversationID",@"inConversation",@"inConversationId"]];
    for(NSUInteger i=0;i<arguments.count&&i<labels.count;i++) {
        if(![accepted containsObject:labels[i]])continue;
        NSString *cid=SNIdentifier(arguments[i]) ?: rxConversation(arguments[i]);if(cid)return cid;
    }
    return nil;
}
static BOOL native14171;
void SNSetReceiveHostVersion(NSString *version) {
    @synchronized(SNReceiveTracker.class){native14171=[version isEqualToString:@"14.17.1"];}
}
static BOOL nativeMessage(id object) {
    /* A numeric enum on telemetry or an arbitrary dictionary is NOT a message. */
    return [NSStringFromClass(object_getClass(object)) isEqualToString:@"SCNMessagingMessage"];
}
static SNReceiveKind nativeKind(id object,id content,NSString **via) {
    if(!nativeMessage(object))return SN_RX_NONE;
    if(rxTrue(object,@[@"isStatusMessage",@"isSystemConversationRetentionMessage",@"isScreenRecording",@"isErasedSnapStatusMessage",@"isStickerReaction",@"isErased"])){
        *via=@"host-control-predicate";return SN_RX_CONTROL;
    }
    BOOL chat=rxTrue(object,@[@"isTextMessage",@"isChatMediaMessage",@"isVoiceNote",@"isStickerMessage",@"isContentShareMessage",@"isStoryReplyMessage",@"isSingleImageChatMedia",@"isSingleImageOrVideoChatMedia",@"isBitmojiSticker",@"isBloopMessage",@"isSpotlightStoryShareMessage",@"isSpotlightCommentShareMessage",@"isBitmojiUserShare"]);
    BOOL snap=rxTrue(object,@[@"isSnapMessage",@"isSnap",@"isTinySnapMessage"]);
    if(chat&&snap){*via=@"conflicting-native-predicates";return SN_RX_NONE;}
    if(chat||snap){*via=@"host-message-predicate";return snap?SN_RX_SNAP:SN_RX_MESSAGE;}
    BOOL supported=NO;@synchronized(SNReceiveTracker.class){supported=native14171;}
    if(!supported||![NSStringFromClass(object_getClass(content)) isEqualToString:@"SCNMessagingMessageContent"])return SN_RX_NONE;
    id value=SNRead(content,@"contentType"),has=SNRead(content,@"hasContentType");
    if([has isKindOfClass:NSNumber.class]&&![has boolValue])return SN_RX_NONE;
    if(![value isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())return SN_RX_NONE;
    const char *type=[value objCType];if(!type||strchr("fd",type[0]))return SN_RX_NONE;
    /* The compatibility table covers only SNAP=0 and CHAT=1. Native semantic
       getters above handle media/notes/stickers without guessing enum numbers. */
    SNReceiveKind kind=sn_receive_native_content_kind(NSStringFromClass(object_getClass(content)).UTF8String,"14.17.1",[value longLongValue]);
    if(kind!=SN_RX_NONE)*via=@"native-14.17.1-content-enum";
    return kind;
}
NSString *SNLocalAccountIdentifier(id object) {
    /* Do not confuse senderId/userId on a message with the local account. */
    return SNIdentifier(rxFirst(object,@[@"currentUserId",@"loggedInUserId",@"selfUserId"]));
}
NSDictionary *SNResolveReceiveDirection(NSDictionary *event,NSString *account,BOOL knownRemote) {
    NSMutableDictionary *r=[event mutableCopy];
    if(account.length){r[@"incoming"]=@(![account isEqual:r[@"uid"]]);r[@"directionSource"]=@"local-account";}
    else if([r[@"incoming"] isKindOfClass:NSNumber.class])r[@"directionSource"]=@"explicit-host-flag";
    else if(knownRemote){r[@"incoming"]=@YES;r[@"directionSource"]=@"remote-presence";}
    else r[@"directionSource"]=@"unknown";
    return [r copy];
}
static NSDictionary *typeMappings;
void SNSetReceiveTypeMappings(NSDictionary *mappings) {
    NSMutableDictionary *clean=[NSMutableDictionary dictionary];
    if([mappings isKindOfClass:NSDictionary.class])for(id key in mappings) {
        if(clean.count>=64)break;
        if(![key isKindOfClass:NSString.class]||[key length]>180||![mappings[key] isKindOfClass:NSDictionary.class])continue;
        NSMutableDictionary *values=[NSMutableDictionary dictionary];
        for(id raw in mappings[key]) {
            if(values.count>=64)break;
            NSString *kind=mappings[key][raw];
            if([raw isKindOfClass:NSString.class]&&[raw length]<=20&&([kind isEqual:@"message"]||[kind isEqual:@"snap"]||[kind isEqual:@"control"]))values[raw]=kind;
        }
        if(values.count)clean[key]=[values copy];
    }
    @synchronized(SNReceiveTracker.class){typeMappings=[clean copy];}
}
static NSString *enumName(id object, NSString *field, NSNumber *number) {
    /* GPB carries its enum descriptor at runtime. Ask it instead of importing
       a numerical table from a different platform or Snapchat version. */
    @try {
        id descriptor=SNRead([object class],@"descriptor");
        id fields=SNRead(descriptor,@"fields");
        if(![fields isKindOfClass:NSArray.class]||[fields count]>256)return nil;
        for(id f in fields) {
            if(![SNRead(f,@"name") isEqual:field])continue;
            id e=SNRead(f,@"enumDescriptor");if(!e)return nil;
            for(NSString *method in @[@"textFormatNameForValue:",@"enumNameForValue:"]) {
                SEL sel=NSSelectorFromString(method);NSMethodSignature *sig=[e methodSignatureForSelector:sel];
                if(!sig||sig.numberOfArguments!=3||sig.methodReturnType[0]!='@'||sig.methodReturnType[1]=='?')continue;
                const char *arg=[sig getArgumentTypeAtIndex:2];
                if(strcmp(arg,@encode(int32_t)))continue;
                long long raw=number.longLongValue;if(raw<INT32_MIN||raw>INT32_MAX)return nil;
                int32_t v=(int32_t)raw;NSInvocation *inv=[NSInvocation invocationWithMethodSignature:sig];
                inv.target=e;inv.selector=sel;[inv setArgument:&v atIndex:2];[inv invoke];
                __unsafe_unretained id result=nil;[inv getReturnValue:&result];
                if([result isKindOfClass:NSString.class])return result;
            }
        }
    } @catch(__unused NSException *e) {}
    return nil;
}
static SNReceiveKind kindForField(id object, NSString *field, BOOL *present) {
    NSString *hasKey=[@"has" stringByAppendingString:[field stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:[[field substringToIndex:1] uppercaseString]]];
    id has=SNRead(object,hasKey);
    if([has isKindOfClass:NSNumber.class]&&![has boolValue])return SN_RX_NONE;
    id value=SNRead(object,field);if(!value||value==NSNull.null)return SN_RX_NONE;*present=YES;
    NSString *symbol=[value isKindOfClass:NSString.class]?value:nil;
    if([value isKindOfClass:NSNumber.class]) {
        const char *encoding=[value objCType];
        if(CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()||!encoding||strchr("fd",encoding[0]))return SN_RX_NONE;
        symbol=enumName(object,field,value);
        if(!symbol) {
            NSString *key=[NSString stringWithFormat:@"%@.%@",NSStringFromClass(object_getClass(object)),field];
            NSString *mapped=nil;@synchronized(SNReceiveTracker.class){mapped=typeMappings[key][[value stringValue]];}
            if([mapped isEqual:@"snap"])return SN_RX_SNAP;
            if([mapped isEqual:@"message"])return SN_RX_MESSAGE;
            if([mapped isEqual:@"control"])return SN_RX_CONTROL;
        }
    }else if(!symbol){id name=rxFirst(value,@[@"name",@"enumName",@"stringValue"]);if([name isKindOfClass:NSString.class])symbol=name;}
    return sn_receive_kind(symbol.UTF8String);
}
static void reject(NSMutableDictionary *counts,NSString *reason) {counts[reason]=@([counts[reason] unsignedIntegerValue]+1);}
static NSDictionary *shape(id object) {
    NSMutableDictionary *fields=[NSMutableDictionary dictionary];
    /* Only field availability, class names and numeric enum values. No sender
       identifiers, message bodies, attachment bytes, tokens or descriptions. */
    for(NSString *key in @[@"conversationId",@"descriptor",@"messageDescriptor",@"messageId",@"senderId",@"messageContent",@"messageType",@"contentType",@"eventType",@"messages",@"message",@"items",@"metadata",@"timestamp",@"createdAt",@"creationTimestamp",@"creationTimestampMs",@"messageCreationTimestamp",@"isSender",@"isIncoming",@"currentUserId",@"isTextMessage",@"isSnapMessage",@"isSnap",@"isStatusMessage",@"isChatMediaMessage",@"isVoiceNote"]){
        id v=SNRead(object,key);if(v&&v!=NSNull.null){
            if(( [key isEqual:@"contentType"]||[key isEqual:@"messageType"]||[key isEqual:@"eventType"])&&[v isKindOfClass:NSNumber.class])fields[key]=@{ @"class":NSStringFromClass(object_getClass(v)),@"enum":v};
            else if([key hasPrefix:@"is"]&&[v isKindOfClass:NSNumber.class])fields[key]=@([v boolValue]);
            else fields[key]=NSStringFromClass(object_getClass(v));
        }
    }
    NSMutableArray *getters=[NSMutableArray array];
    /* Enumerate selector metadata, without calling unknown methods. This
       makes a new private object layout diagnosable without dumping content. */
    Class cls=object_getClass(object);const char *className=class_getName(cls);
    if(className&&(!strncmp(className,"SC",2)||!strncmp(className,"SOJU",4))) {
        unsigned count=0;Method *methods=class_copyMethodList(cls,&count);
        for(unsigned i=0;i<count&&getters.count<64;i++) {
            Method m=methods[i];if(method_getNumberOfArguments(m)!=2)continue;
            const char *name=sel_getName(method_getName(m));
            if(!strcmp(name,"init")||!strcmp(name,"description")||name[0]=='_')continue;
            char *type=method_copyReturnType(m);BOOL value=type&&(type[0]=='@'||strchr("cCsSiIlLqQBfd",type[0]));free(type);
            if(value)[getters addObject:@(name)];
        }
        free(methods);
    }
    return @{@"class":NSStringFromClass(object_getClass(object)),@"fields":[fields copy],@"declaredGetters":[getters copy]};
}
static void collect(id obj,NSString *inheritedConversation,NSString *hint,NSMutableArray *out,
                    NSMutableDictionary *rejected,NSMutableArray *shapes,NSHashTable *path,
                    NSMutableSet *eventKeys,NSMutableDictionary *identities,unsigned depth,unsigned *budget) {
    if(!obj||obj==NSNull.null)return;
    if(!*budget||depth>8){reject(rejected,@"traversal-limit");return;}
    --*budget;if([path containsObject:obj]){reject(rejected,@"cycle");return;}
    if([obj isKindOfClass:NSString.class]||[obj isKindOfClass:NSNumber.class]||[obj isKindOfClass:NSData.class])return;
    if(out.count>=256){reject(rejected,@"batch-limit");return;}
    [path addObject:obj];
    @try {
        if([obj isKindOfClass:NSArray.class]||[obj isKindOfClass:NSSet.class]) {
            for(id item in obj){if(!*budget)break;collect(item,inheritedConversation,hint,out,rejected,shapes,path,eventKeys,identities,depth+1,budget);}return;
        }
        if(rxTrue(obj,@[@"isHistorical",@"isHistory",@"fromHistory"])) {reject(rejected,@"history");return;}
        if(rxTrue(obj,@[@"isOutgoing",@"outgoing",@"isFromMe"])) {reject(rejected,@"outgoing");return;}
        id metadata=rxFirst(obj,@[@"metadata",@"messageMetadata"]);
        if(rxTrue(metadata,@[@"isHistorical",@"isHistory",@"fromHistory"])) {reject(rejected,@"history");return;}
        if(rxTrue(metadata,@[@"isOutgoing",@"outgoing",@"isFromMe"])) {reject(rejected,@"outgoing");return;}
        NSString *conversation=rxConversation(obj) ?: rxConversation(metadata) ?: inheritedConversation;
        id descriptor=rxDescriptor(obj);
        id senderObject=rxFirst(obj,@[@"sender",@"fromUser"]);
        NSString *sender=SNIdentifier(rxFirst(obj,@[@"senderId",@"senderUserId",@"fromUserId",@"senderID",@"snapchatterUserId"]))
            ?: SNIdentifier(rxFirst(metadata,@[@"senderId",@"senderUserId"])) ?: SNIdentifier(rxFirst(descriptor,@[@"senderId",@"senderUserId"])) ?: SNIdentifier(senderObject)
            ?: SNIdentifier(rxFirst(senderObject,@[@"userId",@"userID",@"snapchatUserId"]));
        NSString *eid=SNMessageIdentifier(rxFirst(obj,@[@"messageId",@"messageID",@"serverMessageId",@"snapId",@"snapID",@"clientMessageId"]))
            ?: SNMessageIdentifier(rxFirst(descriptor,@[@"messageId",@"messageID",@"serverMessageId"]));
        /* Seed even an empty conversation / encrypted model in snapshot mode.
           Otherwise a later decryption or first message is mistaken for a
           baseline, or an old unknown type can appear to be newly received. */
        if(conversation&&(identities[conversation]||identities.count<128)) {
            if(!identities[conversation])identities[conversation]=[NSMutableSet set];
            NSMutableSet *ids=identities[conversation];if(eid&&ids.count<2048)[ids addObject:eid];
        }
        BOOL declared=NO;SNReceiveKind rootKind=SN_RX_NONE;
        for(NSString *field in @[@"eventType",@"messageType",@"contentType"]) {
            SNReceiveKind k=kindForField(obj,field,&declared);
            if(k==SN_RX_CONTROL){reject(rejected,@"control-event");return;}
            if(k!=SN_RX_NONE){
                if(rootKind!=SN_RX_NONE&&rootKind!=k){reject(rejected,@"conflicting-content-type");return;}
                rootKind=k;
            }
        }
        id content=rxFirst(obj,@[@"messageContent",@"contentEnvelope"]);
        BOOL contentDeclared=NO;SNReceiveKind contentKind=kindForField(content,@"contentType",&contentDeclared);
        if(contentKind==SN_RX_CONTROL){reject(rejected,@"control-event");return;}
        if(rootKind!=SN_RX_NONE&&contentKind!=SN_RX_NONE&&rootKind!=contentKind){reject(rejected,@"conflicting-content-type");return;}
        SNReceiveKind kind=contentKind!=SN_RX_NONE?contentKind:rootKind;
        NSString *cls=NSStringFromClass(object_getClass(obj));
        if(!declared&&!contentDeclared) {
            if([cls isEqual:@"SOJUReceivedSnap"]||[cls isEqual:@"SOJUReceivedSnapWithAttachment"])kind=SN_RX_SNAP;
            else if([cls isEqual:@"SOJUReceivedChatMessage"])kind=SN_RX_MESSAGE;
            else if([hint isEqual:@"snap"])kind=SN_RX_SNAP;
            else if([hint isEqual:@"message"])kind=SN_RX_MESSAGE;
        }
        NSString *kindSource=@"structured-type";
        NSString *nativeSource=nil;SNReceiveKind native=nativeKind(obj,content,&nativeSource);
        if(native==SN_RX_CONTROL){reject(rejected,@"control-event");return;}
        if([nativeSource isEqualToString:@"conflicting-native-predicates"]){reject(rejected,nativeSource);return;}
        if(native!=SN_RX_NONE){
            if(kind!=SN_RX_NONE&&kind!=native){reject(rejected,@"conflicting-content-type");return;}
            kind=native;kindSource=nativeSource;
        }
        BOOL candidate=eid||sender||content||declared||contentDeclared;
        if(!candidate&&shapes.count<8)[shapes addObject:shape(obj)];
        if(candidate) {
            NSString *reason=nil;
            if(kind!=SN_RX_MESSAGE&&kind!=SN_RX_SNAP)reason=@"unknown-content-type";
            else if(!sender)reason=@"missing-sender";
            else if(!conversation)reason=@"missing-conversation";
            else if(!eid)reason=@"missing-message-id";
            if(reason){reject(rejected,reason);if(shapes.count<8){[shapes addObject:shape(obj)];if(descriptor&&shapes.count<8)[shapes addObject:shape(descriptor)];if(content&&shapes.count<8)[shapes addObject:shape(content)];if(metadata&&shapes.count<8)[shapes addObject:shape(metadata)];}}
            else {
                NSString *type=kind==SN_RX_SNAP?@"snap":@"message";
                NSString *key=[@[conversation,sender,eid] componentsJoinedByString:@"|"];
                if(![eventKeys containsObject:key]) {
                    NSMutableDictionary *event=[@{@"kind":type,@"uid":sender,@"conversation":conversation,@"event":eid,@"kindSource":kindSource} mutableCopy];
                    if(kind==SN_RX_MESSAGE)event[@"subtype"]=SNContentSubtype(obj,content);
                    NSDictionary *u=SNUserRecord(senderObject,sender);
                    NSString *name=u[@"name"] ?: SNName(rxFirst(obj,@[@"senderDisplayName",@"senderUsername"]));if(name)event[@"name"]=name;
                    id ts=rxFirst(metadata,@[@"creationTimestamp",@"creationTimestampMs",@"messageCreationTimestamp",@"createdAt",@"createdAtMs",@"serverTimestamp",@"serverTimestampMs",@"timestamp"])
                        ?: rxFirst(obj,@[@"creationTimestamp",@"creationTimestampMs",@"messageCreationTimestamp",@"createdAt",@"createdAtMs",@"sentAt",@"serverTimestamp",@"timestamp"]);
                    if([ts isKindOfClass:NSDate.class])event[@"timestamp"]=@([ts timeIntervalSince1970]);
                    else if([ts isKindOfClass:NSNumber.class]){
                        double seconds=sn_receive_seconds([ts doubleValue]);
                        if(!isfinite(seconds)){reject(rejected,@"invalid-time");return;}event[@"timestamp"]=@(seconds);
                    }
                    id outgoing=SNRead(obj,@"isOutgoing") ?: SNRead(metadata,@"isOutgoing");
                    id hasOutgoing=SNRead(obj,@"hasIsOutgoing") ?: SNRead(metadata,@"hasIsOutgoing");
                    if([hasOutgoing isKindOfClass:NSNumber.class]&&![hasOutgoing boolValue])outgoing=nil;
                    if(rxTrue(obj,@[@"isIncoming"])||rxTrue(metadata,@[@"isIncoming"])||([outgoing isKindOfClass:NSNumber.class]&&![outgoing boolValue]))event[@"incoming"]=@YES;
                    id isSender=SNRead(obj,@"isSender") ?: SNRead(metadata,@"isSender");
                    id hasSender=SNRead(obj,@"hasIsSender") ?: SNRead(metadata,@"hasIsSender");
                    if([hasSender isKindOfClass:NSNumber.class]&&![hasSender boolValue])isSender=nil;
                    if([isSender isKindOfClass:NSNumber.class]){
                        if([isSender boolValue]){reject(rejected,@"outgoing");return;}
                        event[@"incoming"]=@YES;
                    }
                    /* A decoded type can still fail the snapshot date or
                       direction gate. Keep only field/selector metadata for
                       that diagnosis, never the timestamp, IDs or body. */
                    if((!event[@"timestamp"]||!event[@"incoming"])&&shapes.count<8){
                        [shapes addObject:shape(obj)];
                        if(metadata&&shapes.count<8)[shapes addObject:shape(metadata)];
                    }
                    [eventKeys addObject:key];[out addObject:[event copy]];
                }
            }
        }
        /* Traverse only structural envelopes, never message text or raw blobs.
           Inherit conversation context, not sender IDs or message IDs. */
        for(NSString *key in @[@"message",@"snap",@"receivedSnap",@"receivedMessage",@"messages",@"receivedMessages",@"newMessages",@"addedMessages",@"insertedMessages",@"snaps",@"updates",@"update",@"items",@"entries",@"conversation",@"conversations",@"conversationViewModel",@"viewModel",@"messageData",@"latestMessage",@"lastMessage",@"messageList",@"messagesArray",@"snapsArray",@"payload",@"notification",@"inAppNotification",@"userInfo"]){
            if(!*budget)break;id child=SNRead(obj,key);if(child)collect(child,conversation,hint,out,rejected,shapes,path,eventKeys,identities,depth+1,budget);
        }
    } @finally {[path removeObject:obj];}
}
NSDictionary *SNDecodeReceived(NSArray *arguments,NSString *conversation,NSString *hint) {
    NSMutableArray *events=[NSMutableArray array],*shapes=[NSMutableArray array];NSMutableDictionary *rejected=[NSMutableDictionary dictionary];
    NSHashTable *path=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality|NSPointerFunctionsStrongMemory];
    NSMutableSet *keys=[NSMutableSet set];NSMutableDictionary *identities=[NSMutableDictionary dictionary];unsigned budget=1024;
    if(conversation)identities[conversation]=[NSMutableSet set];
    @try {for(id arg in arguments){if(!budget)break;collect(arg,conversation,hint,events,rejected,shapes,path,keys,identities,0,&budget);}}
    @catch(__unused NSException *e){reject(rejected,@"object-exception");}
    if(!budget)reject(rejected,@"traversal-limit");
    NSMutableDictionary *detached=[NSMutableDictionary dictionary];
    for(NSString *cid in identities)detached[cid]=[identities[cid] allObjects];
    return @{@"events":[events copy],@"rejected":[rejected copy],@"shapes":[shapes copy],@"identities":[detached copy]};
}
NSDictionary *SNDecodeReceiveCallback(NSString *className,NSString *selector,NSArray *arguments) {
    NSString *cid=SNCallbackConversation(selector,arguments);NSArray *payloads=arguments;
    if([className isEqualToString:@"SCArroyoConversationDataUpdateAnnouncer"]&&
       [selector isEqualToString:@"onConversationUpdated:conversation:updatedMessages:removedMessages:"]) {
        if(arguments.count!=4)return @{@"events":@[],@"identities":@{},@"shapes":@[],@"rejected":@{@"callback-arity":@1}};
        cid=SNIdentifier(arguments[0]) ?: cid;
        /* arg 1 is a whole conversation; arg 3 contains deletions. Only the
           actual updatedMessages collection is a candidate for reception. */
        payloads=@[arguments[2]];
    }
    SNReceiveKind kind=sn_receive_hint(selector.UTF8String);
    NSDictionary *batch=SNDecodeReceived(payloads,cid,kind==SN_RX_SNAP?@"snap":kind==SN_RX_MESSAGE?@"message":nil);
    return batch;
}
void SNEnumerateReceiveBatches(NSString *className,NSString *selector,NSArray *arguments,void (^visit)(NSDictionary *)) {
    if(!visit)return;
    NSUInteger index=NSNotFound;
    if([className isEqual:@"SCArroyoConversationDataUpdateAnnouncer"]&&[selector isEqual:@"onConversationUpdated:conversation:updatedMessages:removedMessages:"]&&arguments.count==4)index=2;
    else if([selector isEqual:@"didReceiveMessages:"]||[selector isEqual:@"onMessagesReceived:"]||[selector isEqual:@"onNewMessages:"])index=0;
    else if([selector isEqual:@"conversation:didReceiveMessages:"]||[selector isEqual:@"conversationId:didReceiveMessages:"])index=1;
    id list=index<arguments.count?arguments[index]:nil;
    if([list isKindOfClass:NSSet.class])list=[list allObjects];
    if(![list isKindOfClass:NSArray.class]||[list count]<=128){visit(SNDecodeReceiveCallback(className,selector,arguments));return;}
    for(NSUInteger offset=0;offset<[list count];offset+=128){
        @autoreleasepool {
            NSMutableArray *args=[arguments mutableCopy];
            args[index]=[list subarrayWithRange:NSMakeRange(offset,MIN((NSUInteger)128,[list count]-offset))];
            visit(SNDecodeReceiveCallback(className,selector,args));
        }
    }
}
NSArray<NSDictionary *> *SNReceivedRecords(id obj,NSString *hint) {
    return SNDecodeReceived(obj?@[obj]:@[],nil,hint)[@"events"];
}

@interface SNReceiveTracker ()
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMutableDictionary *> *conversations;
@property(nonatomic) NSTimeInterval monitoringStart;
@end
@implementation SNReceiveTracker
- (instancetype)init {return [self initWithMonitoringStart:0];}
- (instancetype)initWithMonitoringStart:(NSTimeInterval)start {self=[super init];if(self){_conversations=[NSMutableDictionary dictionary];_monitoringStart=isfinite(start)&&start>0?start:0;}return self;}
- (void)reset {[self.conversations removeAllObjects];if(self.monitoringStart>0)self.monitoringStart=NSDate.date.timeIntervalSince1970;}
- (NSArray<NSDictionary *> *)newEventsInSnapshot:(NSArray<NSDictionary *> *)events wallTime:(NSTimeInterval)wall {
    NSMutableDictionary *identities=[NSMutableDictionary dictionary];
    for(NSDictionary *e in events){NSString *cid=e[@"conversation"];if(!cid||!e[@"event"])continue;if(!identities[cid])identities[cid]=[NSMutableArray array];[identities[cid] addObject:e[@"event"]];}
    return [self newEventsInBatch:@{@"events":events,@"identities":identities} wallTime:wall];
}
- (NSArray<NSDictionary *> *)newEventsInBatch:(NSDictionary *)batch wallTime:(NSTimeInterval)wall {
    if(!isfinite(wall)||wall<=0)return @[];
    NSDictionary *identities=batch[@"identities"] ?: @{};
    NSMutableDictionary *groups=[NSMutableDictionary dictionary];
    for(NSDictionary *e in batch[@"events"]){NSString *cid=e[@"conversation"];if(!cid)continue;if(!groups[cid])groups[cid]=[NSMutableArray array];[groups[cid] addObject:e];}
    NSMutableSet *conversations=[NSMutableSet setWithArray:identities.allKeys];[conversations addObjectsFromArray:groups.allKeys];
    NSMutableArray *out=[NSMutableArray array];
    for(NSString *cid in conversations) {
        NSMutableDictionary *state=self.conversations[cid];BOOL initial=!state;
        if(!state){
            if(self.conversations.count>=128){NSString *oldest=nil;double time=INFINITY;for(NSString *key in self.conversations){double t=[self.conversations[key][@"last"] doubleValue];if(t<time){time=t;oldest=key;}}if(oldest)[self.conversations removeObjectForKey:oldest];}
            state=[@{@"seen":[NSMutableOrderedSet orderedSet],@"start":@(wall),@"last":@(wall)} mutableCopy];self.conversations[cid]=state;
        }
        NSMutableOrderedSet *seen=state[@"seen"];
        NSMutableDictionary *waiting=state[@"waiting"];
        if(!waiting){waiting=[NSMutableDictionary dictionary];state[@"waiting"]=waiting;}
        NSMutableSet *decodedIDs=[NSMutableSet set];
        for(NSDictionary *e in groups[cid]) {
            NSString *key=e[@"event"];if(!key)continue;[decodedIDs addObject:key];
            BOOL known=[seen containsObject:key];
            if(!known&&seen.count>=8192){NSString *old=seen.firstObject;[seen removeObjectAtIndex:0];[waiting removeObjectForKey:old];}
            NSNumber *firstSeen=waiting[key];
            NSNumber *ts=e[@"timestamp"];
            BOOL fresh=ts&&sn_receive_time_valid(ts.doubleValue,wall);
            BOOL firstLive=initial&&self.monitoringStart>0&&[e[@"incoming"] boolValue]&&fresh&&ts.doubleValue>=self.monitoringStart;
            BOOL newlyDecoded=known&&firstSeen&&fresh&&ts.doubleValue>=firstSeen.doubleValue-1;
            if(!known)[seen addObject:key];
            if((!known&&(!initial||firstLive))||newlyDecoded) {
                double start=firstLive?self.monitoringStart:[state[@"start"] doubleValue]-1;
                if(fresh&&ts.doubleValue>=start){
                    if([e[@"directionSource"] isEqualToString:@"unknown"]){if(waiting.count<256)waiting[key]=@(fmin(wall,ts.doubleValue));continue;}
                    if(!e[@"incoming"]||[e[@"incoming"] boolValue])[out addObject:e];
                }
            }
            /* A first live batch with unresolved direction is retained until
               a later observation supplies evidence, not treated as history. */
            if(initial&&self.monitoringStart>0&&fresh&&ts.doubleValue>=self.monitoringStart&&[e[@"directionSource"] isEqualToString:@"unknown"]){
                if(waiting.count<256)waiting[key]=@(fmin(wall,ts.doubleValue));continue;
            }
            [waiting removeObjectForKey:key];
        }
        /* Remember first sighting only for unknown records appearing AFTER a
           baseline; delayed decoding of old baseline history stays silent. */
        for(NSString *eid in identities[cid]){
            if(![seen containsObject:eid]&&!initial&&![decodedIDs containsObject:eid]&&waiting.count<256)waiting[eid]=@(wall);
            if(![seen containsObject:eid]){if(seen.count>=8192){NSString *old=seen.firstObject;[seen removeObjectAtIndex:0];[waiting removeObjectForKey:old];}[seen addObject:eid];}
        }
        for(NSString *eid in [waiting allKeys])if(wall-[waiting[eid] doubleValue]>300)[waiting removeObjectForKey:eid];
        state[@"last"]=@(wall);
    }
    return [out copy];
}
@end
