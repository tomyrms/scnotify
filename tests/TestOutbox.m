#import <Foundation/Foundation.h>
#import "../Sources/SNOutbox.h"
#import "../Sources/SNContent.h"
#import "../Sources/SNReceive.h"
#include <math.h>
#include <stdlib.h>
static NSUInteger checks;
#define CHECK(x) do{checks++;if(!(x)){NSLog(@"FAILED outbox line %d: %s",__LINE__,#x);abort();}}while(0)
static NSString * const U=@"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
static NSString * const C=@"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
static NSString * const ME=@"cccccccc-cccc-4ccc-8ccc-cccccccccccc";
static NSDictionary *event(NSUInteger i,NSString *subtype) {
    return @{@"uid":U,@"conversation":C,@"event":[@(i) stringValue],@"kind":@"message",@"subtype":subtype,@"body":@"DO_NOT_PERSIST_BODY",@"name":@"DO_NOT_PERSIST_NAME"};
}
static NSString *temp(void) {return [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];}
int main(void){@autoreleasepool{
    NSString *dir=temp();SNOutbox *q=[[SNOutbox alloc] initWithDirectory:dir];NSSet *scope=[NSSet setWithObject:ME];NSError *err=nil;
    CHECK([q enqueueEvent:@{} scope:ME atTime:1 error:&err]==nil);CHECK(err.code==1);
    CHECK([q enqueueEvent:event(1,@"voice") scope:ME atTime:NAN error:&err]==nil);
    CHECK([q enqueueEvent:event(1,@"voice") scope:ME atTime:100 error:&err]!=nil);CHECK(err==nil);
    NSString *id1=[q enqueueEvent:event(1,@"voice") scope:ME atTime:100 error:NULL];CHECK([id1 hasPrefix:@"snapnotify.content."]);
    CHECK([[q statisticsForScopes:scope][@"pending"] integerValue]==1);
    // Every distinct message survives an identical sender/type and a >15s backlog.
    for(NSUInteger i=2;i<=600;i++)CHECK([q enqueueEvent:event(i,i%2?@"voice":@"sticker") scope:ME atTime:100 error:NULL]!=nil);
    q=[[SNOutbox alloc] initWithDirectory:dir];CHECK([[q statisticsForScopes:scope][@"pending"] integerValue]==600);
    NSMutableSet *unique=[NSMutableSet set];
    for(NSUInteger i=1;i<=600;i++){
        NSDictionary *r=[q nextReadyInScopes:scope atTime:1000+i];CHECK(r!=nil);CHECK([r[@"event"][@"event"] isEqual:[@(i) stringValue]]);
        CHECK(![unique containsObject:r[@"id"]]);[unique addObject:r[@"id"]];
        CHECK(r[@"event"][@"body"]==nil);CHECK(r[@"event"][@"name"]==nil);
        CHECK([q finishIdentifier:r[@"id"] attempt:[r[@"attempt"] unsignedIntegerValue] success:YES blocked:NO atTime:1000+i]);
    }
    CHECK(unique.count==600);CHECK([q nextReadyInScopes:scope atTime:2000]==nil);
    q=[[SNOutbox alloc] initWithDirectory:dir];CHECK([[q statisticsForScopes:scope][@"accepted"] integerValue]==600);
    CHECK([[q statisticsForScopes:scope][@"pending"] integerValue]==0);
    // Reclassification / duplicate callback must not create another banner.
    CHECK([[q enqueueEvent:event(1,@"text") scope:ME atTime:2001 error:NULL] isEqual:id1]);CHECK([q nextReadyInScopes:scope atTime:2001]==nil);
    // Retry uses exactly the same ID and does not block later messages.
    NSString *retry=[q enqueueEvent:event(601,@"voice") scope:ME atTime:2002 error:NULL];
    NSDictionary *r=[q nextReadyInScopes:scope atTime:2002];CHECK([r[@"id"] isEqual:retry]);
    CHECK([q finishIdentifier:retry attempt:1 success:NO blocked:NO atTime:2002]);CHECK([q nextReadyInScopes:scope atTime:2003]==nil);
    [q enqueueEvent:event(602,@"media") scope:ME atTime:2003 error:NULL];r=[q nextReadyInScopes:scope atTime:2003];CHECK([r[@"event"][@"event"] isEqual:@"602"]);
    CHECK([q finishIdentifier:r[@"id"] attempt:1 success:YES blocked:NO atTime:2003]);
    r=[q nextReadyInScopes:scope atTime:2004];CHECK([r[@"id"] isEqual:retry]);CHECK([r[@"attempt"] integerValue]==2);
    CHECK(![q finishIdentifier:retry attempt:1 success:NO blocked:YES atTime:2004]);
    CHECK([q finishIdentifier:retry attempt:2 success:NO blocked:YES atTime:2004]);
    CHECK([[q statisticsForScopes:scope][@"blocked"] integerValue]==1);CHECK([q nextReadyInScopes:scope atTime:99999]==nil);
    [q retryBlockedInScopes:scope atTime:2005];r=[q nextReadyInScopes:scope atTime:2005];CHECK([r[@"id"] isEqual:retry]);
    CHECK([q finishIdentifier:retry attempt:3 success:YES blocked:NO atTime:2005]);
    // Lack of a completion handler times out on a later attempt, never deletes.
    NSString *timeoutID=[q enqueueEvent:event(603,@"voice") scope:ME atTime:2100 error:NULL];r=[q nextReadyInScopes:scope atTime:2100];CHECK([r[@"id"] isEqual:timeoutID]);
    CHECK([q nextReadyInScopes:scope atTime:2114]==nil);r=[q nextReadyInScopes:scope atTime:2115];CHECK([r[@"id"] isEqual:timeoutID]);CHECK([r[@"attempt"] integerValue]==2);
    CHECK(![q finishIdentifier:timeoutID attempt:1 success:YES blocked:NO atTime:2116]);CHECK([q finishIdentifier:timeoutID attempt:2 success:YES blocked:NO atTime:2116]);
    // Unknown-account records cannot leak into an unrelated login after relaunch.
    [q enqueueEvent:event(604,@"voice") scope:@"session/old" atTime:2200 error:NULL];
    q=[[SNOutbox alloc] initWithDirectory:dir];CHECK([q nextReadyInScopes:scope atTime:9999]==nil);CHECK([[q statisticsForScopes:scope][@"heldForAccount"] integerValue]==1);
    CHECK([q nextReadyInScopes:[NSSet setWithObject:@"session/old"] atTime:9999]!=nil);
    [q bindSessionScope:@"session/old" toAccount:ME];
    CHECK([[q statisticsForScopes:scope][@"heldForAccount"] integerValue]==0);
    NSString *adopted=[q enqueueEvent:event(604,@"voice") scope:ME atTime:11000 error:NULL];
    CHECK([[q statisticsForScopes:scope][@"pending"] integerValue]==1);
    q=[[SNOutbox alloc] initWithDirectory:dir];r=[q nextReadyInScopes:scope atTime:11000];CHECK([r[@"id"] isEqual:adopted]);
    // Names/body redaction is verified in the real files, not just the API.
    for(NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:NULL]){
        NSDictionary *record=[NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:file]];
        CHECK(record[@"event"][@"body"]==nil);CHECK(record[@"event"][@"name"]==nil);
    }
    // Disk unavailable: submission remains possible in memory and is reported.
    NSString *blocked=temp();[@"not a directory" writeToFile:blocked atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    SNOutbox *memory=[[SNOutbox alloc] initWithDirectory:blocked];err=nil;
    CHECK([memory enqueueEvent:event(1,@"voice") scope:ME atTime:1 error:&err]!=nil);CHECK(err.code==3);CHECK([memory nextReadyInScopes:scope atTime:1]!=nil);
    CHECK([[memory statisticsForScopes:scope][@"ioFailures"] unsignedIntegerValue]>0);
    // Remote participant facts remain usable 10 and 30 min after typing stopped.
    SNRemoteParticipants *remote=[SNRemoteParticipants new];[remote observeUser:U conversation:C atTime:100];
    CHECK([remote containsUser:U conversation:C atTime:700]);CHECK([remote containsUser:U conversation:C atTime:1900]);
    CHECK(![remote containsUser:ME conversation:C atTime:700]);CHECK(![remote containsUser:U conversation:ME atTime:700]);
    CHECK(![remote containsUser:U conversation:C atTime:99]);[remote reset];CHECK(![remote containsUser:U conversation:C atTime:700]);
    [remote observeUser:U conversation:C atTime:100];CHECK(![remote containsUser:U conversation:C atTime:86501]);
    // User-facing labels and symbolic metadata; body text never selects a type.
    CHECK([SNContentSubtype(@{@"isVoiceNote":@YES},nil) isEqual:@"voice"]);
    CHECK([SNContentSubtype(@{@"isSingleImageChatMedia":@YES},nil) isEqual:@"photo"]);
    CHECK([SNContentSubtype(@{@"isChatMediaMessage":@YES},nil) isEqual:@"media"]);
    CHECK([SNContentSubtype(@{@"isStickerMessage":@YES},nil) isEqual:@"sticker"]);
    CHECK([SNContentSubtype(@{@"isStoryReplyMessage":@YES},nil) isEqual:@"story_reply"]);
    CHECK([SNContentSubtype(@{@"isContentShareMessage":@YES},nil) isEqual:@"share"]);
    CHECK([SNContentSubtype(@{@"body":@"AUDIO_NOTE"},nil) isEqual:@"text"]);
    CHECK([SNContentSubtype(nil,@{@"contentType":@"CONTENT_TYPE_AUDIO_NOTE"}) isEqual:@"voice"]);
    CHECK([SNNotificationBody(event(1,@"voice"),@"José") isEqual:@"José t’a envoyé un message vocal"]);
    CHECK([SNNotificationBody(event(1,@"photo"),@"José") containsString:@"photo"]);
    CHECK([SNNotificationBody(@{@"kind":@"snap"},@"José") isEqual:@"José t’a envoyé un snap"]);
    CHECK([SNNotificationBody(@{@"kind":@"typing"},@"José") isEqual:@"José est en train d’écrire…"]);
    NSArray *all=[q clear];CHECK(all.count==604);CHECK([[q statisticsForScopes:scope][@"pending"] integerValue]==0);
    [NSFileManager.defaultManager removeItemAtPath:dir error:NULL];[NSFileManager.defaultManager removeItemAtPath:blocked error:NULL];
    NSLog(@"Outbox/burst/content: %lu checks passed (600 distinct persisted messages)",(unsigned long)checks);
}return 0;}
