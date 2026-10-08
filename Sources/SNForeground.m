#import "SNForeground.h"
#import "SNRuntime.h"
#include <stdlib.h>
#include <string.h>

static NSObject *foregroundLock(void) {
    static NSObject *lock;static dispatch_once_t once;
    dispatch_once(&once,^{lock=[NSObject new];});return lock;
}
static const char *foregroundType(const char *type) {
    while(type&&*type&&strchr("rnNoORV",*type))type++;return type;
}
static Method ownMethod(Class cls,SEL selector) {
    unsigned count=0;Method *methods=class_copyMethodList(cls,&count),found=NULL;
    for(unsigned i=0;i<count;i++)if(method_getName(methods[i])==selector){found=methods[i];break;}
    free(methods);return found;
}
static BOOL compatibleMethod(Method method,unsigned arguments) {
    if(!method||method_getNumberOfArguments(method)!=arguments+2)return NO;
    char *raw=method_copyReturnType(method);const char *type=foregroundType(raw);
    BOOL valid=type&&!strcmp(type,"v");free(raw);
    for(unsigned i=2;valid&&i<arguments+2;i++) {
        raw=method_copyArgumentType(method,i);type=foregroundType(raw);
        valid=type&&type[0]=='@';free(raw);
    }
    return valid;
}
static BOOL installMethod(Class cls,SEL selector,IMP replacement,const char *encoding) {
    Method own=ownMethod(cls,selector);
    if(own){method_setImplementation(own,replacement);return YES;}
    if(class_addMethod(cls,selector,replacement,encoding))return YES;
    imp_removeBlock(replacement);return NO;
}
static BOOL isLocalNotice(id notification) {
    id content=SNRead(SNRead(notification,@"request"),@"content");
    id marker=SNRead(SNRead(content,@"userInfo"),@"scnotify");
    return [marker isKindOfClass:NSNumber.class]&&[marker boolValue];
}
BOOL SNInstallForegroundDelegate(Class cls,NSUInteger options) {
    if(!cls||class_isMetaClass(cls))return NO;
    static NSMutableSet *installed;static dispatch_once_t once;
    dispatch_once(&once,^{installed=[NSMutableSet set];});
    @synchronized(foregroundLock()) {
        NSValue *key=[NSValue valueWithPointer:(__bridge const void *)cls];
        if([installed containsObject:key])return YES;
        SEL selector=NSSelectorFromString(@"userNotificationCenter:willPresentNotification:withCompletionHandler:");
        Method method=class_getInstanceMethod(cls,selector);
        if(method&&!compatibleMethod(method,3))return NO;
        IMP original=method?method_getImplementation(method):NULL;
        IMP replacement=imp_implementationWithBlock(^(id self,id center,id notification,void(^completion)(NSUInteger)) {
            if(isLocalNotice(notification)) {if(completion)completion(options);}
            else if(original)((void(*)(id,SEL,id,id,id))original)(self,selector,center,notification,completion);
            else if(completion)completion(0);
        });
        if(!replacement)return NO;
        if(!installMethod(cls,selector,replacement,method?method_getTypeEncoding(method):"v@:@@@?"))return NO;
        [installed addObject:key];return YES;
    }
}
BOOL SNInstallForegroundCenter(Class cls,NSUInteger options) {
    if(!cls||class_isMetaClass(cls))return NO;
    static NSMutableSet *installed;static dispatch_once_t once;
    dispatch_once(&once,^{installed=[NSMutableSet set];});
    @synchronized(foregroundLock()) {
        NSValue *key=[NSValue valueWithPointer:(__bridge const void *)cls];
        if([installed containsObject:key])return YES;
        SEL selector=NSSelectorFromString(@"setDelegate:");
        Method method=class_getInstanceMethod(cls,selector);
        if(!compatibleMethod(method,1))return NO;
        IMP original=method_getImplementation(method);if(!original)return NO;
        IMP replacement=imp_implementationWithBlock(^(id self,id delegate) {
            if(delegate)SNInstallForegroundDelegate(object_getClass(delegate),options);
            ((void(*)(id,SEL,id))original)(self,selector,delegate);
        });
        if(!replacement)return NO;
        if(!installMethod(cls,selector,replacement,method_getTypeEncoding(method)))return NO;
        [installed addObject:key];return YES;
    }
}
