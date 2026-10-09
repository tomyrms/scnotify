#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const SNPresenceActivityText;
FOUNDATION_EXPORT NSString *const SNPresenceActivityVoice;
FOUNDATION_EXPORT NSString *const SNPresenceActivityUnknown;
FOUNDATION_EXPORT NSString *const SNPresenceActivityInactive;

/* Single-queue cache of complete, detached wire-presence snapshots. Generic
   typing callbacks do not identify the composition medium and must not write
   this cache. The caller owns notification transitions/cancellation. */
@interface SNPresenceActivityTracker : NSObject

/* Each participant contains uid (nonempty NSString), isActive (NSNumber 0/1),
   and, when active, activity (text/voice/unknown). Inactive entries may omit
   activity. Omitted users are inactive because the input is a full snapshot.
   Values are copied. Invalid, oversized, or older snapshots are ignored as a
   whole. now must be finite, nonnegative monotonic seconds on one clock.
   Stores at most 128 conversations, each with at most 256 participants. */
- (BOOL)updateConversation:(NSString *)conversation
             participants:(NSArray<NSDictionary *> *)participants
                     time:(double)now;

/* text/voice/unknown describe an active participant. inactive means a recent
   snapshot explicitly or implicitly reported no composition. nil means no
   current knowledge; the caller must not infer text from that absence.
   Knowledge expires 15 seconds after its snapshot. */
- (nullable NSString *)activityForConversation:(NSString *)conversation
                                       sender:(NSString *)sender
                                         time:(double)now;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
