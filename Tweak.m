// SnapNotify 4.0.0-rc1 — explicit event adapters, not notifications from hook names.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <AVFoundation/AVFoundation.h>
#import "Sources/SNRuntime.h"
#import "Core/SNCore.h"
#include <stdatomic.h>
#include <time.h>
#include <stdarg.h>
#include <math.h>

static NSString * const SNVersion=@"4.0.0-rc1";
static dispatch_queue_t worker, logQueue;
static NSMutableDictionary *users, *presence, *pendingEvents, *issuedRequests;
static NSDictionary *config;
static NSString *account, *session, *documents, *support;
static SNLedger ledger;
static atomic_int appState;
static atomic_uint inflight;
static atomic_bool experiments;
static NSUInteger hookCount, nameHits, nameMisses, wireCount, malformedCount, postedCount;
static atomic_ulong packetDrops;
static uint64_t queueGeneration;
static BOOL nativePushRegistered=NO, cacheDirty=NO;
static NSDateFormatter *logFormat;
static NSFileHandle *logHandle;
static NSString *logPath;
static double lastWire=0;
static NSTimer *housekeeping;
/* Main-thread-only experimental audio state. */
static AVAudioPlayer *keepPlayer;
static BOOL audioInterrupted=NO, deferringLifecycle=NO;
static dispatch_block_t deferredBackground;
static __weak id deferredReceiver;

