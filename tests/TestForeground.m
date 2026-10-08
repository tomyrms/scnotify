/* Synthetic Foundation delegates: no notification permissions or device needed. */
#import <Foundation/Foundation.h>
#import "../Sources/SNForeground.h"
#include <stdlib.h>
static NSUInteger checks;
#define CHECK(...) do{checks++;if(!(__VA_ARGS__)){NSLog(@"FAILED foreground line %d: %s",__LINE__,#__VA_ARGS__);abort();}}while(0)
@protocol TestPresentation <NSObject>
- (void)userNotificationCenter:(id)center willPresentNotification:(id)notification withCompletionHandler:(void(^)(NSUInteger))completion;
@end
@interface TestHostDelegate : NSObject <TestPresentation>
@property(nonatomic) NSUInteger calls;
@property(nonatomic,strong) id lastNotification;
@end
@implementation TestHostDelegate
- (void)userNotificationCenter:(__unused id)center willPresentNotification:(id)notification withCompletionHandler:(void(^)(NSUInteger))completion {
    self.calls++;self.lastNotification=notification;if(completion)completion(123);
}
@end
@interface TestInheritedDelegate : TestHostDelegate @end
@implementation TestInheritedDelegate @end
@interface TestEmptyDelegate : NSObject @end
@implementation TestEmptyDelegate @end
@interface TestReplacementDelegate : NSObject @end
@implementation TestReplacementDelegate @end
@interface TestInvalidDelegate : NSObject
- (NSUInteger)userNotificationCenter:(id)center willPresentNotification:(id)notification withCompletionHandler:(id)completion;
@end
@implementation TestInvalidDelegate
- (NSUInteger)userNotificationCenter:(__unused id)center willPresentNotification:(__unused id)notification withCompletionHandler:(__unused id)completion {return 9;}
@end
@interface TestCenter : NSObject
@property(nonatomic,weak) id delegate;
@property(nonatomic) BOOL cachedCallback;
@property(nonatomic) NSUInteger setterCalls;
@end
@implementation TestCenter
- (void)setDelegate:(id)delegate {
    _delegate=delegate;self.setterCalls++;
    self.cachedCallback=[delegate respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)];
}
@end
@interface TestInheritedCenter : TestCenter @end
@implementation TestInheritedCenter @end
static void present(id delegate,id notification,NSUInteger expected) {
    __block NSUInteger completions=0;
    [(id<TestPresentation>)delegate userNotificationCenter:nil willPresentNotification:notification withCompletionHandler:^(NSUInteger options){completions++;CHECK(options==expected);}];
    CHECK(completions==1);
}
int main(void) {
 @autoreleasepool {
    NSUInteger options=26; /* Supplied by Tweak using the SDK constants. */
    NSDictionary *local=@{@"request":@{@"content":@{@"userInfo":@{@"scnotify":@YES}}}};
    NSDictionary *host=@{@"request":@{@"content":@{@"userInfo":@{}}}};
    NSDictionary *falseMarker=@{@"request":@{@"content":@{@"userInfo":@{@"scnotify":@NO}}}};
    NSDictionary *invalidMarker=@{@"request":@{@"content":@{@"userInfo":@{@"scnotify":@"yes"}}}};
    SEL selector=@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:);
    IMP parentOriginal=class_getMethodImplementation(TestHostDelegate.class,selector);
    CHECK(SNInstallForegroundDelegate(TestInheritedDelegate.class,options));
    CHECK(class_getMethodImplementation(TestHostDelegate.class,selector)==parentOriginal);
    TestInheritedDelegate *inherited=[TestInheritedDelegate new];
    present(inherited,local,options);CHECK(inherited.calls==0);
    present(inherited,host,123);CHECK(inherited.calls==1);CHECK(inherited.lastNotification==host);
    present(inherited,falseMarker,123);present(inherited,invalidMarker,123);CHECK(inherited.calls==3);
    CHECK(SNInstallForegroundDelegate(TestInheritedDelegate.class,options));
    present(inherited,host,123);CHECK(inherited.calls==4);
    TestHostDelegate *parent=[TestHostDelegate new];present(parent,local,123);CHECK(parent.calls==1);
    CHECK(!SNInstallForegroundDelegate(TestInvalidDelegate.class,options));
    CHECK(!SNInstallForegroundDelegate(Nil,options));
    CHECK(SNInstallForegroundDelegate(TestEmptyDelegate.class,options));
    TestEmptyDelegate *empty=[TestEmptyDelegate new];
    CHECK([empty respondsToSelector:selector]);present(empty,local,options);present(empty,host,0);
    [(id<TestPresentation>)empty userNotificationCenter:nil willPresentNotification:local withCompletionHandler:nil];
    [(id<TestPresentation>)empty userNotificationCenter:nil willPresentNotification:host withCompletionHandler:nil];
    SEL setter=@selector(setDelegate:);
    IMP originalSetter=class_getMethodImplementation(TestCenter.class,setter);
    CHECK(SNInstallForegroundCenter(TestInheritedCenter.class,options));
    CHECK(class_getMethodImplementation(TestCenter.class,setter)==originalSetter);
    CHECK(SNInstallForegroundCenter(TestInheritedCenter.class,options));
    TestInheritedCenter *center=[TestInheritedCenter new];
    TestReplacementDelegate *replacement=[TestReplacementDelegate new];
    CHECK(![replacement respondsToSelector:selector]);center.delegate=replacement;
    CHECK(center.cachedCallback);CHECK(center.delegate==replacement);CHECK(center.setterCalls==1);
    present(replacement,local,options);present(replacement,host,0);
    center.delegate=inherited;CHECK(center.delegate==inherited);CHECK(center.cachedCallback);CHECK(center.setterCalls==2);
    present(center.delegate,host,123);CHECK(inherited.calls==5);
    center.delegate=nil;CHECK(center.delegate==nil);CHECK(!center.cachedCallback);CHECK(center.setterCalls==3);
    CHECK(SNInstallForegroundDelegate(TestHostDelegate.class,options));
    present(parent,local,options);CHECK(parent.calls==1);present(parent,host,123);CHECK(parent.calls==2);
    CHECK(!SNInstallForegroundCenter(TestEmptyDelegate.class,options));
    NSLog(@"Foreground delegate routing: %lu checks passed",(unsigned long)checks);
 }
 return 0;
}
