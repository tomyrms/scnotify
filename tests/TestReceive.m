/* Synthetic compatibility fixtures, NOT device captures. Executed by the
   macOS job before the iOS library is built. */
#import <Foundation/Foundation.h>
#import "../Sources/SNRuntime.h"
#import "../Sources/SNReceive.h"
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

static NSString *U=@"22222222-2222-4222-8222-222222222222";
static NSString *C=@"11111111-1111-4111-8111-111111111111";
static NSString *D=@"33333333-3333-4333-8333-333333333333";
static NSUInteger checks=0;
#define CHECK(...) do {checks++;if(!(__VA_ARGS__)){NSLog(@"FAILED receive line %d: %s",__LINE__,#__VA_ARGS__);abort();}} while(0)

/* Native-wrapper and protobuf-enum stand-ins, not Snapchat implementations. */
@interface RXUUID : NSObject
@property(nonatomic,strong) NSData *id;
@end
@implementation RXUUID
@end
@interface RXEnum : NSObject
- (NSString *)textFormatNameForValue:(int32_t)value;
@end
@implementation RXEnum
- (NSString *)textFormatNameForValue:(int32_t)value {return value==901?@"SNAP":value==902?@"CHAT":value==903?@"READ_RECEIPT":nil;}
@end
@interface RXContent : NSObject
@property(nonatomic) int32_t contentType;
+ (id)descriptor;
@end
@implementation RXContent
+ (id)descriptor {return @{@"fields":@[@{@"name":@"contentType",@"enumDescriptor":[RXEnum new]}]};}
@end
@interface RXUnmapped : NSObject
@property(nonatomic) int32_t contentType;
@end
@implementation RXUnmapped
@end
@interface RXHook : NSObject
@property(nonatomic) NSUInteger calls;
@property(nonatomic,copy) NSArray *values;
- (void)onMessagesReceived:(id)a conversation:(id)b metadata:(id)c completion:(id)d;
- (void)onMessagesReceived:(id)a historical:(BOOL)historical;
@end
@implementation RXHook
- (void)onMessagesReceived:(id)a conversation:(id)b metadata:(id)c completion:(id)d {self.calls++;self.values=@[a?:NSNull.null,b?:NSNull.null,c?:NSNull.null,d?:NSNull.null];}
- (void)onMessagesReceived:(__unused id)a historical:(__unused BOOL)historical {self.calls++;}
@end
static id uuid(NSString *s) {uuid_t bytes;[[[NSUUID alloc] initWithUUIDString:s] getUUIDBytes:bytes];RXUUID *u=[RXUUID new];u.id=[NSData dataWithBytes:bytes length:16];return u;}
static NSMutableDictionary *message(NSString *cid, id eid, id type) {
    return [@{@"descriptor":@{@"conversationId":uuid(cid),@"messageId":eid},@"senderId":uuid(U),@"messageContent":@{@"contentType":type},@"metadata":@{@"creationTimestamp":@1800000000000LL}} mutableCopy];
}
static NSArray *events(id obj){return SNDecodeReceived(@[obj],nil,nil)[@"events"];}
static NSDictionary *batch(id obj){return SNDecodeReceived(@[obj],nil,nil);}
static BOOL reason(id obj,NSString *r){return [batch(obj)[@"rejected"][r] unsignedIntegerValue]>0;}
int main(void) {
    @autoreleasepool {
        SNSetReceiveTypeMappings(@{});
        CHECK([SNIdentifier(uuid(U)) isEqual:U]);
        CHECK(SNIdentifier(@{@"id":@123})==nil);
        CHECK([SNMessageIdentifier(@(UINT64_MAX)) isEqual:@"18446744073709551615"]);
        CHECK(SNMessageIdentifier(@YES)==nil);CHECK(SNMessageIdentifier(@NO)==nil);
        CHECK(SNMessageIdentifier(@-1)==nil);CHECK(SNMessageIdentifier(@0)==nil);
        CHECK(SNMessageIdentifier(@2.5)==nil);CHECK(SNMessageIdentifier(@"bad|key")==nil);
        CHECK(SNMessageIdentifier(@" ")==nil);CHECK(SNMessageIdentifier(@"bad\nkey")==nil);
        CHECK([SNMessageIdentifier(@"server-msg-42") isEqual:@"server-msg-42"]);
        CHECK([SNMessageIdentifier([[NSUUID alloc] initWithUUIDString:U]) isEqual:U]);
        NSMutableDictionary *m=message(C,@1,@"SNAP");
        CHECK(events(m).count==1);CHECK([events(m)[0][@"kind"] isEqual:@"snap"]);
        CHECK([events(m)[0][@"uid"] isEqual:U]);CHECK([events(m)[0][@"conversation"] isEqual:C]);
        CHECK([events(m)[0][@"event"] isEqual:@"1"]);
        CHECK([events(m)[0][@"timestamp"] doubleValue]==1800000000);
        m=message(C,@(UINT64_MAX),@"CHAT");CHECK([events(m)[0][@"kind"] isEqual:@"message"]);
        CHECK([events(m)[0][@"event"] isEqual:@"18446744073709551615"]);
        m=message(C,@1,@"SNAP");m[@"descriptor"]=@{@"messageId":@1};
        NSString *cid=SNCallbackConversation(@"conversation:didReceiveMessage:",@[uuid(C),m]);
        CHECK([cid isEqual:C]);CHECK([SNDecodeReceived(@[uuid(C),m],cid,nil)[@"events"] count]==1);
        CHECK(SNCallbackConversation(@"didReceiveMessage:",@[uuid(C),m])==nil);
        CHECK([SNCallbackConversation(@"onMessagesReceived:conversationId:",@[@[m],uuid(C)]) isEqual:C]);
        CHECK([SNCallbackConversation(@"onMessagesReceived:conversation:metadata:completion:",@[@[m],uuid(C),@{},NSNull.null]) isEqual:C]);
        CHECK(events(m).count==0);CHECK(reason(m,@"missing-conversation"));
        CHECK(events(@{@"conversationId":C,@"messages":@[m]}).count==1);
        CHECK(events(@{@"conversationId":C,@"messages":@[m,message(D,@1,@"TEXT")]}).count==2);
        CHECK([events(@{@"conversationId":C,@"messages":@[m,message(D,@1,@"TEXT")]})[1][@"conversation"] isEqual:D]);
        m=message(C,@1,@"CHAT");CHECK(events(@[m,m]).count==1);
        CHECK(events(@[m,message(C,@1,@"SNAP")]).count==1);
        NSMutableDictionary *dual=[m mutableCopy];dual[@"messageDescriptor"]=dual[@"descriptor"];dual[@"descriptor"]=@{@"name":@"SchemaOnly"};CHECK(events(dual).count==1);
        CHECK(events(@[m,message(C,@2,@"CHAT")]).count==2);
        CHECK(events(@{@"message":m,@"messages":@[m]}).count==1);
        /* Multiple representations of one callback must contribute missing
           metadata regardless of traversal order, with one output per ID. */
        NSMutableDictionary *sparse=message(C,@41,@"CHAT");sparse[@"metadata"]=@{};
        NSMutableDictionary *complete=message(C,@41,@"VOICE_NOTE");complete[@"isIncoming"]=@YES;complete[@"senderDisplayName"]=@"Friend";
        for(NSArray *copies in @[@[sparse,complete],@[complete,sparse]]) {
            NSArray *decoded=events(copies);CHECK(decoded.count==1);
            CHECK([decoded[0][@"timestamp"] doubleValue]==1800000000);
            CHECK([decoded[0][@"incoming"] boolValue]);CHECK([decoded[0][@"subtype"] isEqual:@"voice"]);
            CHECK([decoded[0][@"name"] isEqual:@"Friend"]);
        }
        CHECK(events(@[sparse,complete,message(C,@42,@"CHAT")]).count==2);
        NSMutableDictionary *firstDate=message(C,@43,@"CHAT");
        NSMutableDictionary *differentDate=message(C,@43,@"VOICE_NOTE");
        differentDate[@"metadata"]=@{@"timestamp":@1799999000,@"isIncoming":@YES};
        NSDictionary *conflictingBatch=batch(@[firstDate,differentDate]);
        CHECK([conflictingBatch[@"events"] count]==1);
        NSDictionary *unchanged=conflictingBatch[@"events"][0];
        CHECK([unchanged[@"timestamp"] doubleValue]==1800000000);
        CHECK(unchanged[@"incoming"]==nil);CHECK(unchanged[@"subtype"]==nil);
        CHECK([conflictingBatch[@"rejected"][@"conflicting-duplicate-time"] integerValue]==1);
        m=message(C,@1,@"CHAT");m[@"outgoing"]=@YES;m[@"isOutgoing"]=@NO;CHECK(reason(m,@"outgoing"));
        m=message(C,@1,@"CHAT");m[@"metadata"]=@{@"isFromMe":@YES};CHECK(events(m).count==0);
        m=message(C,@1,@"CHAT");m[@"isSender"]=@NO;m[@"metadata"]=@{@"isSender":@YES};CHECK(reason(m,@"outgoing"));
        m=message(C,@1,@"CHAT");m[@"isSender"]=@YES;m[@"hasIsSender"]=@NO;m[@"metadata"]=@{@"isIncoming":@YES};CHECK(events(m).count==1);
        CHECK([events(m)[0][@"incoming"] boolValue]);
        m=message(C,@1,@"CHAT");m[@"isOutgoing"]=@YES;m[@"hasIsOutgoing"]=@NO;m[@"metadata"]=@{@"isOutgoing":@NO};CHECK(events(m).count==1);
        CHECK([events(m)[0][@"incoming"] boolValue]);
        m=message(C,@1,@"CHAT");m[@"isIncoming"]=@YES;m[@"hasIsIncoming"]=@NO;CHECK(events(m)[0][@"incoming"]==nil);
        m=message(C,@1,@"CHAT");CHECK(events(@{@"fromHistory":@YES,@"messages":@[m]}).count==0);
        m[@"metadata"]=@{@"isHistorical":@YES};CHECK(reason(m,@"history"));
        for(NSString *control in @[@"TYPING",@"READ_RECEIPT",@"DELIVERY_RECEIPT",@"CALLER_PUSH",@"STATUS_READ",@"DELETE",@"SCREENSHOT"]) {
            m=message(C,@1,control);CHECK(reason(m,@"control-event"));
            CHECK(events(@{@"eventType":control,@"message":message(C,@2,@"CHAT")}).count==0);
        }
        m=message(C,@1,@"CHAT");m[@"messageType"]=@"SNAP";CHECK(reason(m,@"conflicting-content-type"));
        m=message(C,@1,@987);CHECK(reason(m,@"unknown-content-type"));
        CHECK([SNDecodeReceived(@[m],nil,@"snap")[@"events"] count]==0);
        m[@"messageType"]=@"SNAP";CHECK(events(m).count==1);
        m=message(C,@1,@"CHAT");[m removeObjectForKey:@"senderId"];CHECK(reason(m,@"missing-sender"));
        m[@"metadata"]=@{@"senderId":uuid(U),@"isIncoming":@YES};CHECK(events(m).count==1);CHECK([events(m)[0][@"incoming"] boolValue]);
        m=message(C,@1,@"CHAT");m[@"descriptor"]=@{@"conversationId":C};CHECK(reason(m,@"missing-message-id"));
        m=message(C,@1,@"CHAT");[m removeObjectForKey:@"messageContent"];
        CHECK([SNDecodeReceived(@[m],nil,@"message")[@"events"] count]==1);
        CHECK(events(m).count==0);
        RXContent *content=[RXContent new];content.contentType=901;m=message(C,@1,@0);m[@"messageContent"]=content;
        CHECK([events(m)[0][@"kind"] isEqual:@"snap"]);content.contentType=902;CHECK([events(m)[0][@"kind"] isEqual:@"message"]);
        content.contentType=903;CHECK(events(m).count==0);content.contentType=904;CHECK(events(m).count==0);
        RXUnmapped *raw=[RXUnmapped new];raw.contentType=901;m[@"messageContent"]=raw;CHECK(events(m).count==0);
        SNSetReceiveTypeMappings(@{@"RXUnmapped.contentType":@{@"901":@"snap"}});CHECK(events(m).count==1);
        raw.contentType=902;CHECK(events(m).count==0);SNSetReceiveTypeMappings(@{});raw.contentType=901;CHECK(events(m).count==0);
        for(NSNumber *time in @[@1800000000,@1800000000000LL,@1800000000000000LL,@1800000000000000000LL]) {
            m=message(C,@1,@"CHAT");m[@"metadata"]=@{@"timestamp":time};CHECK([events(m)[0][@"timestamp"] doubleValue]==1800000000);
        }
        m=message(C,@1,@"CHAT");m[@"metadata"]=@{@"timestamp":@(NAN)};CHECK(reason(m,@"invalid-time"));
        m=message(C,@1,@"CHAT");m[@"metadata"]=@{@"timestamp":[NSDate dateWithTimeIntervalSince1970:1800000000]};CHECK(events(m).count==1);
        m=message(C,@1,@"CHAT");m[@"metadata"]=@{@"creationTimestamp":@0,@"serverTimestampMs":@1800000000000LL};
        CHECK([events(m)[0][@"timestamp"] doubleValue]==1800000000);
        m[@"metadata"]=@{@"creationTimestamp":@1700000000,@"hasCreationTimestamp":@NO,@"timestamp":@1800000000};
        CHECK([events(m)[0][@"timestamp"] doubleValue]==1800000000);
        for(NSString *field in @[@"createdAtMs",@"serverTimestampMs"]){m=message(C,@1,@"CHAT");m[@"metadata"]=@{};m[field]=@1800000000000LL;CHECK([events(m)[0][@"timestamp"] doubleValue]==1800000000);}
        for(NSString *type in @[@"VOICE_NOTE",@"VOICE_MESSAGE",@"VOICE_NOTE_MESSAGE",@"AUDIO_MESSAGE",@"AUDIO_NOTE",@"CONTENT_TYPE_AUDIO_NOTE"]){m=message(C,@1,type);CHECK([events(m)[0][@"subtype"] isEqual:@"voice"]);CHECK([events(m)[0][@"kind"] isEqual:@"message"]);}
        m=message(C,@1,@"CHAT");m[@"senderDisplayName"]=@"José 日本語";CHECK([events(m)[0][@"name"] isEqual:@"José 日本語"]);
        /* The duplicate-cycle guard is the behaviour under test here. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-circular-container"
        NSMutableDictionary *cycle=[NSMutableDictionary dictionary];cycle[@"message"]=cycle;CHECK(reason(cycle,@"cycle"));[cycle removeAllObjects];
#pragma clang diagnostic pop
        id deep=message(C,@1,@"CHAT");for(unsigned i=0;i<12;i++)deep=@{@"message":deep};CHECK(reason(deep,@"traversal-limit"));
        NSMutableArray *many=[NSMutableArray array];for(unsigned i=1;i<=300;i++)[many addObject:message(C,@(i),@"CHAT")];CHECK(events(many).count==300);
        for(unsigned i=301;i<=600;i++)[many addObject:message(C,@(i),@"CHAT")];CHECK(events(many).count==512);CHECK(reason(many,@"batch-limit"));
        m=message(C,@1,@983);m[@"body"]=@"DO_NOT_EXPORT_PRIVATE_MESSAGE";
        NSData *diagnostic=[NSJSONSerialization dataWithJSONObject:batch(m)[@"shapes"] options:0 error:NULL];NSString *text=[[NSString alloc] initWithData:diagnostic encoding:NSUTF8StringEncoding];
        CHECK([text rangeOfString:@"DO_NOT_EXPORT_PRIVATE_MESSAGE"].location==NSNotFound);CHECK([text rangeOfString:U].location==NSNotFound);
        SNReceiveTracker *tracker=[SNReceiveTracker new];
        m=message(C,@1,@"CHAT");CHECK([tracker newEventsInBatch:batch(m) wallTime:1800000000].count==0);
        CHECK([tracker newEventsInBatch:batch(m) wallTime:1800000001].count==0);
        CHECK([tracker newEventsInBatch:batch(@[m,message(C,@2,@"CHAT")]) wallTime:1800000001].count==1);
        CHECK([tracker newEventsInBatch:batch(@[m,message(C,@2,@"CHAT")]) wallTime:1800000002].count==0);
        CHECK([tracker newEventsInBatch:batch(@{@"conversationId":C,@"messages":@[]}) wallTime:1800000003].count==0);
        CHECK([tracker newEventsInBatch:batch(m) wallTime:1800000004].count==0);
        [tracker reset];CHECK([tracker newEventsInBatch:batch(@{@"conversationId":C,@"messages":@[]}) wallTime:1800000000].count==0);
        CHECK([tracker newEventsInBatch:batch(m) wallTime:1800000001].count==1);
        [tracker reset];CHECK([tracker newEventsInBatch:batch(message(C,@8,@983)) wallTime:1800000000].count==0);
        CHECK([tracker newEventsInBatch:batch(message(C,@8,@"SNAP")) wallTime:1800000001].count==0);
        [tracker reset];CHECK([tracker newEventsInBatch:batch(m) wallTime:1800000000].count==0);
        NSMutableDictionary *old=message(C,@20,@"CHAT");old[@"metadata"]=@{@"timestamp":@1799999990};
        CHECK([tracker newEventsInBatch:batch(old) wallTime:1800000001].count==0);
        CHECK([tracker newEventsInBatch:batch(message(D,@1,@"SNAP")) wallTime:1800000002].count==0);
        CHECK([tracker newEventsInBatch:batch(message(D,@2,@"SNAP")) wallTime:1800000003].count==0); /* predates D baseline */
        CHECK([tracker newEventsInBatch:batch(m) wallTime:NAN].count==0);
        /* Long sessions must not permanently stop after the bounded ID cache
           fills. Old messages remain ineligible after their cache expires. */
        tracker=[SNReceiveTracker new];
        CHECK([tracker newEventsInBatch:batch(@{@"conversationId":C,@"messages":@[]}) wallTime:1800000000].count==0);
        NSMutableArray *burst=[NSMutableArray array];
        for(unsigned i=1;i<=2048;i++)[burst addObject:@{@"conversation":C,@"event":[NSString stringWithFormat:@"%u",i],@"timestamp":@1800000000,@"incoming":@YES}];
        CHECK([tracker newEventsInSnapshot:burst wallTime:1800000000].count==2048);
        NSDictionary *after=@{@"conversation":C,@"event":@"2049",@"timestamp":@1800000362,@"incoming":@YES};
        CHECK([tracker newEventsInSnapshot:@[after] wallTime:1800000362].count==1);
        CHECK([tracker newEventsInSnapshot:burst wallTime:1800000362].count==0);
        CHECK([tracker newEventsInSnapshot:@[after] wallTime:1800000363].count==0);
        /* A full decoded burst may still be waiting on metadata: the pending
           bound must not silently discard the tail of an accepted batch. */
        tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
        NSMutableArray *incomplete=[NSMutableArray array],*completed=[NSMutableArray array];
        for(unsigned i=1;i<=300;i++) {
            NSDictionary *pending=@{@"conversation":C,@"event":[NSString stringWithFormat:@"%u",i],@"incoming":@YES};
            [incomplete addObject:pending];NSMutableDictionary *ready=[pending mutableCopy];ready[@"timestamp"]=@1800000001;[completed addObject:ready];
        }
        CHECK([tracker newEventsInSnapshot:incomplete wallTime:1800000002].count==0);
        CHECK([tracker newEventsInSnapshot:completed wallTime:1800000003].count==300);
        CHECK([tracker newEventsInSnapshot:completed wallTime:1800000004].count==0);
        /* Keep the original monitoring threshold after a delayed first
           observation: subsequent IDs may have been created before it. */
        tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
        NSDictionary *voice=@{@"conversation":C,@"event":@"voice",@"timestamp":@1800000001,@"incoming":@YES};
        NSDictionary *chat=@{@"conversation":C,@"event":@"chat",@"timestamp":@1800000005,@"incoming":@YES};
        CHECK([tracker newEventsInSnapshot:@[voice] wallTime:1800000010].count==1);
        CHECK([tracker newEventsInSnapshot:@[chat] wallTime:1800000011].count==1);
        CHECK([tracker newEventsInSnapshot:@[voice,chat] wallTime:1800000012].count==0);
        NSMutableDictionary *late=[@{@"conversation":C,@"event":@"late",@"incoming":@YES} mutableCopy];
        CHECK([tracker newEventsInSnapshot:@[late] wallTime:1800000020].count==0);
        late[@"timestamp"]=@1800000015;
        CHECK([tracker newEventsInSnapshot:@[late] wallTime:1800000023].count==1);
        CHECK([tracker newEventsInSnapshot:@[late] wallTime:1800000024].count==0);
        /* Late type decoding follows the same stable threshold. Old initial
           history still stays silent, and fresh replays still deduplicate. */
        CHECK([tracker newEventsInBatch:batch(message(C,@55,@983)) wallTime:1800000030].count==0);
        m=message(C,@55,@"CHAT");m[@"metadata"]=@{@"timestamp":@1800000025,@"isIncoming":@YES};
        CHECK([tracker newEventsInBatch:batch(m) wallTime:1800000031].count==1);
        CHECK([tracker newEventsInBatch:batch(m) wallTime:1800000032].count==0);
        m=message(C,@56,@"CHAT");m[@"metadata"]=@{@"timestamp":@1799999999,@"isIncoming":@YES};
        CHECK([tracker newEventsInBatch:batch(m) wallTime:1800000033].count==0);
        /* Without an explicit monitoring start, the first snapshot remains a
           silent baseline while later metadata retains that baseline gate. */
        tracker=[SNReceiveTracker new];
        CHECK([tracker newEventsInSnapshot:@[voice] wallTime:1800000010].count==0);
        [late removeObjectForKey:@"timestamp"];
        CHECK([tracker newEventsInSnapshot:@[late] wallTime:1800000020].count==0);
        late[@"timestamp"]=@1800000015;
        CHECK([tracker newEventsInSnapshot:@[late] wallTime:1800000023].count==1);
        CHECK([tracker newEventsInSnapshot:@[voice] wallTime:1800000024].count==0);
        __block NSUInteger hits=0;SEL sel=@selector(onMessagesReceived:conversation:metadata:completion:);
        CHECK(SNInstallHook(RXHook.class,sel,^(id self,NSArray *args,__unused id result){hits++;CHECK([(RXHook *)self calls]==1);CHECK(args.count==4);CHECK([args[1] isEqual:C]);CHECK(args[3]==NSNull.null);}));
        RXHook *hook=[RXHook new];[hook onMessagesReceived:@[@1] conversation:C metadata:@{} completion:nil];CHECK(hits==1);CHECK(hook.calls==1);
        CHECK(!SNInstallHook(RXHook.class,@selector(onMessagesReceived:historical:),^(__unused id self,__unused NSArray *args,__unused id result){}));
        NSLog(@"Receive adapters/runtime: %lu synthetic checks passed",(unsigned long)checks);
    }
    return 0;
}
