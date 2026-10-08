// SnapNotify v2.0 — keep-alive + local notification bridge for Snapchat
// Pure ObjC runtime swizzling (no substrate/Logos). Thread-safe, throttled, rotation-safe log.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

static AVAudioPlayer *gPlayer = nil;
static NSMutableDictionary *gOrig = nil;
static NSMutableDictionary *gThrottle = nil;
static NSLock *gLock = nil;
static NSString *gLogPath = nil;
static NSTimer *gTimer = nil;
static _Thread_local BOOL t_inhit = NO;

static void sck_log(NSString *fmt, ...);

#pragma mark - helpers

static NSString *sck_app_state(void) {
    return ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) ? @"BG" : @"FG";
}

static NSString *sck_try_user(id obj) {
    if (!obj || ![obj isKindOfClass:[NSObject class]]) return @"";
    NSArray *keys = @[@"username", @"senderUsername", @"displayName", @"senderDisplayName", @"name", @"title"];
    for (NSString *k in keys) {
        @try {
            if ([obj respondsToSelector:NSSelectorFromString(k)]) {
                id v = [obj valueForKey:k];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0 && [(NSString *)v length] < 40) return v;
            }
        } @catch (NSException *e) {}
    }
    return @"";
}

static NSString *sck_label_for(NSString *cls, NSString *sel) {
    NSString *all = [[cls stringByAppendingString:@":"] stringByAppendingString:sel];
    NSString *low = [all lowercaseString];
    NSString *clslow = [cls lowercaseString];
    NSString *sellov = [sel lowercaseString];
    if ([low containsString:@"typing"]) return @"écrit...";
    if ([clslow containsString:@"sccall"] || [sellov containsString:@"callobserver"] || [sellov containsString:@"incomingcall"] || [sellov containsString:@"reportincoming"] || [sellov containsString:@"calldid"]) return @"t'appelle";
    if ([low containsString:@"receivedsnap"]) return @"t'a envoyé un snap";
    if ([low containsString:@"snapstate"]) return @"activité snap";
    if ([low containsString:@"snapupdate"]) return @"activité snap";
    if ([low containsString:@"messageupdate"] || [low containsString:@"conversationmessage"]) return @"activité chat";
    if ([low containsString:@"chatmessage"] || [low containsString:@"chatconversation"]) return @"activité chat";
    return nil;
}

#pragma mark - logging (thread-safe, rotation at 1 MB)

static void sck_log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[SnapNotify] %@", msg);
    static NSDateFormatter *df = nil;
    if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss"; }
    NSString *line = [NSString stringWithFormat:@"[%@] [%@] %@\n", [df stringFromDate:[NSDate date]], sck_app_state(), msg];
    NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
    [gLock lock];
    @try {
        if (!gLogPath) {
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            gLogPath = [docs stringByAppendingPathComponent:@"snapnotify.log"];
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attrs = [fm attributesOfItemAtPath:gLogPath error:nil];
        if (attrs && [attrs fileSize] > 1024 * 1024) {
            [fm removeItemAtPath:gLogPath error:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
        if (!fh) { [d writeToFile:gLogPath atomically:YES]; }
        else { [fh seekToEndOfFile]; [fh writeData:d]; [fh closeFile]; }
    } @catch (NSException *e) {
        NSLog(@"[SnapNotify] log exc %@", e);
    }
    [gLock unlock];
}

#pragma mark - local notification (throttled, thread-safe)

static void sck_notify_raw(NSString *key, NSString *title, NSString *body, BOOL silent) {
    if (t_inhit) return;
    t_inhit = YES;
    @try {
        [gLock lock];
        NSDate *last = gThrottle[key];
        BOOL skip = last && [[NSDate date] timeIntervalSinceDate:last] < 45.0;
        if (!skip) gThrottle[key] = [NSDate date];
        [gLock unlock];
        if (skip) { t_inhit = NO; return; }
        UNMutableNotificationContent *c = [UNMutableNotificationContent new];
        c.title = title;
        c.body = body;
        c.userInfo = @{@"scnotify": @YES};
        if (!silent) c.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest *r = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:c trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:r withCompletionHandler:^(NSError *e) {
            if (e) sck_log(@"notify err %@", e.localizedDescription);
        }];
    } @catch (NSException *e) { sck_log(@"notify exc %@", e); }
    t_inhit = NO;
}

static void sck_notify_event(NSString *cls, NSString *sel, id a) {
    NSString *label = sck_label_for(cls, sel);
    NSString *lowsel = [[cls stringByAppendingString:sel] lowercaseString];
    BOOL isEvent = (label != nil);
    BOOL isCall = [lowsel containsString:@"sccall"] || [lowsel containsString:@"callobserver"] || [lowsel containsString:@"incomingcall"] || [lowsel containsString:@"reportincoming"];
    BOOL isTyping = [lowsel containsString:@"typing"];
    if (!isEvent) {
        isEvent = [lowsel containsString:@"snap"] || [lowsel containsString:@"chat"] || [lowsel containsString:@"message"] || [lowsel containsString:@"conversation"] || [lowsel containsString:@"receive"] || [lowsel containsString:@"incoming"];
    }
    if (!isEvent) return;
    BOOL active = ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive);
    if (active && !isCall) return;
    NSString *who = sck_try_user(a);
    NSString *body;
    if (isTyping) {
        body = who.length ? [NSString stringWithFormat:@"%@ %@", who, @"est en train d'écrire..."] : @"quelqu'un est en train d'écrire...";
    } else if (isCall) {
        body = who.length ? [NSString stringWithFormat:@"%@ t'appelle !", who] : @"Appel entrant !";
    } else if (label) {
        body = who.length ? [NSString stringWithFormat:@"%@ : %@", who, label] : label;
    } else {
        body = [NSString stringWithFormat:@"activité (%@)", sel];
    }
    sck_notify_raw([NSString stringWithFormat:@"%@.%@", cls, sel], @"Snapchat", body, NO);
}

