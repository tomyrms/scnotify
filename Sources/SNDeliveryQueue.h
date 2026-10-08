#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@class SNOutbox;

/* The content delivery lane owns disk I/O and retry state. It never runs on
   Snapchat's callback queue or on the immediate call/presence event lane. */
typedef void (^SNContentSubmitter)(NSDictionary *event, NSString *identifier,
                                  void (^completion)(NSError * _Nullable));
typedef void (^SNDeliveryReporter)(NSString *stage, NSDictionary *details);
FOUNDATION_EXPORT NSString * const SNDeliveryBlockedErrorDomain;

@interface SNDeliveryQueue : NSObject
- (instancetype)initWithDirectory:(NSString *)directory
                        submitter:(SNContentSubmitter)submitter
                         reporter:(SNDeliveryReporter)reporter;
/* Injectable loader for deterministic storage-stall and failure tests. It is
   invoked asynchronously on the private lane, never on the calling thread. */
- (instancetype)initWithStorageFactory:(SNOutbox * _Nullable (^)(void))factory
                            submitter:(SNContentSubmitter)submitter
                             reporter:(SNDeliveryReporter)reporter;
/* These methods only enqueue work; none synchronously wait for storage. */
- (void)configureScopes:(NSSet<NSString *> *)scopes
               session:(NSString *)sessionScope
               account:(nullable NSString *)account
               enabled:(BOOL)enabled spacing:(NSTimeInterval)spacing;
- (void)enqueueEvent:(NSDictionary *)event scope:(NSString *)scope;
- (void)resumeBlocked;
- (void)requestDrain;
- (void)clearWithCompletion:(void (^)(NSArray<NSString *> *identifiers))completion;
- (void)statisticsWithCompletion:(void (^)(NSDictionary *statistics))completion;
@end
/* Always asynchronous, including when called from queue itself. In particular
   never switch to dispatch_sync when the receiver is saturated. */
FOUNDATION_EXPORT void SNEnqueueObservedWork(dispatch_queue_t queue, dispatch_block_t work);
NS_ASSUME_NONNULL_END
