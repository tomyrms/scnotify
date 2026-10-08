#import <Foundation/Foundation.h>
#import "../Core/SNReceivePolicy.h"
NS_ASSUME_NONNULL_BEGIN
/* Numeric mappings are opt-in and scoped to an exact Class.field; there is no
   universal assumption that enum 1/2 means chat/snap across private APIs. */
void SNSetReceiveTypeMappings(NSDictionary *mappings);
NSString * _Nullable SNMessageIdentifier(id _Nullable value);
NSString * _Nullable SNCallbackConversation(NSString *selector, NSArray *arguments);
/* Result: { events: [...], rejected: {reason: count}, shapes: [...], identities: {conversation: [messageID]} }.
   All results are detached Foundation values, never retained host objects. */
NSDictionary *SNDecodeReceived(NSArray *arguments, NSString * _Nullable conversation,
                               NSString * _Nullable hint);
/* Snapshot observers are not receive callbacks. The first image seeds a
   baseline; only subsequent new IDs with fresh creation times can notify. */
@interface SNReceiveTracker : NSObject
/* A positive start permits first-batch incoming records created after start. */
- (instancetype)initWithMonitoringStart:(NSTimeInterval)start;
- (NSArray<NSDictionary *> *)newEventsInSnapshot:(NSArray<NSDictionary *> *)events wallTime:(NSTimeInterval)wall;
- (NSArray<NSDictionary *> *)newEventsInBatch:(NSDictionary *)batch wallTime:(NSTimeInterval)wall;
- (void)reset;
@end
NS_ASSUME_NONNULL_END