#pragma mark - silent audio keep-alive

static NSData *sck_silence(void) {
    uint32_t sr = 8000; uint16_t ch = 1, bps = 16;
    uint32_t dataLen = sr * ch * bps / 8;
    uint32_t fileLen = 44 + dataLen;
    NSMutableData *d = [NSMutableData dataWithCapacity:fileLen];
    uint32_t v; uint16_t s;
    [d appendBytes:"RIFF" length:4]; v = fileLen - 8; [d appendBytes:&v length:4];
    [d appendBytes:"WAVE" length:4]; [d appendBytes:"fmt " length:4]; v = 16; [d appendBytes:&v length:4];
    s = 1; [d appendBytes:&s length:2]; s = ch; [d appendBytes:&s length:2];
    v = sr; [d appendBytes:&v length:4]; v = sr * ch * bps / 8; [d appendBytes:&v length:4];
    s = ch * bps / 8; [d appendBytes:&s length:2]; s = bps; [d appendBytes:&s length:2];
    [d appendBytes:"data" length:4]; v = dataLen; [d appendBytes:&v length:4];
    int16_t sample = 1;
    for (uint32_t i = 0; i < dataLen / 2; i++) [d appendBytes:&sample length:2];
    return d;
}

static void sck_ensure_audio(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSError *err = nil;
            AVAudioSession *sess = [AVAudioSession sharedInstance];
            [sess setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&err];
            [sess setActive:YES error:&err];
            if (!gPlayer) {
                gPlayer = [[AVAudioPlayer alloc] initWithData:sck_silence() error:&err];
                gPlayer.numberOfLoops = -1;
                gPlayer.volume = 0.0;
                [gPlayer prepareToPlay];
            }
            if (gPlayer && !gPlayer.isPlaying) {
                BOOL ok = [gPlayer play];
                if (!ok) sck_log(@"keepalive play failed err=%@", err);
            }
        } @catch (NSException *e) { sck_log(@"audio exc %@", e); }
    });
}

#pragma mark - swizzling framework

static IMP sck_orig(id self, SEL _cmd) {
    Class c = object_getClass(self);
    while (c) {
        NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(c), sel_getName(_cmd)];
        NSValue *v = gOrig[key];
        if (v) return (IMP)[v pointerValue];
        c = class_getSuperclass(c);
    }
    return NULL;
}

static BOOL sck_enc_ok(Method m, int objArgs) {
    const char *e = method_getTypeEncoding(m);
    if (!e || e[0] != 'v') return NO;
    int ats = 0;
    const char *p = e + 1;
    while (*p) {
        char c = *p;
        if (c >= '0' && c <= '9') { p++; continue; }
        if (c == '@') {
            ats++; p++;
            if (*p == '?') p++;
            else if (*p == '"') { p++; while (*p && *p != '"') p++; if (*p) p++; }
            continue;
        }
        if (c == ':') { ats++; p++; continue; }
        if (c=='r'||c=='n'||c=='N'||c=='O'||c=='R'||c=='V'||c=='o'||c=='A') { p++; continue; }
        return NO;
    }
    return ats == objArgs + 2;
}

