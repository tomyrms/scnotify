#import "SNEventBuffer.h"
@implementation SNEventBuffer {
    NSMutableArray<NSString *> *_order;
    NSMutableDictionary<NSString *,NSDictionary *> *_events;
    NSUInteger _capacity;
}
- (instancetype)initWithCapacity:(NSUInteger)capacity {
    if((self=[super init])){_capacity=MAX((NSUInteger)1,capacity);_order=[NSMutableArray new];_events=[NSMutableDictionary new];}
    return self;
}
- (NSUInteger)count {return _events.count;}
- (BOOL)enqueue:(NSDictionary *)event key:(NSString *)key {
    if(_events[key])return YES;
    if(_events.count>=_capacity)return NO;
    _events[key]=[event copy];[_order addObject:[key copy]];return YES;
}
- (NSDictionary *)takeFirst {
    NSString *key=_order.firstObject;if(!key)return nil;
    NSDictionary *event=_events[key];[_events removeObjectForKey:key];[_order removeObjectAtIndex:0];return event;
}
- (void)removeKey:(NSString *)key {[_events removeObjectForKey:key];[_order removeObject:key];}
- (void)removeAll {[_events removeAllObjects];[_order removeAllObjects];}
@end
