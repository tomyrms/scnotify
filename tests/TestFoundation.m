#import <Foundation/Foundation.h>
#import "../Sources/SNRuntime.h"
#include <assert.h>

static NSString *U=@"22222222-2222-4222-8222-222222222222";
static NSString *V=@"55555555-5555-4555-8555-555555555555";
static NSString *C=@"11111111-1111-4111-8111-111111111111";
static NSUInteger checks=0;
#define CHECK(condition) do { checks++; if(!(condition)){NSLog(@"FAILED line %d: %s",__LINE__,#condition);abort();} } while(0)

@interface SNTestPerson : NSObject
@property(nonatomic,copy) NSString *userId;
@property(nonatomic,copy) NSString *displayName;
@property(nonatomic,copy) NSString *username;
@property(nonatomic) NSInteger typingState;
@property(nonatomic) double timestamp;
@end
@implementation SNTestPerson
@end
@interface SNTestParent : NSObject
@property(nonatomic) NSUInteger calls;
- (void)receive:(id)value;
- (NSString *)displayNameForUserId:(id)value;
- (BOOL)notAnObject:(id)value;
@end
@implementation SNTestParent
- (void)receive:(__unused id)value {self.calls++;}
- (NSString *)displayNameForUserId:(__unused id)value {self.calls++;return @"João 日本語";}
- (BOOL)notAnObject:(__unused id)value {self.calls++;return YES;}
@end
@interface SNTestChild : SNTestParent
@end
@implementation SNTestChild
- (void)receive:(id)value {[super receive:value];self.calls++;}
@end
@interface SNTestPresenceProxy : NSObject
@property(nonatomic,copy) NSString *fixture;
@end
@implementation SNTestPresenceProxy
- (NSString *)description {return self.fixture;}
@end
int main(void) {
    @autoreleasepool {
        CHECK([SNIdentifier([[NSUUID alloc] initWithUUIDString:U]) isEqual:U]);
        CHECK(SNIdentifier(@"not a UUID")==nil);
        CHECK([SNName(@"  João 日本語  ") isEqual:@"João 日本語"]);
        CHECK(SNName(U)==nil);CHECK(SNName(@"null")==nil);CHECK(SNName(@"A\nB")==nil);
        SNTestPerson *p=[SNTestPerson new];p.userId=U;p.displayName=@"José da Silva";p.username=@"jose.test";p.typingState=3;
        CHECK([SNRead(p,@"typingState") isEqual:@3]);
        p.timestamp=123.5;CHECK([SNRead(p,@"timestamp") isEqual:@123.5]);
        uuid_t rawUUID;[[[NSUUID alloc] initWithUUIDString:U] getUUIDBytes:rawUUID];
        CHECK([SNIdentifier([NSData dataWithBytes:rawUUID length:16]) isEqual:U]);
        CHECK([SNUserRecord(p,nil)[@"name"] isEqual:@"José da Silva"]);
        CHECK([SNUserRecord(@{@"conversationId":C,@"displayName":@"Group"},nil) count]==0);
        CHECK([SNUserRecord(@"Alice",U)[@"uid"] isEqual:U]);
        CHECK([SNUserRecords(@{@"users":@[p]}) count]==1);
        CHECK([SNUserRecords(@{U:@{@"displayName":@"Alice"}}).firstObject[@"uid"] isEqual:U]);
        NSArray *snapshot=@[@{@"conversationId":C,@"remoteTypingParticipants":@[@{@"userId":U,@"typingState":@3},@{@"userId":V,@"typingState":@1}],@"remotePeekingParticipantUserIds":@[U]}];
        NSArray *decoded=SNPresenceRecords(snapshot);
        CHECK(decoded.count==1);CHECK([decoded[0][@"typing"] count]==2);CHECK([decoded[0][@"peeking"] count]==1);
        CHECK(SNPresenceRecords(@[]).count==0);
        CHECK(SNPresenceRecords(@[@{@"conversationId":C}])==nil);
        CHECK(SNPresenceRecords(@[@{@"conversationId":C,@"remoteTypingParticipants":@[@{@"userId":@"invalid"}]}])==nil);
        SNTestPresenceProxy *proxy=[SNTestPresenceProxy new];
        proxy.fixture=[NSString stringWithFormat:@"<typedObject SCCPresencePlatformActiveConversationInfo: { conversationId: %@, remoteTypingParticipants: [ <typedObject T: { typingState: 3, userId: %@ }> ], remotePeekingParticipantUserIds: [ %@ ] }>",C,U,V];
        decoded=SNPresenceRecords(@[proxy]);
        CHECK(decoded.count==1);CHECK([decoded[0][@"typing"][0][@"uid"] isEqual:U]);CHECK([decoded[0][@"peeking"][0][@"uid"] isEqual:V]);
        proxy.fixture=@"<typedObject SCCPresencePlatformActiveConversationInfo: { remoteTypingParticipants: [ truncated";
        CHECK(SNPresenceRecords(@[proxy])==nil);
        NSDictionary *snap=@{@"messageType":@"SNAP",@"senderId":U,@"conversationId":C,@"messageId":@1,@"senderDisplayName":@"José"};
        CHECK(SNReceivedRecords(snap,nil).count==1);
        CHECK([SNReceivedRecords(snap,nil).firstObject[@"kind"] isEqual:@"snap"]);
        NSMutableDictionary *m=[snap mutableCopy];m[@"isOutgoing"]=@YES;CHECK(SNReceivedRecords(m,nil).count==0);
        m=[snap mutableCopy];m[@"isHistorical"]=@YES;CHECK(SNReceivedRecords(m,nil).count==0);
        m=[snap mutableCopy];m[@"messageType"]=@"READ_RECEIPT";CHECK(SNReceivedRecords(m,@"message").count==0);
        m=[snap mutableCopy];[m removeObjectForKey:@"senderId"];CHECK(SNReceivedRecords(m,nil).count==0);
        m=[snap mutableCopy];m[@"messageType"]=@987;CHECK(SNReceivedRecords(m,nil).count==0);
        m=[snap mutableCopy];m[@"messageId"]=@0;CHECK(SNReceivedRecords(m,nil).count==0);
        __block NSUInteger parentHits=0,childHits=0,resolverHits=0;
        CHECK(SNInstallHook(SNTestParent.class,@selector(receive:),^(__unused id self,__unused NSArray *a,__unused id r){parentHits++;}));
        CHECK(SNInstallHook(SNTestChild.class,@selector(receive:),^(__unused id self,__unused NSArray *a,__unused id r){childHits++;}));
        SNTestChild *child=[SNTestChild new];[child receive:@"x"];
        CHECK(child.calls==2);CHECK(parentHits==1);CHECK(childHits==1);
        CHECK(!SNInstallHook(SNTestChild.class,@selector(receive:),^(__unused id self,__unused NSArray *a,__unused id r){}));
        CHECK(!SNInstallHook(SNTestParent.class,@selector(notAnObject:),^(__unused id self,__unused NSArray *a,__unused id r){}));
        CHECK(!SNInstallHook(SNTestParent.class,@selector(init),^(__unused id self,__unused NSArray *a,__unused id r){}));
        CHECK(SNInstallHook(SNTestParent.class,@selector(displayNameForUserId:),^(id self,NSArray *a,id r){
            resolverHits++;CHECK([a.firstObject isEqual:U]);CHECK([r isEqual:@"João 日本語"]);
            /* Re-enter a getter while harvesting: original still executes,
               observer does not recurse. */
            (void)[self displayNameForUserId:U];
        }));
        CHECK([[child displayNameForUserId:U] isEqual:@"João 日本語"]);CHECK(resolverHits==1);CHECK(child.calls==4);
        NSLog(@"Foundation/runtime: %lu checks passed",(unsigned long)checks);
    }
    return 0;
}
