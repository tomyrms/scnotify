#import "SNDeliveryQueue.h"
#import "SNOutbox.h"
#include <math.h>
#include <time.h>

NSString * const SNDeliveryBlockedErrorDomain=@"SnapNotifyDeliveryBlocked";

void SNEnqueueObservedWork(dispatch_queue_t queue, dispatch_block_t work) {
    if(queue && work)dispatch_async(queue,work);
}
static double monotonic(void) {
    struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);
    return (double)t.tv_sec+(double)t.tv_nsec/1e9;
}
@interface SNDeliveryQueue ()
@property(nonatomic,strong) dispatch_queue_t lane;
@property(nonatomic,strong) SNOutbox *outbox;
@property(nonatomic,copy) NSSet<NSString *> *scopes;
@property(nonatomic,copy) SNContentSubmitter submitter;
@property(nonatomic,copy) SNDeliveryReporter reporter;
@property(nonatomic) BOOL enabled, busy, wakePending;
@property(nonatomic) NSTimeInterval spacing, nextSubmission, wakeDeadline;
@property(nonatomic) uint64_t wakeToken, generation, accepted, failures, timeouts;
@property(nonatomic,copy) NSString *activeID;
@property(nonatomic) NSUInteger activeAttempt;
@end
@implementation SNDeliveryQueue
- (instancetype)initWithDirectory:(NSString *)directory submitter:(SNContentSubmitter)submitter reporter:(SNDeliveryReporter)reporter {
    NSString *path=[directory copy];
    return [self initWithStorageFactory:^SNOutbox *{return [[SNOutbox alloc] initWithDirectory:path];}
                                submitter:submitter reporter:reporter];
}
- (instancetype)initWithStorageFactory:(SNOutbox *(^)(void))factory submitter:(SNContentSubmitter)submitter reporter:(SNDeliveryReporter)reporter {
    self=[super init];if(!self)return nil;
    _lane=dispatch_queue_create("ch.snapnotify.content-delivery",DISPATCH_QUEUE_SERIAL);
    _scopes=[NSSet set];_spacing=0.4;_generation=1;
    _submitter=[submitter copy];_reporter=[reporter copy];
    SNOutbox *(^loader)(void)=[factory copy];
    dispatch_async(_lane,^{
        @autoreleasepool {
            @try{self.outbox=loader?loader():nil;}
            @catch(NSException *e){[self report:@"storage-exception" details:@{@"exception":e.name}];}
            if(!self.outbox)self.outbox=[[SNOutbox alloc] initInMemory];
            [self report:@"ready" details:[self.outbox statisticsForScopes:self.scopes]];
            [self wakeAfter:0];
        }
    });
    return self;
}
- (void)report:(NSString *)stage details:(NSDictionary *)details {
    if(!self.reporter)return;
    @try{self.reporter(stage,details);}@catch(__unused NSException *e){}
}
- (void)configureScopes:(NSSet *)scopes session:(NSString *)sessionScope account:(NSString *)account enabled:(BOOL)enabled spacing:(NSTimeInterval)spacing {
    NSSet *copy=[scopes copy];NSString *transient=[sessionScope copy],*owner=[account copy];
    dispatch_async(self.lane,^{
        self.scopes=copy;self.enabled=enabled;
        self.spacing=isfinite(spacing)?fmax(0.01,fmin(2,spacing)):0.4;
        if(owner.length)[self.outbox bindSessionScope:transient toAccount:owner];
        [self wakeAfter:0];
    });
}
- (void)enqueueEvent:(NSDictionary *)event scope:(NSString *)scope {
    NSDictionary *copy=[event copy];NSString *owner=[scope copy];
    dispatch_async(self.lane,^{
        @try {
            NSError *error=nil;
            NSString *rid=[self.outbox enqueueEvent:copy scope:owner atTime:NSDate.date.timeIntervalSince1970 error:&error];
            if(error)[self report:@"storage" details:@{@"code":@(error.code),@"retained":@(rid!=nil)}];
            if(rid)[self wakeAfter:0];
        }@catch(NSException *e){[self report:@"enqueue-exception" details:@{@"exception":e.name}];}
    });
}
- (void)requestDrain {dispatch_async(self.lane,^{[self wakeAfter:0];});}
- (void)resumeBlocked {
    dispatch_async(self.lane,^{
        [self.outbox retryBlockedInScopes:self.scopes atTime:NSDate.date.timeIntervalSince1970];
        [self wakeAfter:0];
    });
}
- (void)clearWithCompletion:(void (^)(NSArray *))completion {
    dispatch_async(self.lane,^{
        self.generation++;self.wakeToken++;self.wakePending=NO;
        self.busy=NO;self.activeID=nil;self.nextSubmission=0;
        NSArray *ids=[self.outbox clear]?:@[];
        if(completion)completion(ids);
    });
}
- (void)statisticsWithCompletion:(void (^)(NSDictionary *))completion {
    dispatch_async(self.lane,^{
        NSMutableDictionary *s=[[self.outbox statisticsForScopes:self.scopes] mutableCopy]?:[NSMutableDictionary dictionary];
        s[@"acceptedThisRun"]=@(self.accepted);s[@"failedSubmissions"]=@(self.failures);
        s[@"completionTimeouts"]=@(self.timeouts);s[@"busy"]=@(self.busy);
        s[@"separateStorageLane"]=@YES;
        if(completion)completion([s copy]);
    });
}
/* An arrival can bring a wake FORWARD, never postpone an existing one.
   rc5 invalidated its old token on every arrival, allowing steady bursts to
   debounce delivery forever. All state here belongs to lane. */