static double nowTime(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
    return (double)t.tv_sec+(double)t.tv_nsec/1e9;
}
static NSString *stateLabel(void) {
    switch(atomic_load(&appState)){case UIApplicationStateActive:return @"FG";case UIApplicationStateBackground:return @"BG";default:return @"INACTIVE";}
}
static void logLine(NSString *format,...) NS_FORMAT_FUNCTION(1,2);
static void logLine(NSString *format,...) {
    va_list ap;va_start(ap,format);NSString *message=[[NSString alloc] initWithFormat:format arguments:ap];va_end(ap);
    NSString *state=stateLabel();NSDate *date=[NSDate date];
    dispatch_async(logQueue,^{
        @autoreleasepool {
            if(!logFormat){logFormat=[NSDateFormatter new];logFormat.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];logFormat.dateFormat=@"yyyy-MM-dd HH:mm:ss.SSS";}
            NSString *line=[NSString stringWithFormat:@"[%@] [%@] %@\n",[logFormat stringFromDate:date],state,message];
            NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
            @try {
                NSFileManager *fm=NSFileManager.defaultManager;
                if(!logPath)logPath=[documents stringByAppendingPathComponent:@"snapnotify.log"];
                if(!logHandle){
                    if(![fm fileExistsAtPath:logPath])[fm createFileAtPath:logPath contents:nil attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}];
                    logHandle=[NSFileHandle fileHandleForWritingAtPath:logPath];[logHandle seekToEndOfFile];
                }
                if(logHandle.offsetInFile+data.length>1024*1024){
                    [logHandle closeFile];logHandle=nil;
                    NSString *old=[logPath stringByAppendingString:@".1"];
                    [fm removeItemAtPath:old error:NULL];[fm moveItemAtPath:logPath toPath:old error:NULL];
                    [fm createFileAtPath:logPath contents:nil attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}];
                    logHandle=[NSFileHandle fileHandleForWritingAtPath:logPath];
                }
                [logHandle writeData:data];
            } @catch(NSException *e){logHandle=nil;NSLog(@"[SnapNotify] log IO failed: %@",e.name);}
        }
    });
}
static BOOL enabled(NSString *key) {return [config[key] boolValue];}
static double setting(NSString *key,double fallback,double min,double max) {
    id v=config[key];double x=[v isKindOfClass:NSNumber.class]?[v doubleValue]:fallback;
    return isfinite(x)?fmax(min,fmin(max,x)):fallback;
}
static NSString *shortID(NSString *uid) {
    if(!uid.length)return @"missing";
    return enabled(@"DiagnosticsIncludeIdentifiers")?uid:[uid substringToIndex:MIN((NSUInteger)8,uid.length)];
}
static void loadConfig(void) {
    NSMutableDictionary *defaults=[@{
        @"Enabled":@YES,@"TypingNotifications":@YES,@"SnapNotifications":@YES,
        @"MessageNotifications":@YES,@"CallNotifications":@YES,@"PeekingNotifications":@YES,
        @"NotifyInForeground":@NO,@"ExperimentalKeepAlive":@YES,
        @"DiagnosticsIncludeIdentifiers":@NO,@"TypingIdleSeconds":@8.0,
        @"TypingRestartGapSeconds":@1.5,@"NameWaitSeconds":@0.8,
        @"Aliases":@{},@"SelfUserID":@"",@"TypingInactiveStates":@[]
    } mutableCopy];
    NSString *p=[documents stringByAppendingPathComponent:@"SnapNotifyConfig.plist"];
    NSDictionary *file=[NSDictionary dictionaryWithContentsOfFile:p];
    if(file){
        for(NSString *key in [defaults allKeys]) {
            id a=defaults[key],b=file[key];
            BOOL ok=([a isKindOfClass:NSNumber.class]&&[b isKindOfClass:NSNumber.class])||([a isKindOfClass:NSString.class]&&[b isKindOfClass:NSString.class])||([a isKindOfClass:NSDictionary.class]&&[b isKindOfClass:NSDictionary.class])||([a isKindOfClass:NSArray.class]&&[b isKindOfClass:NSArray.class]);
            if(ok)defaults[key]=b;
        }
    }else [defaults writeToFile:p atomically:YES];
    NSMutableDictionary *aliases=[NSMutableDictionary dictionary];
    for(id key in defaults[@"Aliases"]){if(aliases.count>=2048)break;NSString *uid=SNIdentifier(key),*name=SNName(defaults[@"Aliases"][key]);if(uid&&name)aliases[uid]=name;}
    defaults[@"Aliases"]=[aliases copy];
    if([defaults[@"TypingInactiveStates"] count]>256)defaults[@"TypingInactiveStates"]=@[];
    config=[defaults copy];atomic_store(&experiments,enabled(@"Enabled")&&enabled(@"ExperimentalKeepAlive"));
}
static NSString *cachePath(void) {return [support stringByAppendingPathComponent:@"identities-v4.plist"];}
static void saveCache(void) {
    if(!cacheDirty||!account.length)return;cacheDirty=NO;
    NSError *error=nil;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@4,@"account":account,@"users":users} format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if(!data||![data writeToFile:cachePath() options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error]){cacheDirty=YES;logLine(@"CACHE-WRITE-FAILED code=%ld",(long)error.code);}
}
static void setAccount(NSString *uid) {
    if(!uid.length||[account isEqualToString:uid])return;
    BOOL switching=account.length>0;
    saveCache();account=[uid copy];
    if(switching){
        queueGeneration++;
        NSArray *owned=issuedRequests.allKeys;
        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:owned];
        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:owned];
        [issuedRequests removeAllObjects];[users removeAllObjects];[presence removeAllObjects];[pendingEvents removeAllObjects];memset(&ledger,0,sizeof(ledger));
    }
    /* Learning our own ID for the first time must not cancel the incoming
       call whose state callback supplied it. Only a real account switch resets. */
    NSDictionary *saved=[NSDictionary dictionaryWithContentsOfFile:cachePath()];
    if([saved[@"version"] isEqual:@4]&&[saved[@"account"] isEqual:account]&&[saved[@"users"] isKindOfClass:NSDictionary.class]) {
        for(id key in saved[@"users"]){
            if(users.count>=2048)break;NSString *user=SNIdentifier(key);id value=saved[@"users"][key];
            if(user&&!users[user]&&[value isKindOfClass:NSDictionary.class]&&SNName(value[@"name"]))users[user]=@{@"name":SNName(value[@"name"]),@"quality":@1};
        }
    }
    cacheDirty=users.count>0;logLine(@"ACCOUNT-CHANGED account=%@ cache=%lu",shortID(uid),(unsigned long)users.count);
}
static void remember(NSArray<NSDictionary *> *records) {
    for(NSDictionary *u in records) {
        NSString *uid=SNIdentifier(u[@"uid"]),*name=SNName(u[@"name"]);if(!uid||!name)continue;
        NSInteger quality=[u[@"quality"] integerValue];NSDictionary *old=users[uid];
        if(old&&[old[@"quality"] integerValue]>quality)continue;
        if([old[@"name"] isEqual:name])continue;
        if(users.count>=2048&&!old)[users removeObjectForKey:users.allKeys.firstObject];
        users[uid]=@{@"name":name,@"quality":@(quality)};cacheDirty=YES;
        /* Do not publish contact names in diagnostics. */
        logLine(@"IDENTITY-LEARNED uid=%@ quality=%ld",shortID(uid),(long)quality);
    }
}
static NSString *resolveName(NSString *uid) {
    NSDictionary *aliases=config[@"Aliases"];NSString *name=SNName(aliases[uid])?:SNName(users[uid][@"name"]);
    if(name)nameHits++;else nameMisses++;return name;
}
static BOOL eventEnabled(NSString *kind) {
    NSDictionary *keys=@{@"typing":@"TypingNotifications",@"peek":@"PeekingNotifications",@"snap":@"SnapNotifications",@"message":@"MessageNotifications",@"call":@"CallNotifications"};
    return enabled(@"Enabled")&&keys[kind]&&enabled(keys[kind]);
}
static NSString *eventKey(NSDictionary *event) {
    return [@[event[@"kind"],event[@"conversation"],event[@"uid"],event[@"event"]] componentsJoinedByString:@"|"];
}
static NSString *bodyFor(NSDictionary *event,NSString *name) {
    NSString *who=name ?: [NSString stringWithFormat:@"Contact %@",shortID(event[@"uid"])];
    NSString *kind=event[@"kind"];
    if([kind isEqual:@"typing"])return [who stringByAppendingString:@" est en train d’écrire…"];
    if([kind isEqual:@"peek"])return [who stringByAppendingString:@" entrouvre la conversation"];
    if([kind isEqual:@"snap"])return [who stringByAppendingString:@" t’a envoyé un snap"];
    if([kind isEqual:@"message"])return [who stringByAppendingString:@" t’a envoyé un message"];
    return [who stringByAppendingString:[event[@"video"] boolValue]?@" t’appelle en vidéo":@" t’appelle"];
}
static BOOL isForegroundSuppressed(void) {return atomic_load(&appState)==UIApplicationStateActive&&!enabled(@"NotifyInForeground");}
static void deliver(NSDictionary *event,uint64_t ticket,uint64_t generation,unsigned attempt) {
    if(generation!=queueGeneration)return;
    NSString *key=eventKey(event);
    /* STOP / account changes can cancel the pending name wait. */
    if(![pendingEvents[key][@"ticket"] isEqual:@(ticket)])return;
    if(!eventEnabled(event[@"kind"])||isForegroundSuppressed()) {
        sn_ledger_commit(&ledger,ticket,nowTime(),60);[pendingEvents removeObjectForKey:key];return;
    }
    NSString *name=resolveName(event[@"uid"]);
    UNMutableNotificationContent *content=[UNMutableNotificationContent new];
    content.title=@"Snapchat";content.body=bodyFor(event,name);content.sound=UNNotificationSound.defaultSound;
    content.threadIdentifier=[@"snapnotify." stringByAppendingString:event[@"conversation"]];
    content.userInfo=@{@"scnotify":@YES,@"version":SNVersion,@"kind":event[@"kind"]};
    if(@available(iOS 15.0,*)){if([event[@"kind"] isEqual:@"call"])content.interruptionLevel=UNNotificationInterruptionLevelTimeSensitive;}
    NSString *requestID=[NSString stringWithFormat:@"snapnotify.%@.%llu",session,(unsigned long long)ticket];
    UNNotificationRequest *request=[UNNotificationRequest requestWithIdentifier:requestID content:content trigger:nil];
    issuedRequests[requestID]=@(nowTime());
    logLine(@"NOTIF-REQUEST type=%@ uid=%@ name=%@ attempt=%u",event[@"kind"],shortID(event[@"uid"]),name?@"resolved":@"unresolved",attempt);
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(worker,^{
            if(generation!=queueGeneration){
                [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[requestID]];
                [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[requestID]];
                return;
            }
            if(![pendingEvents[key][@"ticket"] isEqual:@(ticket)])return;
            if(error){
                logLine(@"NOTIF-FAILED type=%@ domain=%@ code=%ld",event[@"kind"],error.domain,(long)error.code);
                /* One bounded retry, same identifier. Do not lock out a failed
                   notification or busy-loop when permission is denied. */
                if(attempt==0 && !( [error.domain isEqualToString:UNErrorDomain] && error.code==UNErrorCodeNotificationsNotAllowed)){
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),worker,^{deliver(event,ticket,generation,1);});
                }else{
                    sn_ledger_cancel(&ledger,ticket);[pendingEvents removeObjectForKey:key];
                    NSString *pk=[@[event[@"kind"],event[@"conversation"],event[@"uid"]] componentsJoinedByString:@"|"];
                    SNPresence *ps=[presence[pk] mutableBytes];
                    if(ps && [[NSString stringWithFormat:@"session-%llu",(unsigned long long)ps->session] isEqual:event[@"event"]]){ps->active=false;ps->notified=false;}
                }
            }else{
                double ttl=[event[@"kind"] isEqual:@"call"]?300:([event[@"kind"] isEqual:@"typing"]||[event[@"kind"] isEqual:@"peek"])?60:86400;
                sn_ledger_commit(&ledger,ticket,nowTime(),ttl);[pendingEvents removeObjectForKey:key];postedCount++;
                logLine(@"NOTIF-ACCEPTED type=%@ ticket=%llu",event[@"kind"],(unsigned long long)ticket);
            }
        });
    }];
}
static void notifyEvent(NSDictionary *event) {
    NSString *uid=event[@"uid"],*kind=event[@"kind"];
    if(!SNIdentifier(uid)||!SNIdentifier(event[@"conversation"])||!event[@"event"]||!kind)return;
    if(account.length&&[uid isEqual:account]){logLine(@"EVENT-DROP reason=self type=%@",kind);return;}
    if(!eventEnabled(kind))return;
    NSString *key=eventKey(event);double now=nowTime();
    uint64_t ticket=sn_ledger_reserve(&ledger,key.UTF8String,now,15);
    if(!ticket){logLine(@"EVENT-DROP reason=duplicate type=%@ uid=%@",kind,shortID(uid));return;}
    if(isForegroundSuppressed()) {
        sn_ledger_commit(&ledger,ticket,now,([kind isEqual:@"call"]?300:60));
        logLine(@"EVENT-OBSERVED type=%@ foreground=1",kind);return;
    }
    pendingEvents[key]=@{@"ticket":@(ticket),@"event":event,@"created":@(now)};
    double wait=SNName(config[@"Aliases"][uid])||SNName(users[uid][@"name"])?0:setting(@"NameWaitSeconds",0.8,0,2);
    uint64_t generation=queueGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(wait*NSEC_PER_SEC)),worker,^{deliver(event,ticket,generation,0);});
}
static void cancelCall(SNCall call) {
    NSDictionary *e=@{@"kind":@"call",@"uid":@(call.sender),@"conversation":@(call.conversation),@"event":@(call.call)};
    NSString *key=eventKey(e);NSDictionary *pending=pendingEvents[key];
    if(pending){sn_ledger_cancel(&ledger,[pending[@"ticket"] unsignedLongLongValue]);[pendingEvents removeObjectForKey:key];}
    sn_ledger_mark(&ledger,key.UTF8String,nowTime(),300);
    logLine(@"CALL-STOP uid=%@",shortID(@(call.sender)));
}
static void consumePacket(NSData *packet) {
    lastWire=nowTime();wireCount++;
    SNRecord records[SN_RECORD_MAX];size_t count=0;
    if(!sn_decode_records((SNBytes){packet.bytes,packet.length},records,&count)) {
        malformedCount++;logLine(@"WIRE-UNSUPPORTED bytes=%lu",(unsigned long)packet.length);return;
    }
    for(size_t i=0;i<count;i++) {
        SNRecord r=records[i];
        if(!strcmp(r.topic,"volatile")) {
            SNCall call;
            if(sn_decode_call(r.payload,&call)) {
                if(call.action==SN_CALL_STOP){cancelCall(call);continue;}
                if(call.skip_ringing){logLine(@"CALL-SILENT uid=%@",shortID(@(call.sender)));continue;}
                notifyEvent(@{@"kind":@"call",@"uid":@(call.sender),@"conversation":@(call.conversation),@"event":@(call.call),@"video":@(call.video)});
            }else logLine(@"WIRE-IGNORED topic=volatile reason=not-a-validated-call bytes=%lu",(unsigned long)r.payload.size);
        } else if(!strcmp(r.topic,"presence")) {
            /* The typed presence callback is the semantic source. Raw presence
               bytes in the supplied logs are truncated, so no guessed schema. */
            logLine(@"WIRE topic=presence bytes=%lu",(unsigned long)r.payload.size);
        } else {
            logLine(@"WIRE-UNSUPPORTED topic=%s bytes=%lu",r.topic,(unsigned long)r.payload.size);
            /* sync_trigger is not a snap. No fallback 'activity' notifications. */
        }
    }
}
static void enqueuePacket(NSData *data) {
    if(![data isKindOfClass:NSData.class]||!data.length||data.length>SN_PACKET_MAX)return;
    if(atomic_fetch_add(&inflight,1)>=64){atomic_fetch_sub(&inflight,1);atomic_fetch_add(&packetDrops,1);return;}
    NSData *copy=[data copy];
    dispatch_async(worker,^{
        @try {@autoreleasepool{consumePacket(copy);}}
        @catch(NSException *error){logLine(@"WIRE-ERROR exception=%@",error.name);}
        @finally{atomic_fetch_sub(&inflight,1);}
    });
}
static void cancelPresenceWait(NSString *kind,NSString *cid,NSString *uid,SNPresence *state) {
    NSString *key=[@[kind,cid,uid,[NSString stringWithFormat:@"session-%llu",(unsigned long long)state->session]] componentsJoinedByString:@"|"];
    NSDictionary *entry=pendingEvents[key];
    if(entry){
        uint64_t ticket=[entry[@"ticket"] unsignedLongLongValue];
        sn_ledger_cancel(&ledger,ticket);[pendingEvents removeObjectForKey:key];
        NSString *rid=[NSString stringWithFormat:@"snapnotify.%@.%llu",session,(unsigned long long)ticket];
        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[rid]];
        state->notified=false;
        logLine(@"PRESENCE-CANCELLED-WAIT type=%@ uid=%@",kind,shortID(uid));
    }
}
static void consumePresence(NSArray<NSDictionary *> *snapshots) {
    if(!snapshots){logLine(@"PRESENCE-UNSUPPORTED preserved_previous_state=1");return;}
    double now=nowTime();NSMutableSet *seen=[NSMutableSet set],*unknownPeek=[NSMutableSet set];
    for(NSDictionary *convo in snapshots) {
        NSString *cid=convo[@"conversation"];
        if(![convo[@"peekingKnown"] boolValue])[unknownPeek addObject:cid];
        for(NSString *kind in @[@"typing",@"peek"]) {
            for(NSDictionary *person in convo[[kind isEqual:@"typing"]?@"typing":@"peeking"]) {
                NSString *uid=person[@"uid"],*key=[@[kind,cid,uid] componentsJoinedByString:@"|"];
                [seen addObject:key];
                BOOL active=person[@"active"]?[person[@"active"] boolValue]:YES;
                /* RemoteTypingParticipants membership is used when the proxy
                   offers no boolean. Numeric enum meanings are NOT invented. */
                if([kind isEqual:@"typing"]&&[config[@"TypingInactiveStates"] containsObject:person[@"rawState"]])active=NO;
                NSMutableData *data=presence[key];if(!data){data=[NSMutableData dataWithLength:sizeof(SNPresence)];presence[key]=data;}
                SNPresence *state=data.mutableBytes;
                SNPresenceChange change=sn_presence_update(state,active,now,setting(@"TypingIdleSeconds",8,2,60),setting(@"TypingRestartGapSeconds",1.5,0,10));
                logLine(@"PRESENCE type=%@ uid=%@ raw=%@ active=%d change=%d fallback=%@",kind,shortID(uid),person[@"rawState"],active,change,convo[@"fallback"]);
                if(change==SN_PRESENCE_STOP)cancelPresenceWait(kind,cid,uid,state);
                if(change==SN_PRESENCE_START)notifyEvent(@{@"kind":kind,@"uid":uid,@"conversation":cid,@"event":[NSString stringWithFormat:@"session-%llu",(unsigned long long)state->session]});
            }
        }
    }
    for(NSString *key in [presence allKeys]) {
        NSArray *parts=[key componentsSeparatedByString:@"|"];SNPresence *state=[presence[key] mutableBytes];
        if(![seen containsObject:key] && !([parts[0] isEqual:@"peek"]&&[unknownPeek containsObject:parts[1]])) {
            if(state->active){cancelPresenceWait(parts[0],parts[1],parts[2],state);sn_presence_update(state,NO,now,8,0);logLine(@"PRESENCE-STOP type=%@ uid=%@",parts[0],shortID(parts[2]));}
        }
        if(presence.count>512 || (state->observed&&!state->active&&now-state->last_activity>300))[presence removeObjectForKey:key];
    }
}
static void consumeReceived(NSArray *events) {
    for(NSDictionary *e in events) {
        NSNumber *ts=e[@"timestamp"];
        if(ts){double t=ts.doubleValue;if(t>1e12)t/=1000;
            double age=NSDate.date.timeIntervalSince1970-t;
            if(!isfinite(t)||age>300||age< -60){logLine(@"EVENT-DROP reason=historical-or-invalid-time type=%@",e[@"kind"]);continue;}}
        if(e[@"name"])remember(@[@{@"uid":e[@"uid"],@"name":e[@"name"],@"quality":@2}]);
        notifyEvent(e);
    }
}

