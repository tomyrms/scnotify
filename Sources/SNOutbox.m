#import "SNOutbox.h"
#import "SNRuntime.h"
#import "SNReceive.h"
#import <CommonCrypto/CommonDigest.h>
#include <math.h>

static NSString *identifierFor(NSDictionary *e,NSString *scope) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:@[scope,e[@"kind"],e[@"conversation"],e[@"uid"],e[@"event"]] options:0 error:NULL];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);
    NSMutableString *s=[NSMutableString stringWithString:@"snapnotify.content."];
    for(NSUInteger i=0;i<sizeof(hash);i++)[s appendFormat:@"%02x",hash[i]];
    return s;
}
static NSDictionary *safeEvent(NSDictionary *input) {
    if(![input isKindOfClass:NSDictionary.class])return nil;
    NSString *kind=input[@"kind"],*uid=SNIdentifier(input[@"uid"]),*cid=SNIdentifier(input[@"conversation"]),*eid=SNMessageIdentifier(input[@"event"]);
    if(![@[@"snap",@"message"] containsObject:kind]||!uid||!cid||!eid)return nil;
    NSMutableDictionary *e=[@{@"kind":kind,@"uid":uid,@"conversation":cid,@"event":eid} mutableCopy];
    if(input[@"subtype"]&&[@[@"text",@"voice",@"photo",@"media",@"sticker",@"share",@"story_reply",@"location"] containsObject:input[@"subtype"]])e[@"subtype"]=input[@"subtype"];
    return [e copy];
}
@interface SNOutbox ()
@property(nonatomic,copy) NSString *directory;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMutableDictionary *> *records;
@property(nonatomic) uint64_t sequence;
@property(nonatomic) NSUInteger ioFailures,invalidFiles,capacityFailures,newRecords,duplicates;
@end
@implementation SNOutbox
- (NSString *)path:(NSString *)rid {return [self.directory stringByAppendingPathComponent:[rid stringByAppendingPathExtension:@"plist"]];}
- (BOOL)save:(NSDictionary *)record {
    NSError *error=nil;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    BOOL ok=data&&[data writeToFile:[self path:record[@"id"]] options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error];
    if(!ok)self.ioFailures++;
    return ok;
}
- (instancetype)initWithDirectory:(NSString *)directory {
    self=[super init];if(!self)return nil;
    _directory=[directory copy];_records=[NSMutableDictionary dictionary];
    NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error])self.ioFailures++;
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:&error];
    if(!files&&error)self.ioFailures++;
    /* Never follow arbitrary names/symlinks, nor load message contents from an
       untrusted file. An oversized directory is reported, not declared empty. */
    for(NSString *file in files) {
        if(![file hasPrefix:@"snapnotify.content."]||![file hasSuffix:@".plist"]||file.length!=89)continue;
        if(self.records.count>=20000){self.capacityFailures++;break;}
        NSString *p=[directory stringByAppendingPathComponent:file];NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:p error:NULL];
        if(![attrs[NSFileType] isEqual:NSFileTypeRegular]||[attrs[NSFileSize] unsignedLongLongValue]>8192){self.invalidFiles++;continue;}
        NSDictionary *r=[NSDictionary dictionaryWithContentsOfFile:p];NSDictionary *e=safeEvent(r[@"event"]);
        NSString *scope=r[@"scope"],*rid=r[@"id"],*state=r[@"state"];
        BOOL valid=e&&[scope isKindOfClass:NSString.class]&&scope.length&&scope.length<160&&[rid isKindOfClass:NSString.class]&&[rid isEqual:file.stringByDeletingPathExtension]&&[rid isEqual:identifierFor(e,scope)]&&[@[@"pending",@"accepted",@"blocked"] containsObject:state];
        for(NSString *key in @[@"order",@"attempt",@"retryAt",@"createdAt"]){id n=r[key];valid=valid&&[n isKindOfClass:NSNumber.class]&&isfinite([n doubleValue])&&[n doubleValue]>=0;}
        if([state isEqual:@"accepted"]){id n=r[@"acceptedAt"];valid=valid&&[n isKindOfClass:NSNumber.class]&&isfinite([n doubleValue]);}
        if(r[@"owner"])valid=valid&&SNIdentifier(r[@"owner"])!=nil;
        if(!valid){self.invalidFiles++;continue;}
        NSMutableDictionary *copy=[r mutableCopy];copy[@"event"]=e;
        self.records[rid]=copy;self.sequence=MAX(self.sequence,[r[@"order"] unsignedLongLongValue]);
    }
    return self;
}
- (void)pruneAtTime:(double)now {
    for(NSString *key in [self.records allKeys]){
        NSDictionary *r=self.records[key];
        if(![r[@"state"] isEqual:@"accepted"]||now-[r[@"acceptedAt"] doubleValue]<86400)continue;
        if([NSFileManager.defaultManager removeItemAtPath:[self path:key] error:NULL])[self.records removeObjectForKey:key];else self.ioFailures++;
    }
}
- (NSString *)enqueueEvent:(NSDictionary *)input scope:(NSString *)scope atTime:(double)now error:(NSError **)error {
    if(error)*error=nil;NSDictionary *e=safeEvent(input);
    if(!e||![scope isKindOfClass:NSString.class]||!scope.length||scope.length>=160||!isfinite(now)||now<0){if(error)*error=[NSError errorWithDomain:@"SnapNotifyOutbox" code:1 userInfo:nil];return nil;}
    NSString *rid=identifierFor(e,scope);NSMutableDictionary *old=self.records[rid];
    if(!old&&SNIdentifier(scope))for(NSMutableDictionary *record in self.records.allValues){
        NSDictionary *previous=record[@"event"];
        if([record[@"owner"] isEqual:scope]&&[previous[@"kind"] isEqual:e[@"kind"]]&&[previous[@"conversation"] isEqual:e[@"conversation"]]&&[previous[@"uid"] isEqual:e[@"uid"]]&&[previous[@"event"] isEqual:e[@"event"]]){old=record;rid=record[@"id"];break;}
    }
    if(old){
        self.duplicates++;
        /* Enrich a pending generic message without making a second event.
           A later reclassification of an accepted event never posts again. */
        if(![old[@"state"] isEqual:@"accepted"]&&[old[@"attempt"] unsignedIntegerValue]==0&&(!old[@"event"][@"subtype"]||[old[@"event"][@"subtype"] isEqual:@"text"])&&e[@"subtype"]){old[@"event"]=e;[self save:old];}
        return rid;
    }
    if(self.records.count>=20000)[self pruneAtTime:now];
    if(self.records.count>=20000){self.capacityFailures++;if(error)*error=[NSError errorWithDomain:@"SnapNotifyOutbox" code:2 userInfo:nil];return nil;}
    NSMutableDictionary *r=[@{@"id":rid,@"scope":scope,@"event":e,@"order":@(++self.sequence),@"createdAt":@(now),@"retryAt":@(now),@"attempt":@0,@"state":@"pending"} mutableCopy];
    id wait=input[@"nameWait"];double seconds=[wait isKindOfClass:NSNumber.class]?[wait doubleValue]:0;
    if(isfinite(seconds))r[@"retryAt"]=@(now+fmax(0,fmin(2,seconds)));
    self.records[rid]=r;self.newRecords++;
    /* An IO failure retains the event in RAM and permits delivery. The caller
       and status explicitly report that crash durability is degraded. */
    if(![self save:r]&&error)*error=[NSError errorWithDomain:@"SnapNotifyOutbox" code:3 userInfo:nil];
    return rid;
}
- (NSDictionary *)nextReadyInScopes:(NSSet *)scopes atTime:(double)now {
    if(!isfinite(now)||now<0)return nil;
    NSMutableDictionary *best=nil;uint64_t order=UINT64_MAX;
    for(NSMutableDictionary *r in self.records.allValues){
        if(![r[@"state"] isEqual:@"pending"]||!([scopes containsObject:r[@"scope"]]||(r[@"owner"]&&[scopes containsObject:r[@"owner"]]))||[r[@"retryAt"] doubleValue]>now)continue;
        if([r[@"order"] unsignedLongLongValue]<order){order=[r[@"order"] unsignedLongLongValue];best=r;}
    }
    if(!best)return nil;
    best[@"attempt"]=@([best[@"attempt"] unsignedIntegerValue]+1);best[@"retryAt"]=@(now+15);
    [self save:best];return [best copy];
}
- (BOOL)finishIdentifier:(NSString *)rid attempt:(NSUInteger)attempt success:(BOOL)success blocked:(BOOL)blocked atTime:(double)now {
    NSMutableDictionary *r=self.records[rid];
    if(!r||![r[@"state"] isEqual:@"pending"]||[r[@"attempt"] unsignedIntegerValue]!=attempt||!isfinite(now)||now<0)return NO;
    if(success){r[@"state"]=@"accepted";r[@"acceptedAt"]=@(now);}
    else if(blocked)r[@"state"]=@"blocked";
    else r[@"retryAt"]=@(now+fmin(60,pow(2,(double)MIN(attempt,(NSUInteger)6))));
    [self save:r];return YES;
}
- (void)retryBlockedInScopes:(NSSet *)scopes atTime:(double)now {
    if(!isfinite(now)||now<0)return;
    for(NSMutableDictionary *r in self.records.allValues)if([r[@"state"] isEqual:@"blocked"]&&([scopes containsObject:r[@"scope"]]||(r[@"owner"]&&[scopes containsObject:r[@"owner"]]))){r[@"state"]=@"pending";r[@"retryAt"]=@(now);[self save:r];}
    [self pruneAtTime:now];
}
- (void)bindSessionScope:(NSString *)scope toAccount:(NSString *)owner {
    if(![scope hasPrefix:@"session/"]||!SNIdentifier(owner))return;
    for(NSMutableDictionary *r in self.records.allValues)if([r[@"scope"] isEqual:scope]&&!r[@"owner"]){r[@"owner"]=owner;[self save:r];}
}
- (NSArray *)clear {
    NSArray *ids=[self.records.allKeys copy];
    for(NSString *rid in ids)if(![NSFileManager.defaultManager removeItemAtPath:[self path:rid] error:NULL])self.ioFailures++;
    [self.records removeAllObjects];return ids;
}
- (NSDictionary *)statisticsForScopes:(NSSet *)scopes {
    NSUInteger pending=0,accepted=0,blocked=0,held=0;
    for(NSDictionary *r in self.records.allValues){
        if([r[@"state"] isEqual:@"accepted"]){accepted++;continue;}
        if(!([scopes containsObject:r[@"scope"]]||(r[@"owner"]&&[scopes containsObject:r[@"owner"]])))held++;
        else if([r[@"state"] isEqual:@"blocked"])blocked++;
        else pending++;
    }
    return @{@"pending":@(pending),@"accepted":@(accepted),@"blocked":@(blocked),@"heldForAccount":@(held),@"ioFailures":@(self.ioFailures),@"invalidFiles":@(self.invalidFiles),@"capacityFailures":@(self.capacityFailures),@"newRecords":@(self.newRecords),@"duplicates":@(self.duplicates)};
}
@end
