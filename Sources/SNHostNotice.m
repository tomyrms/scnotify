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
NSDictionary *SNHostNotice(id payload) {
    if(!payload)return nil;
    NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    id object=payload;
    for(unsigned depth=0;object&&depth<4;depth++) {
        if([seen containsObject:object])return nil;[seen addObject:object];
        for(NSString *key in @[@"isHistorical",@"fromHistory",@"isOutgoing",@"isFromMe",@"scnotify"]){
            id value=SNRead(object,key);if([value isKindOfClass:NSNumber.class]&&[value boolValue])return nil;
        }
        NSString *title=firstText(object,@[@"title",@"notificationTitle"],256);
        NSString *body=firstText(object,@[@"body",@"notificationBody",@"messageText",@"text",@"message"],4096);
        if(title.length&&body.length) {
            NSMutableDictionary *notice=[@{@"title":title,@"body":body} mutableCopy];
            NSString *identity=SNMessageIdentifier(SNRead(object,@"notificationId")) ?: SNMessageIdentifier(SNRead(object,@"notificationIdentifier"));
            if(identity)notice[@"id"]=identity;
            return [notice copy];
        }
        id next=SNRead(object,@"notificationContent") ?: SNRead(object,@"content") ?: SNRead(object,@"notification");
        if(!next||[next isKindOfClass:NSString.class]||[next isKindOfClass:NSData.class])return nil;
        object=next;
    }
    return nil;
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
