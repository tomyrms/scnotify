#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/* All calls belong to one serial queue. Files contain identifiers + subtype,
   never message bodies, voice data, names, tokens or notification preview text.
   'accepted' means accepted by the OS API, NOT a banner seen by the user. */
@interface SNOutbox : NSObject
- (instancetype)initWithDirectory:(NSString *)directory;
- (nullable NSString *)enqueueEvent:(NSDictionary *)event scope:(NSString *)scope
                            atTime:(double)now error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary *)nextReadyInScopes:(NSSet<NSString *> *)scopes atTime:(double)now;
- (BOOL)finishIdentifier:(NSString *)identifier attempt:(NSUInteger)attempt
                success:(BOOL)success blocked:(BOOL)blocked atTime:(double)now;
- (void)retryBlockedInScopes:(NSSet<NSString *> *)scopes atTime:(double)now;
- (void)bindSessionScope:(NSString *)scope toAccount:(NSString *)account;
- (NSArray<NSString *> *)clear;
- (NSDictionary *)statisticsForScopes:(NSSet<NSString *> *)scopes;
@end
NS_ASSUME_NONNULL_END
