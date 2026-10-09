#import <Foundation/Foundation.h>
#import "../Sources/SNPresenceActivity.h"
#include <math.h>
#include <stdlib.h>
#define CHECK(...) do { if (!(__VA_ARGS__)) { NSLog(@"FAILED presence activity line %d", __LINE__); abort(); } } while (0)

static NSDictionary *Active(NSString *uid, NSString *activity) {
    return @{@"uid": uid, @"activity": activity, @"isActive": @YES};
}
static NSString *Lookup(SNPresenceActivityTracker *tracker, NSString *uid, double now) {
    return [tracker activityForConversation:@"conversation" sender:uid time:now];
}

int main(void) { @autoreleasepool {
    SNPresenceActivityTracker *tracker = [SNPresenceActivityTracker new];
    CHECK(Lookup(tracker, @"alice", 1) == nil);

    /* Explicit media can coexist in a group. Generic composition remains
       unknown, never inferred to be text merely because isActive is true. */
    NSArray *group = @[Active(@"alice", @"voice"), Active(@"bob", @"text"),
                       Active(@"carol", @"unknown")];
    CHECK([tracker updateConversation:@"conversation" participants:group time:100]);
    CHECK([Lookup(tracker, @"alice", 100) isEqual:SNPresenceActivityVoice]);
    CHECK([Lookup(tracker, @"bob", 100) isEqual:SNPresenceActivityText]);
    CHECK([Lookup(tracker, @"carol", 100) isEqual:SNPresenceActivityUnknown]);
    CHECK([Lookup(tracker, @"absent", 100) isEqual:SNPresenceActivityInactive]);

    /* A new full snapshot replaces the old one: omission and explicit stop
       both erase stale recording/text states. A sender can switch medium. */
    CHECK([tracker updateConversation:@"conversation"
        participants:@[Active(@"alice", @"text"), @{@"uid": @"bob", @"isActive": @NO}]
        time:101]);
    CHECK([Lookup(tracker, @"alice", 101) isEqual:SNPresenceActivityText]);
    CHECK([Lookup(tracker, @"bob", 101) isEqual:SNPresenceActivityInactive]);
    CHECK([Lookup(tracker, @"carol", 101) isEqual:SNPresenceActivityInactive]);
    CHECK([tracker updateConversation:@"conversation" participants:@[] time:102]);
    CHECK([Lookup(tracker, @"alice", 102) isEqual:SNPresenceActivityInactive]);

    /* A snapshot for a different conversation cannot classify this sender. */
    CHECK([tracker updateConversation:@"other" participants:@[Active(@"alice", @"voice")] time:102]);
    CHECK([Lookup(tracker, @"alice", 102) isEqual:SNPresenceActivityInactive]);
    CHECK([[tracker activityForConversation:@"other" sender:@"alice" time:102] isEqual:SNPresenceActivityVoice]);
    CHECK([tracker activityForConversation:@"unseen" sender:@"alice" time:102] == nil);

    /* Time boundaries and stale arrivals: old media must not revive. */
    CHECK(![tracker updateConversation:@"conversation" participants:group time:101]);
    CHECK([Lookup(tracker, @"alice", 102) isEqual:SNPresenceActivityInactive]);
    CHECK(Lookup(tracker, @"alice", 101) == nil);
    CHECK([Lookup(tracker, @"alice", 116.999) isEqual:SNPresenceActivityInactive]);
    CHECK(Lookup(tracker, @"alice", 117) == nil);
    CHECK(Lookup(tracker, @"alice", NAN) == nil);
    CHECK(Lookup(tracker, @"alice", INFINITY) == nil);
    CHECK(![tracker updateConversation:@"conversation" participants:group time:NAN]);
    CHECK(![tracker updateConversation:@"conversation" participants:group time:-1]);

    /* Invalid/ambiguous input fails atomically, preserving valid evidence. */
    CHECK([tracker updateConversation:@"conversation" participants:group time:200]);
    CHECK(![tracker updateConversation:@"conversation" participants:@[Active(@"alice", @"voice"), Active(@"alice", @"text")] time:201]);
    CHECK(![tracker updateConversation:@"conversation" participants:@[@{@"uid": @"alice", @"isActive": @YES}] time:201]);
    CHECK(![tracker updateConversation:@"conversation" participants:@[Active(@"alice", @"1")] time:201]);
    CHECK(![tracker updateConversation:@"conversation" participants:@[@{@"uid": @"alice", @"isActive": @3, @"activity": @"text"}] time:201]);
    CHECK(![tracker updateConversation:@"conversation" participants:@[@{@"uid": @"alice", @"isActive": @"yes", @"activity": @"text"}] time:201]);
    CHECK(![tracker updateConversation:@"conversation" participants:@[@{}] time:201]);
    CHECK(![tracker updateConversation:@"" participants:group time:201]);
    CHECK([Lookup(tracker, @"alice", 201) isEqual:SNPresenceActivityVoice]);

    /* Snapshots detach mutable data before the source callback returns. */
    NSMutableString *cid = [@"mutable" mutableCopy];
    NSMutableString *uid = [@"dana" mutableCopy];
    NSMutableDictionary *participant = [Active(uid, @"voice") mutableCopy];
    NSMutableArray *participants = [NSMutableArray arrayWithObject:participant];
    CHECK([tracker updateConversation:cid participants:participants time:200]);
    [cid appendString:@"-changed"]; [uid appendString:@"-changed"];
    participant[@"activity"] = @"text"; [participants removeAllObjects];
    CHECK([[tracker activityForConversation:@"mutable" sender:@"dana" time:201] isEqual:SNPresenceActivityVoice]);

    /* Capacity is bounded without partially applying an oversized snapshot. */
    NSMutableArray *large = [NSMutableArray new];
    for (NSUInteger i = 0; i < 256; i++) [large addObject:Active([@(i) stringValue], @"text")];
    CHECK([tracker updateConversation:@"conversation" participants:large time:202]);
    [large addObject:Active(@"overflow", @"voice")];
    CHECK(![tracker updateConversation:@"conversation" participants:large time:203]);
    CHECK([Lookup(tracker, @"255", 203) isEqual:SNPresenceActivityText]);
    CHECK([Lookup(tracker, @"overflow", 203) isEqual:SNPresenceActivityInactive]);

    [tracker reset]; CHECK(Lookup(tracker, @"255", 203) == nil);
    for (NSUInteger i = 0; i < 128; i++) {
        CHECK([tracker updateConversation:[@(i) stringValue] participants:group time:300]);
    }
    /* Refreshing the oldest conversation keeps it; the next oldest is evicted. */
    CHECK([tracker updateConversation:@"0" participants:group time:301]);
    CHECK([tracker updateConversation:@"new" participants:group time:301]);
    CHECK([[tracker activityForConversation:@"0" sender:@"alice" time:302] isEqual:SNPresenceActivityVoice]);
    CHECK([tracker activityForConversation:@"1" sender:@"alice" time:302] == nil);
    CHECK([[tracker activityForConversation:@"127" sender:@"alice" time:302] isEqual:SNPresenceActivityVoice]);
    [tracker reset];
    CHECK([tracker activityForConversation:@"new" sender:@"alice" time:302] == nil);
    NSLog(@"PASS presence activity: distinct media, group isolation, stops, expiry, invalid input, ownership, capacity and reset");
} return 0; }