- (void)wakeAfter:(double)delay {
    if(self.busy||!self.enabled)return;
    double now=monotonic(),due=fmax(now+fmax(0,delay),self.nextSubmission);
    if(self.wakePending && self.wakeDeadline<=due)return;
    self.wakePending=YES;self.wakeDeadline=due;
    uint64_t token=++self.wakeToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(fmax(0,due-now)*NSEC_PER_SEC)),self.lane,^{
        if(token!=self.wakeToken)return;
        self.wakePending=NO;
        [self drain];
    });
}
- (void)drain {
    if(self.busy||!self.enabled)return;
    NSDictionary *item=nil;
    @try{item=[self.outbox nextReadyInScopes:self.scopes atTime:NSDate.date.timeIntervalSince1970];}
    @catch(NSException *e){[self report:@"drain-exception" details:@{@"exception":e.name}];[self wakeAfter:1];return;}
    if(!item){
        if([[self.outbox statisticsForScopes:self.scopes][@"pending"] unsignedIntegerValue])[self wakeAfter:0.1];
        return;
    }
    NSString *rid=item[@"id"];NSDictionary *event=item[@"event"];
    NSUInteger attempt=[item[@"attempt"] unsignedIntegerValue];uint64_t generation=self.generation;
    self.busy=YES;self.activeID=rid;self.activeAttempt=attempt;
    void (^complete)(NSError *)=^(NSError *error){
        dispatch_async(self.lane,^{
            if(generation!=self.generation||![self.activeID isEqual:rid]||self.activeAttempt!=attempt)return;
            BOOL blocked=[error.domain isEqual:SNDeliveryBlockedErrorDomain];
            @try{[self.outbox finishIdentifier:rid attempt:attempt success:error==nil blocked:blocked atTime:NSDate.date.timeIntervalSince1970];}
            @catch(NSException *e){[self report:@"storage-exception" details:@{@"exception":e.name}];}
            self.busy=NO;self.activeID=nil;
            if(!error)self.accepted++;else self.failures++;
            [self report:error?@"failed":@"accepted" details:@{@"kind":event[@"kind"],@"subtype":event[@"subtype"]?:@"snap",@"code":@(error.code),@"blocked":@(blocked)}];
            self.nextSubmission=monotonic()+self.spacing;
            [self wakeAfter:0];
        });
    };
    @try{
        if(self.submitter){
            NSMutableDictionary *submission=[event mutableCopy];
            submission[@"deliveryScope"]=item[@"owner"]?:item[@"scope"];
            self.submitter([submission copy],rid,complete);
        }
        else complete([NSError errorWithDomain:SNDeliveryBlockedErrorDomain code:1 userInfo:nil]);
    }@catch(NSException *e){
        [self report:@"submit-exception" details:@{@"exception":e.name}];
        complete([NSError errorWithDomain:@"SnapNotifySubmit" code:1 userInfo:nil]);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),self.lane,^{
        if(generation!=self.generation||![self.activeID isEqual:rid]||self.activeAttempt!=attempt)return;
        self.timeouts++;[self report:@"timeout" details:@{@"attempt":@(attempt)}];
        complete([NSError errorWithDomain:@"SnapNotifySubmitTimeout" code:1 userInfo:nil]);
    });
}
@end
