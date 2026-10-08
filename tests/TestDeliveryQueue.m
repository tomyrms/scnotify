#import <Foundation/Foundation.h>
#import "../Sources/SNDeliveryQueue.h"
#import "../Sources/SNOutbox.h"
#import <objc/runtime.h>
#include <stdatomic.h>
#include <unistd.h>

static atomic_uint checks;
#define CHECK(x) do { atomic_fetch_add(&checks,1);if(!(x)){NSLog(@"FAILED delivery integration line %d: %s",__LINE__,#x);abort();} } while(0)
static NSString * const U=@"11111111-1111-4111-8111-111111111111";
static NSString * const C=@"22222222-2222-4222-8222-222222222222";
static NSString * const A=@"33333333-3333-4333-8333-333333333333";
static NSDictionary *event(unsigned i) {
    return @{@"kind":i%3==0?@"snap":@"message",@"uid":U,@"conversation":C,@"event":@(i+1),
             @"subtype":i%3==1?@"voice":@"text"};
}
static NSString *temp(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
}
static void waitFor(dispatch_semaphore_t s,double secs) {
    CHECK(dispatch_semaphore_wait(s,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(secs*NSEC_PER_SEC)))==0);
}
static NSDictionary *stats(SNDeliveryQueue *q) {
    __block NSDictionary *s=nil;dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [q statisticsWithCompletion:^(NSDictionary *value){s=value;dispatch_semaphore_signal(done);}];waitFor(done,5);return s;
}
static dispatch_semaphore_t storageEntered,storageRelease;
int main(void) {
    @autoreleasepool {
        /* Saturated receiver: the callback retains a host lock while worker
           needs it. A synchronous fallback would block the callback here. */
        dispatch_queue_t worker=dispatch_queue_create("test.immediate",DISPATCH_QUEUE_SERIAL);
        NSLock *hostLock=[NSLock new];[hostLock lock];
        dispatch_semaphore_t began=dispatch_semaphore_create(0),sourceReturned=dispatch_semaphore_create(0),drained=dispatch_semaphore_create(0);
        dispatch_async(worker,^{dispatch_semaphore_signal(began);[hostLock lock];[hostLock unlock];});
        waitFor(began,2);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            for(unsigned i=0;i<2000;i++)SNEnqueueObservedWork(worker,^{});
            SNEnqueueObservedWork(worker,^{dispatch_semaphore_signal(drained);});
            dispatch_semaphore_signal(sourceReturned);
        });
        waitFor(sourceReturned,2); /* Must return BEFORE releasing hostLock. */
        [hostLock unlock];waitFor(drained,5);

        storageEntered=dispatch_semaphore_create(0);storageRelease=dispatch_semaphore_create(0);
        __block unsigned sent=0;NSMutableSet *ids=[NSMutableSet set];
        dispatch_semaphore_t first=dispatch_semaphore_create(0);
        SNDeliveryQueue *q=[[SNDeliveryQueue alloc] initWithStorageFactory:^SNOutbox *{
            dispatch_semaphore_signal(storageEntered);
            dispatch_semaphore_wait(storageRelease,DISPATCH_TIME_FOREVER);
            return [[SNOutbox alloc] initWithDirectory:temp()];
        } submitter:^(NSDictionary *e,NSString *rid,void (^complete)(NSError *)){
            @synchronized(ids){[ids addObject:rid];sent++;}
            CHECK(e[@"deliveryScope"]!=nil);
            dispatch_semaphore_signal(first);complete(nil);
        } reporter:^(__unused NSString *s,__unused NSDictionary *d){}];
        waitFor(storageEntered,2);
        [q configureScopes:[NSSet setWithObject:A] session:@"session/test" account:A enabled:YES spacing:0.01];
        [q enqueueEvent:event(0) scope:A];
        dispatch_semaphore_t call=dispatch_semaphore_create(0),typing=dispatch_semaphore_create(0);
        SNEnqueueObservedWork(worker,^{dispatch_semaphore_signal(call);});
        SNEnqueueObservedWork(worker,^{dispatch_semaphore_signal(typing);});
        waitFor(call,2);waitFor(typing,2); /* Disk remains stalled. */
        @synchronized(ids){CHECK(sent==0);}
        dispatch_semaphore_signal(storageRelease);
        waitFor(first,5);

        /* Continuous arrivals must not keep replacing the pending drain
           deadline. Verify delivery progresses before the producer stops. */
        for(unsigned i=1;i<=120;i++){
            [q enqueueEvent:event(i) scope:A];usleep(5000);
        }
        @synchronized(ids){CHECK(sent>5);}
        for(unsigned n=0;n<500;n++){
            NSDictionary *s=stats(q);
            if([s[@"acceptedThisRun"] unsignedIntegerValue]==121)break;
            usleep(10000);
        }
        CHECK([stats(q)[@"acceptedThisRun"] unsignedIntegerValue]==121);
        @synchronized(ids){CHECK(ids.count==121);}
        [q enqueueEvent:event(10) scope:A];usleep(100000);
        CHECK([stats(q)[@"acceptedThisRun"] unsignedIntegerValue]==121); /* actual duplicate */
        CHECK([stats(q)[@"pending"] unsignedIntegerValue]==0);

        /* Synchronous exception from the system submitter must not leave busy
           set forever. Production code retries and then drains later content. */
        __block unsigned tries=0;
        SNDeliveryQueue *faulty=[[SNDeliveryQueue alloc] initWithDirectory:temp() submitter:^(__unused NSDictionary *e,__unused NSString *rid,void (^complete)(NSError *)){
            tries++;if(tries==1)@throw [NSException exceptionWithName:@"SimulatedUNFailure" reason:nil userInfo:nil];complete(nil);
        } reporter:^(__unused NSString *s,__unused NSDictionary *d){}];
        [faulty configureScopes:[NSSet setWithObject:A] session:@"session/test" account:A enabled:YES spacing:0.01];
        [faulty enqueueEvent:event(400) scope:A];[faulty enqueueEvent:event(401) scope:A];
        for(unsigned n=0;n<600;n++){if([stats(faulty)[@"acceptedThisRun"] unsignedIntegerValue]==2)break;usleep(10000);}
        CHECK([stats(faulty)[@"acceptedThisRun"] unsignedIntegerValue]==2);

        /* Scope transitions must not deliver another account's pending rows. */
        dispatch_semaphore_t cleared=dispatch_semaphore_create(0);
        [q clearWithCompletion:^(__unused NSArray *r){dispatch_semaphore_signal(cleared);}];waitFor(cleared,3);
        [q configureScopes:[NSSet setWithObject:@"session/new"] session:@"session/new" account:nil enabled:YES spacing:0.01];
        [q enqueueEvent:event(600) scope:A];usleep(100000);
        CHECK([stats(q)[@"heldForAccount"] unsignedIntegerValue]==1);

        /* A broken directory must degrade persistence, not all notifications. */
        NSString *notDirectory=temp();[@"not a directory" writeToFile:notDirectory atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        dispatch_semaphore_t recovered=dispatch_semaphore_create(0);
        SNDeliveryQueue *degraded=[[SNDeliveryQueue alloc] initWithDirectory:notDirectory submitter:^(__unused NSDictionary *e,__unused NSString *rid,void (^complete)(NSError *)){
            complete(nil);dispatch_semaphore_signal(recovered);
        } reporter:^(__unused NSString *s,__unused NSDictionary *d){}];
        [degraded configureScopes:[NSSet setWithObject:A] session:@"session/test" account:A enabled:YES spacing:0.01];
        [degraded enqueueEvent:event(700) scope:A];waitFor(recovered,5);
        CHECK([stats(degraded)[@"ioFailures"] unsignedIntegerValue]>0);

        /* In-memory fallback works and does not pretend to persist its rows. */
        SNOutbox *memory=[[SNOutbox alloc] initInMemory];NSError *error=nil;
        NSString *rid=[memory enqueueEvent:event(800) scope:A atTime:100 error:&error];
        CHECK(rid!=nil&&error!=nil);
        NSDictionary *ready=[memory nextReadyInScopes:[NSSet setWithObject:A] atTime:101];CHECK(ready!=nil);
        CHECK([memory finishIdentifier:rid attempt:[ready[@"attempt"] unsignedIntegerValue] success:YES blocked:NO atTime:102]);
        CHECK([memory clear].count==1);
        NSLog(@"Delivery integration: %u checks passed; blocked storage, host lock, continuous bursts, submit failure and scopes exercised",atomic_load(&checks));
    }
    return 0;
}