#pragma mark - Optional background experiment (main thread only)
static void stopExperiment(NSString *reason) {
    [keepPlayer stop];keepPlayer=nil;
    /* Never deactivate or reset Snapchat's shared audio session. */
    if(deferringLifecycle){dispatch_block_t callback=deferredBackground;deferredBackground=nil;deferringLifecycle=NO;if(callback)callback();}
    deferredReceiver=nil;logLine(@"KEEPALIVE-STOP reason=%@",reason);
}
static BOOL startExperiment(void) {
    if(!atomic_load(&experiments)||audioInterrupted||atomic_load(&appState)!=UIApplicationStateBackground)return NO;
    NSArray *modes=NSBundle.mainBundle.infoDictionary[@"UIBackgroundModes"];
    if(![modes isKindOfClass:NSArray.class]||![modes containsObject:@"audio"]){logLine(@"KEEPALIVE-UNAVAILABLE reason=no-audio-background-mode");return NO;}
    AVAudioSession *audio=AVAudioSession.sharedInstance;
    if([audio.category isEqual:AVAudioSessionCategoryRecord]||[audio.category isEqual:AVAudioSessionCategoryPlayAndRecord]){logLine(@"KEEPALIVE-UNAVAILABLE reason=host-recording-or-call");return NO;}
    NSError *e=nil;
    if(![audio setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&e]||![audio setActive:YES error:&e]){logLine(@"KEEPALIVE-UNAVAILABLE reason=audio-session code=%ld",(long)e.code);return NO;}
    if(!keepPlayer){
        /* One second, mono PCM16 @ 8 kHz. A genuinely silent buffer, not
           per-sample allocation. This is not an APNs replacement. */
        uint8_t h[44]={'R','I','F','F',0xa4,0x3e,0,0,'W','A','V','E','f','m','t',' ',16,0,0,0,1,0,1,0,0x40,0x1f,0,0,0x80,0x3e,0,0,2,0,16,0,'d','a','t','a',0x80,0x3e,0,0};
        NSMutableData *wav=[NSMutableData dataWithBytes:h length:44];[wav increaseLengthBy:16000];
        keepPlayer=[[AVAudioPlayer alloc] initWithData:wav error:&e];keepPlayer.numberOfLoops=-1;keepPlayer.volume=0;
    }
    BOOL ok=keepPlayer.isPlaying||[keepPlayer play];logLine(@"KEEPALIVE-EXPERIMENT playing=%d guaranteed=0",ok);return ok;
}
static void installBackgroundExperiment(Class cls) {
    /* Exact observed lifecycle method, not UIApplication state spoofing and
       not begin/endBackgroundTask tampering. Enabled only by the local config. */
    SEL sel=NSSelectorFromString(@"_onAppDidEnterBackground");Method m=class_getInstanceMethod(cls,sel);
    static BOOL installed=NO;if(installed||!m)return;
    unsigned n=method_getNumberOfArguments(m);char *type=method_copyReturnType(m);BOOL valid=n==2&&type&&!strcmp(type,"v");free(type);if(!valid)return;
    IMP original=method_getImplementation(m);
    IMP replacement=imp_implementationWithBlock(^(id self){
        if(NSThread.isMainThread)atomic_store(&appState,UIApplication.sharedApplication.applicationState);
        if(NSThread.isMainThread && atomic_load(&experiments) && startExperiment()) {
            if(deferringLifecycle && deferredReceiver!=self){((void(*)(id,SEL))original)(self,sel);return;}
            __weak id weakSelf=self;deferredReceiver=self;deferringLifecycle=YES;
            deferredBackground=^{id target=weakSelf;if(target)((void(*)(id,SEL))original)(target,sel);};
            logLine(@"DUPLEX-BACKGROUND-DEFERRED experimental=1");return;
        }
        ((void(*)(id,SEL))original)(self,sel);logLine(@"DUPLEX-BACKGROUND host-callback=forwarded");
    });
    method_setImplementation(m,replacement);installed=YES;hookCount++;
}

