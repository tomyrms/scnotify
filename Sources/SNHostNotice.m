#import "SNHostNotice.h"
#import "SNRuntime.h"
#import "SNReceive.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static NSString *noticeText(id value, NSUInteger limit) {
    if([value isKindOfClass:NSAttributedString.class])value=[value string];
    if(![value isKindOfClass:NSString.class]||![value length]||[value length]>limit)return nil;
    /* Newlines are legal notification text. Other C0 control characters are not. */
    for(NSUInteger i=0;i<[value length];i++){
        unichar c=[value characterAtIndex:i];if(c<32&&c!='\n'&&c!='\r'&&c!='\t')return nil;
    }
    return [value copy];
}
static NSString *firstText(id object, NSArray *keys, NSUInteger limit) {
    for(NSString *key in keys){NSString *text=noticeText(SNRead(object,key),limit);if(text)return text;}return nil;
}
static NSDictionary *noticeAtDepth(id object, NSString *inheritedIdentity, NSHashTable *seen,
                                  unsigned depth, unsigned *budget) {
    if(!object||object==NSNull.null||depth>=4||!*budget||[seen containsObject:object])return nil;
    --*budget;[seen addObject:object];
    for(NSString *key in @[@"isHistorical",@"fromHistory",@"isOutgoing",@"isFromMe",@"scnotify"]){
        id value=SNRead(object,key);if([value isKindOfClass:NSNumber.class]&&[value boolValue])return nil;
    }
    /* Our local-notification marker lives in UNNotificationContent.userInfo. */
    id ownMarker=SNRead(SNRead(object,@"userInfo"),@"scnotify");
    if([ownMarker isKindOfClass:NSNumber.class]&&[ownMarker boolValue])return nil;
    NSString *identity=SNMessageIdentifier(SNRead(object,@"notificationId")) ?:
        SNMessageIdentifier(SNRead(object,@"notificationIdentifier")) ?: inheritedIdentity;
    NSString *title=firstText(object,@[@"title",@"notificationTitle"],256);
    NSString *body=firstText(object,@[@"body",@"notificationBody",@"messageText",@"text",@"message"],4096);
    if(title.length&&body.length) {
        NSMutableDictionary *notice=[@{@"title":title,@"body":body} mutableCopy];
        if(identity)notice[@"id"]=identity;
        return [notice copy];
    }
    /* Null or unsupported aliases must not hide another supported envelope.
       Preserve the envelope's stable ID when its text is in nested content. */
    for(NSString *key in @[@"notificationContent",@"content",@"notification"]) {
        id child=SNRead(object,key);
        if(!child||child==NSNull.null||[child isKindOfClass:NSString.class]||[child isKindOfClass:NSData.class])continue;
        NSDictionary *notice=noticeAtDepth(child,identity,seen,depth+1,budget);if(notice)return notice;
    }
    return nil;
}
NSDictionary *SNHostNotice(id payload) {
    NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality|NSPointerFunctionsStrongMemory];
    unsigned budget=16;
    return noticeAtDepth(payload,nil,seen,0,&budget);
}
id SNTransportJSON(id payload) {
    if([payload isKindOfClass:NSDictionary.class]||[payload isKindOfClass:NSArray.class])return payload;
    if(![payload isKindOfClass:NSData.class]||![payload length]||[payload length]>256*1024)return nil;
    const uint8_t *bytes=[payload bytes];NSUInteger length=[payload length],i=0;
    while(i<length&&(bytes[i]==' '||bytes[i]=='\n'||bytes[i]=='\r'||bytes[i]=='\t'))i++;
    if(i==length||(bytes[i]!='{'&&bytes[i]!='['))return nil;
    id value=[NSJSONSerialization JSONObjectWithData:payload options:0 error:NULL];
    return [value isKindOfClass:NSDictionary.class]||[value isKindOfClass:NSArray.class]?value:nil;
}

/* Apple Blocks ABI, documented by Clang. No invoke-pointer calls or guesses
   about a block's argument types. The original is called as its verified type. */
struct SNBlockHeader {void *isa;int flags;int reserved;void *invoke;const void *descriptor;};
static const char *skipQualifiers(const char *type) {while(type&&*type&&strchr("rnNoORV",*type))type++;return type;}
static BOOL unaryObjectBlock(id object) {
    Class blockClass=NSClassFromString(@"NSBlock");
    if(!object||!blockClass||![object isKindOfClass:blockClass])return NO;
    const struct SNBlockHeader *b=(__bridge const void *)object;
    if(!(b->flags&(1U<<30))||!b->descriptor)return NO;
    const uint8_t *d=b->descriptor;d+=2*sizeof(unsigned long);
    if(b->flags&(1U<<25))d+=2*sizeof(void *);
    const char *signature=NULL;memcpy(&signature,d,sizeof(signature));if(!signature)return NO;
    @try {
        NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:signature];
        if(sig.numberOfArguments!=2||strcmp(skipQualifiers(sig.methodReturnType),"v"))return NO;
        const char *arg=skipQualifiers([sig getArgumentTypeAtIndex:1]);
        return arg&&arg[0]=='@'&&arg[1]!='?';
    } @catch(__unused NSException *e){return NO;}
}
id SNWrapNoticeBlock(id block,SNNoticeObserver observer) {
    if(!unaryObjectBlock(block)||!observer)return nil;
    void (^original)(id)=[block copy];
    return [^(id payload){
        SNInspect(^{if(payload)observer(payload);});
        original(payload);
    } copy];
}
BOOL SNInstallNoticeChoice(Class cls,SNNoticeObserver observer) {
    if(!cls||!observer)return NO;
    static NSMutableSet *installed;static dispatch_once_t once;
    dispatch_once(&once,^{installed=[NSMutableSet set];});
    @synchronized(installed) {
        NSString *key=NSStringFromClass(cls);if([installed containsObject:key])return NO;
        SEL sel=NSSelectorFromString(@"matchInAppNotification:systemNotification:");
        unsigned count=0;Method *methods=class_copyMethodList(cls,&count);Method method=NULL;
        for(unsigned i=0;i<count;i++)if(method_getName(methods[i])==sel){method=methods[i];break;}free(methods);
        if(!method||method_getNumberOfArguments(method)!=4)return NO;
        char *ret=method_copyReturnType(method);BOOL good=ret&&!strcmp(skipQualifiers(ret),"v");free(ret);
        for(unsigned i=2;i<4&&good;i++){char *a=method_copyArgumentType(method,i);const char *t=skipQualifiers(a);good=t&&t[0]=='@';free(a);}
        if(!good)return NO;
        IMP original=method_getImplementation(method);if(!original)return NO;
        SNNoticeObserver observe=[observer copy];
        IMP replacement=imp_implementationWithBlock(^(id self,id inApp,id system){
            id wrapped=SNWrapNoticeBlock(inApp,observe);
            ((void(*)(id,SEL,id,id))original)(self,sel,wrapped?:inApp,system);
        });
        if(!replacement)return NO;
        method_setImplementation(method,replacement);[installed addObject:key];return YES;
    }
}
