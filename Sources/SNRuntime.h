#import <Foundation/Foundation.h>
#import <objc/runtime.h>
NS_ASSUME_NONNULL_BEGIN
/* Read getters only after checking their signature. Object ivars are a bounded
   fallback; no raw pointer, scalar-as-object or untyped KVC dereference. */
id _Nullable SNRead(id _Nullable object, NSString *key);
NSString * _Nullable SNIdentifier(id _Nullable value);
NSString * _Nullable SNName(id _Nullable value);
NSDictionary * _Nullable SNUserRecord(id _Nullable object, NSString * _Nullable explicitUserID);
NSArray<NSDictionary *> *SNUserRecords(id _Nullable object);
/* nil means unsupported snapshot, [] means a successfully decoded empty one. */
NSArray<NSDictionary *> * _Nullable SNPresenceRecords(id _Nullable object);
NSArray<NSDictionary *> *SNReceivedRecords(id _Nullable object, NSString * _Nullable eventHint);
/* Call observations are made after the original method returns. The captured
   original IMP belongs to this declaring class, never the dynamic receiver. */
typedef void (^SNHookObserver)(id receiver, NSArray *arguments, id _Nullable result);
BOOL SNInstallHook(Class cls, SEL selector, SNHookObserver observer);
/* Sets this thread's inspection guard and always restores it, including on
   exceptions. Hook observers recursively invoked by reads are skipped. */
void SNInspect(dispatch_block_t block);
NS_ASSUME_NONNULL_END
