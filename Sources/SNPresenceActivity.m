#import "SNPresenceActivity.h"
#include <math.h>

NSString *const SNPresenceActivityText = @"text";
NSString *const SNPresenceActivityVoice = @"voice";
NSString *const SNPresenceActivityUnknown = @"unknown";
NSString *const SNPresenceActivityInactive = @"inactive";

static const NSUInteger SNPresenceMaxConversations = 128;
static const NSUInteger SNPresenceMaxParticipants = 256;
static const NSUInteger SNPresenceMaxIdentifierLength = 128;
static const double SNPresenceKnowledgeLifetime = 15.0;

static BOOL SNPresenceValidIdentifier(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 &&
        [value length] <= SNPresenceMaxIdentifierLength;
}

@interface SNPresenceConversationSnapshot : NSObject
@property(nonatomic) double time;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *activities;
@end
@implementation SNPresenceConversationSnapshot
@end

@implementation SNPresenceActivityTracker {
    NSMutableDictionary<NSString *, SNPresenceConversationSnapshot *> *_conversations;
    NSMutableArray<NSString *> *_order;
}

- (instancetype)init {
    if ((self = [super init])) {
        _conversations = [NSMutableDictionary new];
        _order = [NSMutableArray new];
    }
    return self;
}

- (BOOL)updateConversation:(NSString *)conversation
             participants:(NSArray<NSDictionary *> *)participants
                     time:(double)now {
    if (!SNPresenceValidIdentifier(conversation) || !isfinite(now) || now < 0 ||
        ![participants isKindOfClass:NSArray.class] ||
        participants.count > SNPresenceMaxParticipants) return NO;
    SNPresenceConversationSnapshot *previous = _conversations[conversation];
    if (previous && now < previous.time) return NO;

    NSMutableDictionary<NSString *, NSString *> *activities = [NSMutableDictionary new];
    for (id entry in participants) {
        if (![entry isKindOfClass:NSDictionary.class]) return NO;
        id uid = entry[@"uid"];
        id active = entry[@"isActive"];
        if (!SNPresenceValidIdentifier(uid) || activities[uid] ||
            ![active isKindOfClass:NSNumber.class]) return NO;
        double activeValue = [active doubleValue];
        if (activeValue != 0.0 && activeValue != 1.0) return NO;

        NSString *activity = SNPresenceActivityInactive;
        if (activeValue == 1.0) {
            id medium = entry[@"activity"];
            if ([medium isEqual:SNPresenceActivityText]) activity = SNPresenceActivityText;
            else if ([medium isEqual:SNPresenceActivityVoice]) activity = SNPresenceActivityVoice;
            else if ([medium isEqual:SNPresenceActivityUnknown]) activity = SNPresenceActivityUnknown;
            else return NO;
        }
        activities[[uid copy]] = activity;
    }

    NSString *key = [conversation copy];
    SNPresenceConversationSnapshot *snapshot = [SNPresenceConversationSnapshot new];
    snapshot.time = now;
    snapshot.activities = activities;
    if (previous) [_order removeObject:key];
    else if (_conversations.count >= SNPresenceMaxConversations) {
        NSString *oldest = _order.firstObject;
        [_conversations removeObjectForKey:oldest];
        [_order removeObjectAtIndex:0];
    }
    _conversations[key] = snapshot;
    [_order addObject:key];
    return YES;
}

- (NSString *)activityForConversation:(NSString *)conversation
                               sender:(NSString *)sender
                                 time:(double)now {
    if (!SNPresenceValidIdentifier(conversation) || !SNPresenceValidIdentifier(sender) ||
        !isfinite(now) || now < 0) return nil;
    SNPresenceConversationSnapshot *snapshot = _conversations[conversation];
    if (!snapshot || now < snapshot.time ||
        now - snapshot.time >= SNPresenceKnowledgeLifetime) return nil;
    return snapshot.activities[sender] ?: SNPresenceActivityInactive;
}

- (void)reset {
    [_conversations removeAllObjects];
    [_order removeAllObjects];
}
@end
