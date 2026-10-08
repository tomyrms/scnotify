/* Synthetic fixtures only; no captured user messages. */
#import <Foundation/Foundation.h>
#import "../Sources/SNHostNotice.h"
#import "../Sources/SNReceive.h"
#import "../Sources/SNRuntime.h"
#include <stdlib.h>
static NSUInteger checks;
#define CHECK(...) do{checks++;if(!(__VA_ARGS__)){NSLog(@"FAILED host line %d: %s",__LINE__,#__VA_ARGS__);abort();}}while(0)
@interface NoticeChoice : NSObject
@property(nonatomic,strong) id payload;
@property(nonatomic) BOOL system;
@property(nonatomic) NSUInteger calls;
- (void)matchInAppNotification:(void(^)(id))inApp systemNotification:(void(^)(id))system;
@end
@implementation NoticeChoice
- (void)matchInAppNotification:(void(^)(id))inApp systemNotification:(void(^)(id))system {
    self.calls++;if(self.system){if(system)system(self.payload);}else if(inApp)inApp(self.payload);
}
@end
@interface OptionalKind : NSObject
@property(nonatomic) BOOL hasContentType;
@property(nonatomic) int contentType;
@end
@implementation OptionalKind
@end
static NSString *C=@"11111111-1111-4111-8111-111111111111",*U=@"22222222-2222-4222-8222-222222222222";
static NSDictionary *batch(NSInteger n,double time,id type,BOOL incoming) {
    return SNDecodeReceived(@[@{@"conversationId":C,@"senderId":U,@"messageId":@(n),@"contentType":type,@"timestamp":@(time),@"isIncoming":@(incoming)}],nil,nil);
}
int main(void) {
 @autoreleasepool {
    NSDictionary *n=@{@"title":@"Test contact",@"body":@"Nouveau chat",@"notificationId":@"notice-1"};
    CHECK([SNHostNotice(n)[@"title"] isEqual:@"Test contact"]);
    CHECK([SNHostNotice(n)[@"body"] isEqual:@"Nouveau chat"]);
    CHECK([SNHostNotice(n)[@"id"] isEqual:@"notice-1"]);
    CHECK(SNHostNotice(@{@"body":@"snap"})==nil); /* Words alone never constitute a notice. */
    CHECK(SNHostNotice(@{@"title":@"Test",@"body":@123})==nil);
    CHECK(SNHostNotice(@{@"title":@"Test",@"body":@"Chat",@"isOutgoing":@YES})==nil);
    CHECK(SNHostNotice(@{@"title":@"Test",@"body":@"Chat",@"scnotify":@YES})==nil);
    CHECK(SNHostNotice(@{@"title":@"Test",@"body":@"Chat",@"userInfo":@{@"scnotify":@YES}})==nil);
    CHECK([SNHostNotice(@{@"content":n})[@"body"] isEqual:@"Nouveau chat"]);
    CHECK([SNHostNotice(@{@"notificationContent":NSNull.null,@"content":n})[@"body"] isEqual:@"Nouveau chat"]);
    CHECK([SNHostNotice(@{@"notificationContent":@{},@"notification":n})[@"id"] isEqual:@"notice-1"]);
    CHECK([SNHostNotice(@{@"notificationContent":@"unavailable",@"content":n})[@"id"] isEqual:@"notice-1"]);
    NSDictionary *noticeContent=@{@"title":@"Test contact",@"body":@"Nouveau chat"};
    CHECK([SNHostNotice(@{@"notificationId":@"envelope-1",@"content":noticeContent})[@"id"] isEqual:@"envelope-1"]);
    CHECK([SNHostNotice(@{@"notificationId":@"envelope-1",@"content":n})[@"id"] isEqual:@"notice-1"]);
    CHECK(SNHostNotice(@{@"isHistorical":@YES,@"content":n})==nil);
    CHECK(SNHostNotice(@{@"content":@{@"content":@{@"content":@{@"content":n}}}})==nil);
    /* The duplicate-cycle guard is the behaviour under test here. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-circular-container"
    NSMutableDictionary *cycle=[NSMutableDictionary dictionary];[cycle setObject:cycle forKey:@"content"];
#pragma clang diagnostic pop
    CHECK(SNHostNotice(cycle)==nil);[cycle removeAllObjects];
    CHECK([SNHostNotice(@{@"title":[[NSAttributedString alloc] initWithString:@"Test"],@"messageText":@"Line 1\nLine 2"})[@"body"] isEqual:@"Line 1\nLine 2"]);
    CHECK(SNHostNotice(@{@"title":@"Test",@"body":[@"a" stringByPaddingToLength:4097 withString:@"a" startingAtIndex:0]})==nil);
    CHECK(SNTransportJSON([@"{\"messages\":[]}" dataUsingEncoding:NSUTF8StringEncoding])!=nil);
    CHECK(SNTransportJSON([@"snap CALLER_PUSH" dataUsingEncoding:NSUTF8StringEncoding])==nil);
    CHECK(SNTransportJSON([@"{broken" dataUsingEncoding:NSUTF8StringEncoding])==nil);
    CHECK(SNTransportJSON([NSMutableData dataWithLength:256*1024+1])==nil);
    CHECK(SNTransportJSON(@[@{}])!=nil);
    __block NSUInteger observed=0,called=0;
    void (^original)(id)=^(id value){called++;CHECK(value==n||value==nil);};
    id wrapped=SNWrapNoticeBlock(original,^(id payload){observed++;CHECK(payload==n);});
    CHECK(wrapped!=nil);((void(^)(id))wrapped)(n);CHECK(called==1);CHECK(observed==1);
    ((void(^)(id))wrapped)(nil);CHECK(called==2);CHECK(observed==1);
    CHECK(SNWrapNoticeBlock(^{},^(__unused id value){})==nil);
    CHECK(SNWrapNoticeBlock(^NSInteger(__unused id x){return 7;},^(__unused id value){})==nil);
    CHECK(SNWrapNoticeBlock(^(__unused NSInteger x){},^(__unused id value){})==nil);
    CHECK(SNWrapNoticeBlock(@{},^(__unused id value){})==nil);
    CHECK(SNInstallNoticeChoice(NoticeChoice.class,^(id payload){observed++;CHECK(payload==n);}));
    NoticeChoice *choice=[NoticeChoice new];choice.payload=n;
    [choice matchInAppNotification:original systemNotification:original];CHECK(choice.calls==1);CHECK(observed==2);CHECK(called==3);
    choice.system=YES;[choice matchInAppNotification:original systemNotification:original];CHECK(choice.calls==2);CHECK(observed==2);CHECK(called==4);
    CHECK(!SNInstallNoticeChoice(NoticeChoice.class,^(__unused id payload){}));
    /* Observer exceptions cannot skip the host's callback. */
    wrapped=SNWrapNoticeBlock(original,^(__unused id value){[NSException raise:@"Test" format:@"intentional"];});
    ((void(^)(id))wrapped)(n);CHECK(called==5);
    OptionalKind *content=[OptionalKind new];content.hasContentType=NO;content.contentType=0;
    NSDictionary *message=@{@"conversationId":C,@"senderId":U,@"messageId":@1,@"messageContent":content};
    CHECK([SNDecodeReceived(@[message],nil,@"snap")[@"events"] count]==1);
    content.hasContentType=YES;CHECK([SNDecodeReceived(@[message],nil,@"snap")[@"events"] count]==0);
    /* Native descriptor sender + a feed's latestMessage envelope. */
    message=@{@"descriptor":@{@"conversationId":C,@"senderId":U,@"messageId":@2},@"contentType":@"CHAT"};
    CHECK([SNDecodeReceived(@[@{@"latestMessage":message}],nil,nil)[@"events"] count]==1);
    SNReceiveTracker *tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    CHECK([tracker newEventsInBatch:batch(1,1800000001,@"CHAT",YES) wallTime:1800000002].count==1);
    CHECK([tracker newEventsInBatch:batch(1,1800000001,@"CHAT",YES) wallTime:1800000003].count==0);
    tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    CHECK([tracker newEventsInBatch:batch(1,1799999999,@"CHAT",YES) wallTime:1800000002].count==0);
    tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    CHECK([tracker newEventsInBatch:batch(1,1800000001,@"CHAT",NO) wallTime:1800000002].count==0);
    /* Old encrypted baseline never notifies when decoded. New encrypted
       records can notify once when their semantic content becomes available. */
    tracker=[[SNReceiveTracker alloc] initWithMonitoringStart:1800000000];
    CHECK([tracker newEventsInBatch:batch(1,1799999990,@987,YES) wallTime:1800000000].count==0);
    CHECK([tracker newEventsInBatch:batch(1,1799999990,@"SNAP",YES) wallTime:1800000001].count==0);
    CHECK([tracker newEventsInBatch:batch(2,1800000002,@987,YES) wallTime:1800000002].count==0);
    CHECK([tracker newEventsInBatch:batch(2,1800000002,@"SNAP",YES) wallTime:1800000003].count==1);
    CHECK([tracker newEventsInBatch:batch(2,1800000002,@"SNAP",YES) wallTime:1800000004].count==0);
    NSLog(@"Host bridge and receive fixes: %lu synthetic checks passed",(unsigned long)checks);
 }
 return 0;
}
