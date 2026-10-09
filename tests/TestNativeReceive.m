#import <Foundation/Foundation.h>
#import "../Sources/SNReceive.h"
#import "../Sources/SNRuntime.h"
#include <stdint.h>
#include <stdlib.h>
static NSUInteger checks;
#define CHECK(x) do { checks++; if(!(x)){NSLog(@"FAILED native line %d: %s",__LINE__,#x);abort();} } while(0)
static NSString * const C=@"11111111-2222-3333-4444-555555555555";
static NSString * const U=@"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
static NSString * const ME=@"99999999-8888-7777-6666-555555555555";
static NSString * const CLS=@"SCArroyoConversationDataUpdateAnnouncer";
static NSString * const SELNAME=@"onConversationUpdated:conversation:updatedMessages:removedMessages:";
/* Exact class/field SHAPES from the supplied device schema. IDs, dates and
   predicate results below are synthetic, NOT captured message payloads. */
@interface SCNMessagingUUID : NSObject
@property(nonatomic,copy) NSString *valueForTest;
- (NSString *)toString;
@end
@implementation SCNMessagingUUID
- (NSString *)toString{return self.valueForTest;}
@end
@interface SCNMessagingMessageDescriptor : NSObject
@property(nonatomic,strong) SCNMessagingUUID *conversationId;
@property(nonatomic) uint64_t messageId;
@end
@implementation SCNMessagingMessageDescriptor
@end
@interface SCNMessagingMessageContent : NSObject
@property(nonatomic) NSInteger contentType;
@end
@implementation SCNMessagingMessageContent
@end
@interface SCNMessagingMessage : NSObject
@property(nonatomic,strong) SCNMessagingMessageDescriptor *descriptor;
@property(nonatomic,strong) SCNMessagingUUID *senderId;
@property(nonatomic,copy) NSString *conversationId;
@property(nonatomic,strong) SCNMessagingMessageContent *messageContent;
@property(nonatomic,strong) NSDictionary *metadata;
@property(nonatomic) BOOL isTextMessage;
@property(nonatomic) BOOL isSnapMessage;
@property(nonatomic) BOOL isStatusMessage;
@property(nonatomic) BOOL isVoiceNote;
@property(nonatomic) BOOL isVoiceNoteMessage;
@property(nonatomic) BOOL isChatMediaMessage;
@property(nonatomic) BOOL isStickerReaction;
@property(nonatomic) BOOL isErased;
@property(nonatomic) BOOL isTinySnapMessage;
@property(nonatomic,strong) NSNumber *isOutgoing;
@end
@implementation SCNMessagingMessage
@end
static SCNMessagingUUID *uuid(NSString *value){SCNMessagingUUID *u=[SCNMessagingUUID new];u.valueForTest=value;return u;}
static SCNMessagingMessage *msg(uint64_t mid,NSInteger kind) {
    SCNMessagingMessage *m=[SCNMessagingMessage new];m.descriptor=[SCNMessagingMessageDescriptor new];
    m.descriptor.conversationId=uuid(C);m.descriptor.messageId=mid;m.conversationId=C;m.senderId=uuid(U);
    m.messageContent=[SCNMessagingMessageContent new];m.messageContent.contentType=kind;
    m.metadata=@{@"creationTimestampMs":@1800000001000LL};return m;
}
static NSDictionary *decode(SCNMessagingMessage *m){return SNDecodeReceiveCallback(CLS,SELNAME,@[uuid(C),NSNull.null,@[m],@[]]);}
static NSDictionary *firstEvent(SCNMessagingMessage *m){return [decode(m)[@"events"] firstObject];}
static NSDictionary *prepared(SCNMessagingMessage *m,NSString *account,BOOL remote) {
    NSMutableDictionary *b=[decode(m) mutableCopy];NSMutableArray *events=[NSMutableArray array];
    for(NSDictionary *e in b[@"events"])[events addObject:SNResolveReceiveDirection(e,account,remote)];b[@"events"]=events;return b;
}
@interface RC4BoolHost : NSObject
@property(nonatomic) NSUInteger calls;
- (_Bool)present:(id)a delegate:(id)b;
- (signed char)legacy:(id)a delegate:(id)b;
- (int)notBoolean:(id)a;
@end
@implementation RC4BoolHost
- (_Bool)present:(id)a delegate:(__unused id)b {self.calls++;return [a boolValue];}
- (signed char)legacy:(id)a delegate:(__unused id)b {self.calls++;return [a charValue];}
- (int)notBoolean:(__unused id)a{return 7;}
@end
int main(void) {@autoreleasepool {
    SNSetReceiveTypeMappings(@{});SNSetReceiveHostVersion(@"14.17.1");
    CHECK([SNIdentifier(uuid(U)) isEqual:U]);CHECK(SNIdentifier(uuid(@"not-a-uuid"))==nil);
    SCNMessagingMessage *m=msg(UINT64_MAX,1);m.isTextMessage=YES;
    NSDictionary *e=firstEvent(m);CHECK([e[@"kind"] isEqual:@"message"]);CHECK([e[@"kindSource"] isEqual:@"host-message-predicate"]);
    CHECK([e[@"event"] isEqual:@"18446744073709551615"]);CHECK([e[@"uid"] isEqual:U]);CHECK([e[@"conversation"] isEqual:C]);
    CHECK([e[@"timestamp"] doubleValue]==1800000001);
    m.isTextMessage=NO;CHECK([firstEvent(m)[@"kind"] isEqual:@"message"]);
    CHECK([firstEvent(m)[@"kindSource"] isEqual:@"native-14.17.1-content-enum"]);
    m=msg(1,0);CHECK([firstEvent(m)[@"kind"] isEqual:@"snap"]);
    m.messageContent.contentType=6;CHECK(firstEvent(m)==nil);
    for(NSNumber *n in @[@2,@3,@4,@5]){m.messageContent.contentType=n.integerValue;CHECK(firstEvent(m)==nil);m.isChatMediaMessage=YES;CHECK([firstEvent(m)[@"kind"] isEqual:@"message"]);m.isChatMediaMessage=NO;}
    m.messageContent.contentType=999;CHECK(firstEvent(m)==nil);
    m.isVoiceNote=YES;CHECK([firstEvent(m)[@"kind"] isEqual:@"message"]);CHECK([firstEvent(m)[@"subtype"] isEqual:@"voice"]);m.isVoiceNote=NO;
    m.isVoiceNoteMessage=YES;CHECK([firstEvent(m)[@"subtype"] isEqual:@"voice"]);m.isVoiceNoteMessage=NO;
    m.isSnapMessage=YES;CHECK([firstEvent(m)[@"kind"] isEqual:@"snap"]);
    m.isTextMessage=YES;CHECK(firstEvent(m)==nil);CHECK([decode(m)[@"rejected"][@"conflicting-native-predicates"] integerValue]==1);
    m=msg(2,1);m.isTextMessage=YES;m.isStatusMessage=YES;CHECK(firstEvent(m)==nil);
    m.isStatusMessage=NO;m.isStickerReaction=YES;CHECK(firstEvent(m)==nil);
    m.isStickerReaction=NO;m.isErased=YES;CHECK(firstEvent(m)==nil);
    m=msg(3,0);SNSetReceiveHostVersion(@"15.0.0");CHECK(firstEvent(m)==nil);
    m.isSnapMessage=YES;CHECK([firstEvent(m)[@"kind"] isEqual:@"snap"]);
    m=msg(4,1);CHECK(firstEvent(m)==nil);m.isTextMessage=YES;CHECK([firstEvent(m)[@"kind"] isEqual:@"message"]);
    SNSetReceiveHostVersion(@"14.17.1");
    NSDictionary *dictionary=@{@"senderId":U,@"conversationId":C,@"messageId":@42,@"messageContent":@{@"contentType":@1}};
    CHECK([SNDecodeReceived(@[dictionary],nil,nil)[@"events"] count]==0);
    CHECK(sn_receive_source("SCNativeBlizzardLoggerDelegateImpl","onMessageReceived:")==SN_SOURCE_NONE);
    CHECK(sn_receive_source(CLS.UTF8String,SELNAME.UTF8String)==SN_SOURCE_SNAPSHOT);
    // Removed records and conversation-wide history must never be traversed.
    m=msg(5,1);NSDictionary *b=SNDecodeReceiveCallback(CLS,SELNAME,@[uuid(C),@{@"messages":@[msg(10,0)]},@[m],@[msg(11,0)]]);
    CHECK([b[@"events"] count]==1);CHECK([b[@"events"][0][@"event"] isEqual:@"5"]);
    CHECK([SNDecodeReceiveCallback(CLS,SELNAME,@[uuid(C),NSNull.null,@[],@[m]])[@"events"] count]==0);
    CHECK([SNDecodeReceiveCallback(CLS,SELNAME,@[uuid(C),NSNull.null,@[],@[]])[@"identities"][C] count]==0);
    CHECK([SNDecodeReceiveCallback(CLS,SELNAME,@[]) [@"rejected"][@"callback-arity"] integerValue]==1);
    m.descriptor.conversationId=nil;m.conversationId=nil;CHECK([firstEvent(m)[@"conversation"] isEqual:C]);
    for(NSString *field in @[@"createdAt",@"createdAtMs",@"creationTimestamp",@"creationTimestampMs",@"messageCreationTimestamp"]){m.metadata=@{field:@1800000001000LL};CHECK([firstEvent(m)[@"timestamp"] doubleValue]==1800000001);}
    m=msg(6,1);m.metadata=@{@"createdAt":@1800000001,@"isSender":@YES};CHECK(firstEvent(m)==nil);
    m.metadata=@{@"createdAt":@1800000001,@"isSender":@NO};CHECK([firstEvent(m)[@"incoming"] boolValue]);
    m.isOutgoing=@YES;CHECK(firstEvent(m)==nil);m.isOutgoing=nil;
    NSDictionary *in=SNResolveReceiveDirection(firstEvent(m),ME,NO);CHECK([in[@"incoming"] boolValue]);
    CHECK(![SNResolveReceiveDirection(firstEvent(m),U,YES)[@"incoming"] boolValue]);
    m=msg(7,1);CHECK([SNResolveReceiveDirection(firstEvent(m),nil,YES)[@"incoming"] boolValue]);
    CHECK([SNResolveReceiveDirection(firstEvent(m),nil,YES)[@"directionSource"] isEqual:@"remote-presence"]);
    CHECK(SNResolveReceiveDirection(firstEvent(m),nil,NO)[@"incoming"]==nil);
    CHECK(![SNResolveReceiveDirection(@{@"uid":U,@"incoming":@NO},nil,YES)[@"incoming"] boolValue]);
    CHECK(SNLocalAccountIdentifier(@{@"senderId":U,@"userId":U})==nil);
    CHECK([SNLocalAccountIdentifier(@{@"currentUserId":uuid(ME)}) isEqual:ME]);
    // Actual decision sequence: fresh remote chat, snap, second snap, replay.
    SNReceiveTracker *tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    CHECK([tracker newEventsInBatch:prepared(msg(100,1),nil,YES) wallTime:1800000002].count==1);
    CHECK([tracker newEventsInBatch:prepared(msg(101,0),nil,YES) wallTime:1800000002].count==1);
    CHECK([tracker newEventsInBatch:prepared(msg(102,0),nil,YES) wallTime:1800000002].count==1);
    CHECK([tracker newEventsInBatch:prepared(msg(102,0),nil,YES) wallTime:1800000002].count==0);
    m=msg(103,1);m.metadata=@{@"createdAt":@1799999900};CHECK([tracker newEventsInBatch:prepared(m,nil,YES) wallTime:1800000002].count==0);
    CHECK([tracker newEventsInBatch:prepared(msg(104,1),U,YES) wallTime:1800000002].count==0);
    CHECK([tracker newEventsInBatch:prepared(msg(105,1),nil,NO) wallTime:1800000002].count==0);
    CHECK([tracker newEventsInBatch:prepared(msg(105,1),nil,YES) wallTime:1800000003].count==1);
    tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    CHECK([tracker newEventsInBatch:prepared(msg(106,1),nil,NO) wallTime:1800000002].count==0);
    CHECK([tracker newEventsInBatch:prepared(msg(106,1),ME,NO) wallTime:1800000003].count==1);
    // Missing timestamp must stay silent, rather than pretend now is sentAt.
    m=msg(107,1);m.metadata=@{};CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000003].count==0);
    m.metadata=@{@"createdAt":@1800000003};CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000004].count==1);
    CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000005].count==0);
    /* A delayed first observation must retain the original monitoring gate
       when direction or timestamp becomes available on another callback. */
    tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    m=msg(109,1);CHECK([tracker newEventsInBatch:prepared(m,nil,NO) wallTime:1800000010].count==0);
    CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000011].count==1);
    tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    m=msg(110,1);m.metadata=@{};CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000010].count==0);
    m.metadata=@{@"createdAt":@1800000001};CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000011].count==1);
    tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    m=msg(111,1);m.metadata=@{};CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000010].count==0);
    m.metadata=@{@"createdAt":@1799999999};CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000011].count==0);
    // Voice then chat, delivered late/close together: callback time is not
    // evidence that a different message created earlier belongs to history.
    tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    m=msg(112,999);m.isVoiceNote=YES;
    CHECK([tracker newEventsInBatch:prepared(m,ME,NO) wallTime:1800000010].count==1);
    SCNMessagingMessage *following=msg(113,1);following.metadata=@{@"createdAt":@1800000005};
    CHECK([tracker newEventsInBatch:prepared(following,ME,NO) wallTime:1800000011].count==1);
    following=msg(114,1);following.metadata=@{};
    CHECK([tracker newEventsInBatch:prepared(following,ME,NO) wallTime:1800000020].count==0);
    following.metadata=@{@"createdAt":@1800000015};
    CHECK([tracker newEventsInBatch:prepared(following,ME,NO) wallTime:1800000023].count==1);
    CHECK([tracker newEventsInBatch:prepared(following,ME,NO) wallTime:1800000024].count==0);
    m=msg(108,999);m.metadata=@{@"secret":@"PRIVATE_BODY_NOT_FOR_LOGS",@"currentUserId":ME};
    NSString *schema=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:decode(m) options:0 error:NULL] encoding:NSUTF8StringEncoding];
    CHECK(![schema containsString:@"PRIVATE_BODY_NOT_FOR_LOGS"]); // entire rejected batch has only event identities, no text
    NSString *shapes=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:decode(m)[@"shapes"] options:0 error:NULL] encoding:NSUTF8StringEncoding];
    CHECK(![shapes containsString:U]);CHECK(![shapes containsString:ME]);
    // The supplied encoding B32@0:8@16@24 was rejected by rc3.
    __block NSUInteger hits=0;__block int last=-7;RC4BoolHost *host=[RC4BoolHost new];
    CHECK(SNInstallHook(RC4BoolHost.class,@selector(present:delegate:),^(id self,NSArray *args,id result){hits++;last=[result intValue];CHECK(self==host);CHECK(args.count==2);CHECK(args[1]==NSNull.null);}));
    CHECK([host present:@YES delegate:nil]);CHECK(last==1);CHECK(hits==1);CHECK(host.calls==1);
    CHECK(![host present:@NO delegate:nil]);CHECK(last==0);CHECK(hits==2);CHECK(host.calls==2);
    CHECK(SNInstallHook(RC4BoolHost.class,@selector(legacy:delegate:),^(__unused id self,__unused NSArray *a,id r){last=[r intValue];}));
    CHECK([host legacy:@-1 delegate:nil]==-1);CHECK(last==-1);CHECK([host legacy:@0 delegate:nil]==0);
    CHECK(!SNInstallHook(RC4BoolHost.class,@selector(notBoolean:),^(__unused id s,__unused NSArray *a,__unused id r){}));
    NSLog(@"Native messaging regression: %lu synthetic checks passed",(unsigned long)checks);
}return 0;}