#pragma mark - Narrow, signature-checked hooks
static void installForegroundPresentation(Class cls) {
    SEL sel=NSSelectorFromString(@"userNotificationCenter:willPresentNotification:withCompletionHandler:");
    unsigned count=0;Method *ms=class_copyMethodList(cls,&count);Method m=NULL;
    for(unsigned i=0;i<count;i++)if(method_getName(ms[i])==sel){m=ms[i];break;}free(ms);if(!m)return;
    static NSMutableSet *done;static dispatch_once_t once;dispatch_once(&once,^{done=[NSMutableSet set];});
    NSString *key=NSStringFromClass(cls);if([done containsObject:key])return;
    if(method_getNumberOfArguments(m)!=5)return;
    char *r=method_copyReturnType(m);BOOL valid=r&&!strcmp(r,"v");free(r);
    for(unsigned i=2;i<5;i++){char *a=method_copyArgumentType(m,i);valid &= a&&a[0]=='@';free(a);}if(!valid)return;
    IMP original=method_getImplementation(m);
    IMP replacement=imp_implementationWithBlock(^(id self,UNUserNotificationCenter *center,UNNotification *notification,void (^completion)(UNNotificationPresentationOptions)){
        if([notification.request.content.userInfo[@"scnotify"] boolValue]) {
            if(completion)completion(UNNotificationPresentationOptionBanner|UNNotificationPresentationOptionList|UNNotificationPresentationOptionSound);
        }else ((void(*)(id,SEL,id,id,id))original)(self,sel,center,notification,completion);
    });
    method_setImplementation(m,replacement);[done addObject:key];hookCount++;
}
static void attach(Class cls,NSString *name,SNHookObserver observer) {
    if(SNInstallHook(cls,NSSelectorFromString(name),observer)){hookCount++;logLine(@"HOOK class=%@ selector=%@",NSStringFromClass(cls),name);}
}
static void scan(void) {
    /* Main-thread installation; each closure captures its own original IMP.
       objc_copyClassList supplies a consistent, correctly sized allocation. */
    unsigned count=0;Class *classes=objc_copyClassList(&count);if(!classes)return;
    static unsigned lastClassCount=0;
    if(count==lastClassCount){free(classes);return;}lastClassCount=count;
    NSUInteger old=hookCount;
    NSSet *resolverNames=[NSSet setWithArray:@[@"snapchatterForUserId:",@"_snapchatterForUserId:",@"displayNameForUserId:",@"_displayNameForUserId:",@"usernameForUserId:",@"userForUserId:"]];
    NSDictionary *receiveHints=@{@"didReceiveSnap:":@"snap",@"didReceiveChatMessage:":@"message",@"didReceiveMessage:":@"",@"didReceiveMessages:":@"",@"onMessageReceived:":@"",@"onMessagesReceived:":@"",@"conversation:didReceiveMessage:":@""};
    NSSet *identityFields=[NSSet setWithArray:@[@"userId",@"userID",@"username",@"displayName",@"setUserId:",@"setUsername:",@"setDisplayName:"]];
    for(unsigned i=0;i<count;i++) {
        Class cls=classes[i];NSString *cn=NSStringFromClass(cls);
        BOOL snap=[cn hasPrefix:@"SC"]||[cn hasPrefix:@"SOJU"];
        if(!snap)continue;
        if([@[@"SCCDuplexMessageHandler",@"SCNDuplexMessageHandlerCppProxy"] containsObject:cn])attach(cls,@"onReceive:",^(id self,NSArray *a,id r){(void)self;(void)r;enqueuePacket(a.firstObject);});
        if([cn isEqual:@"SCCallStateProvider"]){
            attach(cls,@"updateWithPresencePlatformActiveConversationsInfo:",^(id self,NSArray *a,id r){(void)self;(void)r;NSArray *snapshot=SNPresenceRecords(a.firstObject);dispatch_async(worker,^{consumePresence(snapshot);});});
            attach(cls,@"sessionWrapper:updatedState:",^(id self,NSArray *a,id r){
                (void)self;(void)r;id state=SNRead(a.count>1?a[1]:nil,@"state");id local=SNRead(state,@"localParticipant");NSString *uid=SNIdentifier(SNRead(local,@"snapchatUserId"));
                if(uid)dispatch_async(worker,^{setAccount(uid);});
                /* Do not classify a state-provider callback as an incoming call. */
                dispatch_async(dispatch_get_main_queue(),^{if(keepPlayer)stopExperiment(@"host-call-state");});
            });
        }
        if([cn isEqual:@"SCDuplexAppUserLifecycleObserver"])installBackgroundExperiment(cls);
        if([cn isEqual:@"SCNDuplexBackgroundNetworkTaskDelegateImpl"]){
            attach(cls,@"beginBackgroundTask",^(id self,NSArray *a,id r){(void)self;(void)a;(void)r;logLine(@"DUPLEX-TASK begin");});
            attach(cls,@"endBackgroundTask",^(id self,NSArray *a,id r){(void)self;(void)a;(void)r;logLine(@"DUPLEX-TASK end (not proof of OS suspension)");});
        }
        if([@[@"SCAppDelegate",@"SCMainAppDelegate",@"SCPushNotificationDelegate"] containsObject:cn]){
            installForegroundPresentation(cls);
            attach(cls,@"application:didFailToRegisterForRemoteNotificationsWithError:",^(id self,NSArray *a,id r){(void)self;(void)r;NSError *e=a.count>1&&[a[1] isKindOfClass:NSError.class]?a[1]:nil;logLine(@"APNS-FAILED domain=%@ code=%ld",e.domain,(long)e.code);dispatch_async(worker,^{nativePushRegistered=NO;});});
            attach(cls,@"application:didRegisterForRemoteNotificationsWithDeviceToken:",^(id self,NSArray *a,id r){(void)self;(void)a;(void)r;logLine(@"APNS-REGISTERED token-redacted=1");dispatch_async(worker,^{nativePushRegistered=YES;});});
        }
        if([cn isEqual:@"SCUserInfoDeltaSyncRepository"])attach(cls,@"_processNewUserInfo:",^(id self,NSArray *a,id r){(void)self;(void)r;NSArray *records=SNUserRecords(a.firstObject);dispatch_async(worker,^{remember(records);});});
        BOOL userModel=[cn hasPrefix:@"SCSnapchatter"]||[cn isEqual:@"SCFriendsFeedItem"];
        unsigned mc=0;Method *methods=class_copyMethodList(cls,&mc);
        for(unsigned m=0;m<mc;m++) {
            NSString *name=NSStringFromSelector(method_getName(methods[m]));
            if([resolverNames containsObject:name])attach(cls,name,^(id self,NSArray *args,id result){
                (void)self;NSString *uid=SNIdentifier(args.firstObject);NSDictionary *u=SNUserRecord(result,uid);
                if(u&&[name.lowercaseString containsString:@"username"]){NSMutableDictionary *r=[u mutableCopy];r[@"quality"]=@1;u=[r copy];}
                if(u){NSDictionary *copy=u;dispatch_async(worker,^{remember(@[copy]);});}
            });
            if(userModel&&[identityFields containsObject:name])attach(cls,name,^(id self,NSArray *args,id result){(void)args;(void)result;NSDictionary *u=SNUserRecord(self,nil);if(u)dispatch_async(worker,^{remember(@[u]);});});
            if([@[@"currentUserId",@"loggedInUserId"] containsObject:name])attach(cls,name,^(id self,NSArray *args,id result){(void)self;(void)args;NSString *uid=SNIdentifier(result);if(uid)dispatch_async(worker,^{setAccount(uid);});});
            NSString *hint=receiveHints[name];
            if(hint)attach(cls,name,^(id self,NSArray *args,id result){
                (void)self;(void)result;NSMutableArray *events=[NSMutableArray array],*records=[NSMutableArray array];
                for(id obj in args){[events addObjectsFromArray:SNReceivedRecords(obj,hint.length?hint:nil)];[records addObjectsFromArray:SNUserRecords(obj)];}
                NSArray *copy=[events copy],*names=[records copy];
                dispatch_async(worker,^{remember(names);if(!copy.count)logLine(@"RECEIVE-UNSUPPORTED class=%@ selector=%@",cn,name);consumeReceived(copy);});
            });
        }
        free(methods);
    }
    free(classes);logLine(@"SCAN hooks=%lu added=%lu",(unsigned long)hookCount,(unsigned long)(hookCount-old));
}
static void writeStatus(void) {
    double now=nowTime();
    for(NSString *rid in [issuedRequests allKeys])if(now-[issuedRequests[rid] doubleValue]>86400)[issuedRequests removeObjectForKey:rid];
    while(issuedRequests.count>2048){
        NSString *oldest=[[issuedRequests keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a,NSNumber *b){return [a compare:b];}] firstObject];
        [issuedRequests removeObjectForKey:oldest];
    }
    for(NSString *key in [pendingEvents allKeys])if(now-[pendingEvents[key][@"created"] doubleValue]>15){sn_ledger_cancel(&ledger,[pendingEvents[key][@"ticket"] unsignedLongLongValue]);[pendingEvents removeObjectForKey:key];}
    NSDictionary *status=@{@"version":SNVersion,@"state":stateLabel(),@"knownUsers":@(users.count),@"nameHits":@(nameHits),@"nameMisses":@(nameMisses),@"wirePackets":@(wireCount),@"unsupportedWirePackets":@(malformedCount),@"packetDrops":@(atomic_load(&packetDrops)),@"notificationRequestsAccepted":@(postedCount),@"secondsSinceWire":lastWire?@(now-lastWire):@(-1),@"apnsRegisteredThisRun":@(nativePushRegistered),@"experimentalKeepAlive":@(atomic_load(&experiments)),@"onDeviceValidationRequired":@YES};
    NSData *json=[NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:NULL];
    [json writeToFile:[documents stringByAppendingPathComponent:@"snapnotify_status.json"] options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:NULL];
    logLine(@"HEALTH wire=%lu accepted=%lu users=%lu lastWire=%.1fs",(unsigned long)wireCount,(unsigned long)postedCount,(unsigned long)users.count,lastWire?now-lastWire:-1);
}
static void setup(void) {
    atomic_store(&appState,UIApplication.sharedApplication.applicationState);
    NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){
        atomic_store(&appState,UIApplicationStateBackground);logLine(@"LIFECYCLE background");startExperiment();dispatch_async(worker,^{saveCache();writeStatus();});
    }];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){atomic_store(&appState,UIApplicationStateInactive);}];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){
        atomic_store(&appState,UIApplicationStateActive);
        /* A deferred background transition is obsolete once the host is active. */
        deferredBackground=nil;deferredReceiver=nil;deferringLifecycle=NO;[keepPlayer stop];keepPlayer=nil;
        logLine(@"LIFECYCLE active");scan();dispatch_async(worker,^{loadConfig();NSString *uid=SNIdentifier(config[@"SelfUserID"]);if(uid)setAccount(uid);writeStatus();});
    }];
    [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
        AVAudioSessionInterruptionType type=[note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
        audioInterrupted=type==AVAudioSessionInterruptionTypeBegan;
        if(audioInterrupted)stopExperiment(@"audio-interruption");
        /* No forced resume: do not fight a phone call / microphone recording. */
    }];
    [nc addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){stopExperiment(@"media-services-reset");}];
    housekeeping=[NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(__unused NSTimer *timer){
        if(deferringLifecycle&&(!keepPlayer.isPlaying||!atomic_load(&experiments)))stopExperiment(@"audio-stopped-or-disabled");
        dispatch_async(worker,^{saveCache();writeStatus();});
    }];
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionSound completionHandler:^(BOOL granted,NSError *error){logLine(@"NOTIFICATION-AUTH granted=%d code=%ld",granted,(long)error.code);}];
    scan();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{scan();});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{scan();});
    logLine(@"READY version=%@ host=%@ build=%@ session=%@",SNVersion,NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]?:@"?",NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]?:@"?",session);
}
__attribute__((constructor)) static void start(void) {
    @autoreleasepool {
        /* Process-level guard also prevents accidentally injecting two copies
           of the library and stacking another set of hooks in the same app. */
        if(objc_lookUpClass("SnapNotifyV4ProcessGuard"))return;
        Class guard=objc_allocateClassPair(NSObject.class,"SnapNotifyV4ProcessGuard",0);if(!guard)return;objc_registerClassPair(guard);
        worker=dispatch_queue_create("ch.snapnotify.events",dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL,DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM));
        logQueue=dispatch_queue_create("ch.snapnotify.log",DISPATCH_QUEUE_SERIAL);
        users=[NSMutableDictionary dictionary];presence=[NSMutableDictionary dictionary];pendingEvents=[NSMutableDictionary dictionary];issuedRequests=[NSMutableDictionary dictionary];
        session=NSUUID.UUID.UUIDString;queueGeneration=1;
        documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject];
        support=[[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES) firstObject] stringByAppendingPathComponent:@"SnapNotify"];
        [NSFileManager.defaultManager createDirectoryAtPath:support withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:NULL];
        atomic_store(&appState,UIApplicationStateInactive);
        dispatch_sync(worker,^{loadConfig();NSString *uid=SNIdentifier(config[@"SelfUserID"]);if(uid)setAccount(uid);});
        dispatch_async(dispatch_get_main_queue(),^{setup();});
    }
}
