#import <Foundation/Foundation.h>
#import "../Sources/SNEventBuffer.h"
#include <stdlib.h>
#define CHECK(...) do{if(!(__VA_ARGS__)){NSLog(@"FAILED buffer line %d",__LINE__);abort();}}while(0)
int main(void){@autoreleasepool{
    SNEventBuffer *queue=[[SNEventBuffer alloc] initWithCapacity:4096];
    /* Larger than both old 64-callback and 512-ledger limits. Each distinct
       notification survives, while duplicate callback paths collapse. */
    for(NSUInteger i=0;i<3000;i++){
        NSString *key=[NSString stringWithFormat:@"message-%lu",(unsigned long)i];
        CHECK([queue enqueue:@{@"id":@(i)} key:key]);
        CHECK([queue enqueue:@{@"id":@(i)} key:key]);
    }
    CHECK(queue.count==3000);
    for(NSUInteger i=0;i<3000;i++)CHECK([[queue takeFirst][@"id"] unsignedIntegerValue]==i);
    CHECK(queue.count==0);CHECK([queue takeFirst]==nil);
    CHECK([queue enqueue:@{@"id":@1} key:@"cancelled-call"]);
    [queue removeKey:@"cancelled-call"];CHECK([queue takeFirst]==nil);
    for(NSUInteger i=0;i<4096;i++)CHECK([queue enqueue:@{} key:[@(i) stringValue]]);
    CHECK(![queue enqueue:@{} key:@"overflow"]);
    [queue takeFirst];CHECK([queue enqueue:@{} key:@"overflow"]);
    [queue removeAll];CHECK(queue.count==0);CHECK([queue takeFirst]==nil);
    NSLog(@"PASS event buffer: 3000 distinct events, duplicates, cancellation, capacity and reset");
}return 0;}
