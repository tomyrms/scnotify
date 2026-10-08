// SnapNotify v1 — keep-alive + local notification bridge for Snapchat (diagnostic)
// Pure ObjC runtime swizzling (no substrate/Logos needed).
// Writes log to <app docs>/snapnotify.log and posts throttled local notifications on hits.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdlib.h>

static AVAudioPlayer *gPlayer = nil;
static NSMutableDictionary *gOrig = nil;
static NSMutableDictionary *gThrottle = nil;
static NSString *gLogPath = nil;
static NSTimer *gTimer = nil;
static _Thread_local BOOL t_inhit = NO;

#pragma mark - logging

static void sck_log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[SnapNotify] %@", msg);
    static NSDateFormatter *df = nil;
    if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss.SSS"; }
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];
    if (!gLogPath) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        gLogPath = [docs stringByAppendingPathComponent:@"snapnotify.log"];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
    NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!fh) { [d writeToFile:gLogPath atomically:YES]; }
    else { @try { [fh seekToEndOfFile]; [fh writeData:d]; [fh closeFile]; } @catch (NSException *e) {} }
}

#pragma mark - local notification

static void sck_notify(NSString *key, NSString *body) {
    if (t_inhit) return;
    t_inhit = YES;
    @try {
        NSDate *last = gThrottle[key];
        if (last && [[NSDate date] timeIntervalSinceDate:last] < 45.0) { t_inhit = NO; return; }
        gThrottle[key] = [NSDate date];
        UNMutableNotificationContent *c = [UNMutableNotificationContent new];
        c.title = @"SnapNotify";
        c.body = body;
        c.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest *r = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:c trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:r withCompletionHandler:^(NSError *e) {
            if (e) sck_log(@"notify err %@", e.localizedDescription);
        }];
    } @catch (NSException *e) { sck_log(@"notify exc %@", e); }
    t_inhit = NO;
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
                sck_log(@"keepalive play=%d err=%@", ok, err);
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

static void sck_hit(id self, SEL _cmd, id a, int n) {
    if (t_inhit) return;
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *cls = NSStringFromClass(object_getClass(self));
    if ([sel hasPrefix:@"postNotificationName:"]) {
        if (![a isKindOfClass:[NSString class]]) return;
        NSString *low = [a lowercaseString];
        if ([low containsString:@"managed"] || [low containsString:@"context"] || [low containsString:@"window"] || [low containsString:@"audiosession"] || [low containsString:@"keyboard"] || [low containsString:@"keypath"] || [low containsString:@"external"] || [low containsString:@"screen"] || [low containsString:@"scene"] || [low containsString:@"layout"] || [low hasPrefix:@"ns"] || [low hasPrefix:@"_ns"] || [low hasPrefix:@"_ui"] || [low hasPrefix:@"av"] || [low hasPrefix:@"kb"]) return;
        BOOL interesting = [low containsString:@"snap"] || [low containsString:@"chat"] || [low containsString:@"message"] || [low containsString:@"conversation"] || [low containsString:@"incoming"] || [low containsString:@"receive"] || [low containsString:@"typing"] || [low containsString:@"presence"];
        if (!interesting) return;
        sck_log(@"NOTIFPOST %@", a);
        sck_notify([@"post" stringByAppendingString:a], [NSString stringWithFormat:@"post: %@", a]);
        return;
    }
    NSString *info = @"";
    if ([a isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [(NSDictionary *)a allKeys];
        if (keys.count) info = [NSString stringWithFormat:@" keys=%@", [keys componentsJoinedByString:@","]];
    } else if (a) {
        info = [NSString stringWithFormat:@" <%@>", NSStringFromClass(object_getClass(a))];
    }
    NSString *appState = ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) ? @"BG" : @"FG";
    NSString *msg = [NSString stringWithFormat:@"[%@] -[%@ %@]%@", appState, cls, sel, info];
    sck_log(@"HIT %@", msg);
    sck_notify([NSString stringWithFormat:@"%@.%@", cls, sel], msg);
}

static void sck_repl0(id self, SEL _cmd) { sck_hit(self, _cmd, nil, 0); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL))o)(self, _cmd); }
static void sck_repl1(id self, SEL _cmd, id a) { sck_hit(self, _cmd, a, 1); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id))o)(self, _cmd, a); }
static void sck_repl2(id self, SEL _cmd, id a, id b) { sck_hit(self, _cmd, a, 2); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id, id))o)(self, _cmd, a, b); }
static void sck_repl3(id self, SEL _cmd, id a, id b, id c) { sck_hit(self, _cmd, a, 3); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id, id, id))o)(self, _cmd, a, b, c); }

static void sck_attach(Class c, Method m) {
    SEL sel = method_getName(m);
    const char *sn = sel_getName(sel);
    int colons = 0;
    for (const char *p = sn; *p; p++) if (*p == ':') colons++;
    NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(c), sn];
    if (gOrig[key]) return;
    if (!sck_enc_ok(m, colons)) { sck_log(@"skip(enc) -[%s %s]", class_getName(c), sn); return; }
    IMP newImp = NULL;
    switch (colons) {
        case 0: newImp = (IMP)sck_repl0; break;
        case 1: newImp = (IMP)sck_repl1; break;
        case 2: newImp = (IMP)sck_repl2; break;
        case 3: newImp = (IMP)sck_repl3; break;
        default: sck_log(@"skip(arity %d) -[%s %s]", colons, class_getName(c), sn); return;
    }
    IMP old = method_setImplementation(m, newImp);
    gOrig[key] = [NSValue valueWithPointer:(void *)old];
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
    gOrig = [NSMutableDictionary new];
    gThrottle = [NSMutableDictionary new];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { sck_log(@"app -> background"); sck_ensure_audio(); }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { sck_log(@"app -> active"); sck_ensure_audio(); }];
    [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        sck_log(@"audio interrupt");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ sck_ensure_audio(); });
    }];
    [nc addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        sck_scan();
        sck_ensure_audio();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sck_notify(@"boot", [NSString stringWithFormat:@"SnapNotify v1.3 loaded (%lu hooks)", (unsigned long)gOrig.count]);
        });
    }];
    gTimer = [NSTimer scheduledTimerWithTimeInterval:20.0 repeats:YES block:^(NSTimer *t) { sck_ensure_audio(); }];
    sck_log(@"setup done");
}

#pragma mark - entry

__attribute__((constructor)) static void sck_init(void) {
    @autoreleasepool {
        sck_scan();
        dispatch_async(dispatch_get_main_queue(), ^{ sck_setup(); });
    }
}
