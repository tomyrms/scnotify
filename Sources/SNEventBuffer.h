#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/* Single-queue FIFO. Holds detached values while notification submissions are
   in flight, so a burst does not consume all pending ledger tickets at once. */
@interface SNEventBuffer : NSObject
@property(nonatomic,readonly) NSUInteger count;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
/* YES also for an already queued key; NO means capacity was reached. */
- (BOOL)enqueue:(NSDictionary *)event key:(NSString *)key;
- (nullable NSDictionary *)takeFirst;
- (void)removeKey:(NSString *)key;
- (void)removeAll;
@end
NS_ASSUME_NONNULL_END