static void sck_hit(id self, SEL _cmd, id a, id b) {
    if (t_inhit) return;
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *cls = NSStringFromClass(object_getClass(self));
    if ([sel isEqualToString:@"userNotificationCenter:willPresentNotification:withCompletionHandler:"]) {
        @try {
            id req = [b valueForKey:@"request"];
            id content = [req valueForKey:@"content"];
            id ui = [content valueForKey:@"userInfo"];
            if ([ui isKindOfClass:[NSDictionary class]] && [[ui objectForKey:@"scnotify"] boolValue]) return;
            sck_log(@"WILLPRESENT title=%@ body=%@", [content valueForKey:@"title"] ?: @"", [content valueForKey:@"body"] ?: @"");
        } @catch (NSException *e) { sck_log(@"willpresent exc %@", e); }
        return;
    }
    if ([sel hasPrefix:@"postNotificationName:"]) {
        if (![a isKindOfClass:[NSString class]]) return;
        NSString *low = [a lowercaseString];
        NSString *core = low;
        if ([core hasPrefix:@"com.snapchat."]) core = [core substringFromIndex:13];
        else if ([core hasPrefix:@"com.snapchat"]) core = [core substringFromIndex:12];
        if ([core containsString:@"managed"] || [core containsString:@"context"] || [core containsString:@"window"] || [core containsString:@"audiosession"] || [core containsString:@"keyboard"] || [core containsString:@"keypath"] || [core containsString:@"external"] || [core containsString:@"screen"] || [core containsString:@"scene"] || [core containsString:@"layout"] || [core containsString:@"lens"] || [core containsString:@"unlockable"] || [core containsString:@"viewcontroller"] || [core hasPrefix:@"ns"] || [core hasPrefix:@"_ns"] || [core hasPrefix:@"_ui"] || [core hasPrefix:@"av"] || [core hasPrefix:@"un"] || [core hasPrefix:@"_un"]) return;
        BOOL interesting = [core containsString:@"typing"] || [core containsString:@"message"] || [core containsString:@"conversation"] || [core containsString:@"receive"] || [core containsString:@"incoming"] || [core containsString:@"call"] || [core containsString:@"presence"];
        if (!interesting) return;
        sck_log(@"NOTIFPOST %@", a);
        sck_notify_raw([@"post" stringByAppendingString:a], @"Snapchat", [NSString stringWithFormat:@"activité (%@)", a], NO);
        return;
    }
    @try {
        sck_log(@"HIT [%@] -[%@ %@]", sck_app_state(), cls, sel);
        sck_notify_event(cls, sel, a);
    } @catch (NSException *e) { sck_log(@"hit exc %@", e); }
}

static void sck_repl0(id self, SEL _cmd) { sck_hit(self, _cmd, nil, nil); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL))o)(self, _cmd); }
static void sck_repl1(id self, SEL _cmd, id a) { sck_hit(self, _cmd, a, nil); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id))o)(self, _cmd, a); }
static void sck_repl2(id self, SEL _cmd, id a, id b) { sck_hit(self, _cmd, a, b); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id, id))o)(self, _cmd, a, b); }
static void sck_repl3(id self, SEL _cmd, id a, id b, id c) { sck_hit(self, _cmd, a, b); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id, id, id))o)(self, _cmd, a, b, c); }

static void sck_attach(Class c, Method m) {
    SEL sel = method_getName(m);
    const char *sn = sel_getName(sel);
    int colons = 0;
    for (const char *p = sn; *p; p++) if (*p == ':') colons++;
    NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(c), sn];
    [gLock lock];
    BOOL done = (gOrig[key] != nil);
    [gLock unlock];
    if (done) return;
    if (!sck_enc_ok(m, colons)) return;
    IMP newImp = NULL;
    switch (colons) {
        case 0: newImp = (IMP)sck_repl0; break;
        case 1: newImp = (IMP)sck_repl1; break;
        case 2: newImp = (IMP)sck_repl2; break;
        case 3: newImp = (IMP)sck_repl3; break;
        default: return;
    }
    IMP old = method_setImplementation(m, newImp);
    [gLock lock];
    gOrig[key] = [NSValue valueWithPointer:(void *)old];
    [gLock unlock];
    sck_log(@"swizzled -[%s %s]", class_getName(c), sn);
}

static void sck_hook_all(Class c) {
    unsigned mc = 0;
    Method *ms = class_copyMethodList(c, &mc);
    if (!ms) return;
    for (unsigned j = 0; j < mc; j++) {
        const char *sn = sel_getName(method_getName(ms[j]));
        if (strcmp(sn, "dealloc") == 0 || strcmp(sn, ".cxx_destruct") == 0 || strcmp(sn, ".cxx_construct") == 0 || strcmp(sn, "initialize") == 0) continue;
        int colons = 0;
        for (const char *p = sn; *p; p++) if (*p == ':') colons++;
        if (colons > 3) continue;
        if (!sck_enc_ok(ms[j], colons)) continue;
        sck_attach(c, ms[j]);
    }
    free(ms);
}

