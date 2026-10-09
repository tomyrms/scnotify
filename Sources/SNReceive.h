#import <Foundation/Foundation.h>
#import "../Core/SNReceivePolicy.h"
NS_ASSUME_NONNULL_BEGIN
/* Explicit overrides are scoped to an exact Class.field. Native compatibility
   is separately bounded to the observed messaging model and host version. */
void SNSetReceiveTypeMappings(NSDictionary *mappings);
void SNSetReceiveHostVersion(NSString *version);
/* Snapshot adapter for the exact four-argument Arroyo callback. Removed
   messages and conversation history are not new-message candidates. */
NSDictionary *SNDecodeReceiveCallback(NSString *className, NSString *selector, NSArray *arguments);
/* Return an incoming flag only with independent direction evidence. */
NSDictionary *SNResolveReceiveDirection(NSDictionary *event, NSString * _Nullable account, BOOL knownRemote);
NSString * _Nullable SNLocalAccountIdentifier(id _Nullable object);
NSString * _Nullable SNMessageIdentifier(id _Nullable value);
NSString * _Nullable SNCallbackConversation(NSString *selector, NSArray *arguments);
/* Result: { events: [...], rejected: {reason: count}, shapes: [...], identities: {conversation: [messageID]} }.
   All results are detached Foundation values, never retained host objects. */
NSDictionary *SNDecodeReceived(NSArray *arguments, NSString * _Nullable conversation,
                               NSString * _Nullable hint);
/* Message events may include subtype="voice" when a native semantic getter
   or symbolic content type identifies a voice note; no numeric enum guessing.
   Snapshot observers are not receive callbacks. Old first-batch records seed
   a baseline; newly created incoming IDs can notify under the date/direction
   gates, including first-batch records created since monitoring began.
   Incomplete live records await timestamp/direction evidence, preserving the
   original monitoring/baseline time even when callbacks arrive late. Duplicate
   representations in a callback can supply missing metadata. Seen identities
   expire after the entire date-eligibility horizon instead of filling forever. */
@interface SNReceiveTracker : NSObject
/* A positive start permits first-batch incoming records created after start. */
- (instancetype)initWithMonitoringStart:(NSTimeInterval)start;
- (NSArray<NSDictionary *> *)newEventsInSnapshot:(NSArray<NSDictionary *> *)events wallTime:(NSTimeInterval)wall;
- (NSArray<NSDictionary *> *)newEventsInBatch:(NSDictionary *)batch wallTime:(NSTimeInterval)wall;
- (void)reset;
@end
NS_ASSUME_NONNULL_END
