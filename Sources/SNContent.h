#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/* Classification is semantic, never inferred from free-form chat text. */
NSString *SNContentSubtype(id _Nullable message, id _Nullable content);
NSString *SNNotificationBody(NSDictionary *event, NSString * _Nullable name);
/* Remote identity evidence outlives an ephemeral typing session. Queue-owned. */
@interface SNRemoteParticipants : NSObject
- (void)observeUser:(NSString *)uid conversation:(NSString *)conversation atTime:(double)now;
- (BOOL)containsUser:(NSString *)uid conversation:(NSString *)conversation atTime:(double)now;
- (void)reset;
@end
NS_ASSUME_NONNULL_END