static void sck_scan(void) {
    @try {
        static NSArray *targets = nil;
        if (!targets) targets = @[
            @"session:didReceiveMessage:",
            @"session:didReceiveMessage:replyHandler:",
            @"session:didReceiveMessageData:",
            @"session:didReceiveMessageData:replyHandler:",
            @"URLSession:webSocketTask:didReceiveMessage:",
            @"URLSession:webSocketTask:didReceiveMessageData:",
            @"_didReceiveNotificationWithUserInfoInPerformer:",
            @"didReceiveNotificationWithUserInfo:",
            @"presentInAppNotification:delegate:",
            @"presentInAppNotificationAsync:delegate:",
            @"userNotificationCenter:willPresentNotification:withCompletionHandler:",
            @"userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:",
            @"handleInAppNotification:",
            @"handleInAppNotification:navigationController:",
            @"matchInAppNotification:systemNotification:",
            @"callObserver:callChanged:",
            @"postNotificationName:object:userInfo:",
            @"postNotificationName:object:"
        ];
        NSSet *tset = [NSSet setWithArray:targets];
        int n = objc_getClassList(NULL, 0);
        if (n <= 0) return;
        __unsafe_unretained Class *list = (__unsafe_unretained Class *)malloc(sizeof(Class) * n);
        if (!list) return;
        n = objc_getClassList(list, n);
        for (int i = 0; i < n; i++) {
            Class c = list[i];
            if (c == nil) continue;
            const char *cn = class_getName(c);
            BOOL isSnapClass = cn && (strncmp(cn, "SC", 2) == 0 || strstr(cn, "Snapchat") != NULL);
            if (isSnapClass && (strstr(cn, "Typing") || strstr(cn, "CallState") || strstr(cn, "CallLauncher") || strstr(cn, "SCCallLogSyncer"))) {
                sck_hook_all(c);
                continue;
            }
            unsigned mc = 0;
            Method *ms = class_copyMethodList(c, &mc);
            if (!ms) continue;
            for (unsigned j = 0; j < mc; j++) {
                NSString *nm = NSStringFromSelector(method_getName(ms[j]));
                if ([tset containsObject:nm]) sck_attach(c, ms[j]);
            }
            free(ms);
        }
        free(list);
        NSArray *soju = @[@"SOJUReceivedSnap", @"SOJUChatConversationSnapUpdates", @"SOJUSnapUpdate", @"SOJUReceivedSnapWithAttachment", @"SOJUReceivedChatMessage", @"SOJUChatv3SnapStateMessage", @"SOJUChatv3ReleaseMessage", @"SOJUChatConversationMessageUpdates", @"SOJUChatConversationMessages", @"SOJUConversationMessage", @"SOJUChatMessage", @"SOJUChatOrSnapMessage", @"SOJUConversationStateChatRelease", @"SOJUConversationStateSnapRelease"];
        for (NSString *cn in soju) {
            Class c = objc_getClass([cn UTF8String]);
            if (!c) { sck_log(@"soju: class %@ not found", cn); continue; }
            unsigned mc = 0;
            Method *ms = class_copyMethodList(c, &mc);
            if (!ms) continue;
            for (unsigned j = 0; j < mc; j++) {
                NSString *nm = NSStringFromSelector(method_getName(ms[j]));
                if ([nm hasPrefix:@"init"] || [nm hasPrefix:@"parse"] || [nm hasPrefix:@"merge"] || [nm hasPrefix:@"decode"]) sck_attach(c, ms[j]);
            }
            free(ms);
        }
        sck_log(@"scan done hooks=%lu", (unsigned long)gOrig.count);
    } @catch (NSException *e) { sck_log(@"scan exc %@", e); }
}

#pragma mark - setup

static void sck_setup(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { sck_log(@"app -> background"); sck_ensure_audio(); }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { sck_log(@"app -> active"); sck_ensure_audio(); }];
    [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        sck_log(@"audio interrupt");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ sck_ensure_audio(); });
    }];
    [nc addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        sck_log(@"audio services reset");
        gPlayer = nil;
        sck_ensure_audio();
    }];
    [nc addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        sck_scan();
        sck_ensure_audio();
        [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
            if (settings.authorizationStatus != UNAuthorizationStatusAuthorized) {
                sck_log(@"WARNING: notification permission not granted (status %ld)", (long)settings.authorizationStatus);
            }
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sck_notify_raw(@"boot", @"Snapchat", [NSString stringWithFormat:@"SnapNotify v2.2 chargé (%lu hooks)", (unsigned long)gOrig.count], YES);
        });
    }];
    gTimer = [NSTimer scheduledTimerWithTimeInterval:20.0 repeats:YES block:^(NSTimer *t) { sck_ensure_audio(); }];
    sck_log(@"setup done");
}

#pragma mark - entry

__attribute__((constructor)) static void sck_init(void) {
    @autoreleasepool {
        gLock = [NSLock new];
        gOrig = [NSMutableDictionary new];
        gThrottle = [NSMutableDictionary new];
        sck_scan();
        dispatch_async(dispatch_get_main_queue(), ^{ sck_setup(); });
    }
}
