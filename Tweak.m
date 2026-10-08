// SnapNotify v3.0 — keep-alive + local notification bridge for Snapchat
// Adds: sender name extraction (KVC + protobuf description scan + userId cache),
// per-type throttling, cross-hook dedup, Duplex realtime hooks.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static AVAudioPlayer *gPlayer = nil;
static NSMutableDictionary *gOrig = nil;
static NSMutableDictionary *gThrottle = nil;
static NSMutableDictionary *gNameCache = nil;
static NSLock *gLock = nil;
static NSString *gLogPath = nil;
static NSTimer *gTimer = nil;
static _Thread_local BOOL t_inhit = NO;

static void sck_log(NSString *fmt, ...);
static NSString *sck_extract_name(id obj, BOOL *found);

#pragma mark - helpers

static NSString *sck_app_state(void) {
    return ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) ? @"BG" : @"FG";
}

static NSString *sck_regex_first(NSString *pattern, NSString *text) {
    if (!pattern || !text || text.length < 4) return nil;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&err];
    if (!re) return nil;
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    NSRange r = [m rangeAtIndex:1];
    if (r.location == NSNotFound || r.length == 0) return nil;
    return [text substringWithRange:r];
}

static NSString *sck_event_type(NSString *cls, NSString *sel) {
    NSString *low = [[[cls stringByAppendingString:@":"] stringByAppendingString:sel] lowercaseString];
    if ([low containsString:@"typing"]) return @"typing";
    if ([low containsString:@"sccall"] || [low containsString:@"callobserver"] || [low containsString:@"incomingcall"] || [low containsString:@"reportincoming"]) return @"call";
    if ([low containsString:@"receivedsnap"]) return @"snap";
    if ([low containsString:@"snapstate"] || [low containsString:@"snapupdate"] || [low containsString:@"snapdelta"]) return @"snapstate";
    if ([low containsString:@"chatmessage"] || [low containsString:@"conversationmessage"] || [low containsString:@"messageupdate"] || [low containsString:@"chatconversation"] || [low containsString:@"chatormessage"] || [low containsString:@"receivedchat"]) return @"message";
    if ([low containsString:@"message"] || [low containsString:@"conversation"] || [low containsString:@"receive"] || [low containsString:@"incoming"] || [low containsString:@"presence"]) return @"generic";
    return nil;
}

static NSString *sck_message_body(NSString *t, NSString *name) {
    NSString *who = (name.length ? name : @"Quelqu'un");
    if ([t isEqualToString:@"typing"]) return [NSString stringWithFormat:@"%@ est en train d'écrire...", who];
    if ([t isEqualToString:@"call"]) return (name.length ? [NSString stringWithFormat:@"%@ t'appelle !", name] : @"Appel entrant !");
    if ([t isEqualToString:@"snap"]) return [NSString stringWithFormat:@"%@ t'a envoyé un snap", who];
    if ([t isEqualToString:@"snapstate"]) return [NSString stringWithFormat:@"%@ a vu/ouvert ton snap", who];
    if ([t isEqualToString:@"message"]) return [NSString stringWithFormat:@"%@ t'a envoyé un message", who];
    return [NSString stringWithFormat:@"activité de %@", who];
}

static NSString *sck_duplex_kind(NSData *d) {
    if (!d.length) return nil;
    NSArray *kinds = @[@"typing", @"chat", @"message", @"snap", @"story", @"presence"];
    for (NSString *k in kinds) {
        NSData *kd = [k dataUsingEncoding:NSUTF8StringEncoding];
        if ([d rangeOfData:kd options:0 range:NSMakeRange(0, d.length)].location != NSNotFound) return k;
    }
    return nil;
}

static NSString *sck_extract_name_depth(id obj, BOOL *found, int depth) {
    if (found) *found = NO;
    if (!obj || depth > 2) return nil;
    NSString *name = nil;
    NSString *desc = nil;

    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)obj;
        for (id k in d) {
            if (![k isKindOfClass:[NSString class]]) continue;
            NSString *lk = [k lowercaseString];
            id v = d[k];
            if (![v isKindOfClass:[NSString class]]) continue;
            if ([lk containsString:@"username"] || [lk containsString:@"displayname"] || ([lk containsString:@"name"] && ![lk containsString:@"filename"])) { name = v; break; }
        }
    }
    if (!name) {
        for (NSString *k in @[@"senderUsername", @"username", @"senderDisplayName", @"displayName", @"senderName", @"displayUsername", @"fromUsername", @"senderUserName", @"name", @"sender", @"user", @"title", @"recipientUsername", @"recipientDisplayName", @"conversationName"]) {
            @try {
                if ([obj respondsToSelector:NSSelectorFromString(k)]) {
                    id v = [obj valueForKey:k];
                    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0 && [(NSString *)v length] < 40) { name = v; break; }
                    if (v && ![v isKindOfClass:[NSString class]] && ![v isKindOfClass:[NSNumber class]] && ![v isKindOfClass:[NSData class]]) {
                        NSString *rec = sck_extract_name_depth(v, NULL, depth + 1);
                        if (rec.length) { name = rec; break; }
                    }
                }
            } @catch (NSException *e) {}
        }
    }
    @try { desc = [obj description]; } @catch (NSException *e) { desc = nil; }
    if (!name && desc) {
        name = sck_regex_first(@"(?:senderUsername|username|senderDisplayName|displayName|senderName)[^A-Za-z0-9]{0,12}([A-Za-z0-9._-]{2,40})", desc);
    }
    NSString *ident = nil;
    @try {
        for (NSString *k in @[@"conversationId", @"senderId", @"userId"]) {
            if ([obj respondsToSelector:NSSelectorFromString(k)]) {
                id v = [obj valueForKey:k];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0 && [(NSString *)v length] < 64) { ident = v; break; }
            }
        }
    } @catch (NSException *e) {}
    if (!ident && desc) {
        ident = sck_regex_first(@"(?:conversationId|senderId|userId)[^A-Za-z0-9]{0,12}([A-Za-z0-9._-]{2,64})", desc);
    }
    if (ident && name.length) {
        BOOL changed = NO;
        [gLock lock];
        if (![gNameCache[ident] isEqual:name]) { gNameCache[ident] = name; changed = YES; }
        [gLock unlock];
        if (changed) sck_log(@"NAMECACHE %@ -> %@", ident, name);
    } else if (!name && ident) {
        [gLock lock];
        name = gNameCache[ident];
        [gLock unlock];
    }
    if (name.length) { if (found) *found = YES; return name; }
    return nil;
}

static NSString *sck_extract_name(id obj, BOOL *found) {
    return sck_extract_name_depth(obj, found, 0);
}

#pragma mark - logging (thread-safe, rotation at 1 MB)

static void sck_log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[SnapNotify] %@", msg);
    static NSDateFormatter *df = nil;
    if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss.SSS"; }
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

static void sck_log_obj(NSString *tag, id obj) {
    if (!obj) return;
    @try {
        NSString *d = [obj description];
        if (d.length > 500) d = [d substringToIndex:500];
        sck_log(@"   %@[%@]=%@", tag, NSStringFromClass(object_getClass(obj)), d);
    } @catch (NSException *e) {}
}

#pragma mark - local notification (typed throttle, thread-safe)

static void sck_notify_thr(NSString *key, NSString *title, NSString *body, BOOL silent, double secs) {
    if (t_inhit) return;
    t_inhit = YES;
    @try {
        [gLock lock];
        NSDate *last = gThrottle[key];
        BOOL skip = last && [[NSDate date] timeIntervalSinceDate:last] < secs;
        if (!skip) gThrottle[key] = [NSDate date];
        [gLock unlock];
        if (skip) { sck_log(@"NOTIF-SKIP key=%@", key); t_inhit = NO; return; }
        UNMutableNotificationContent *c = [UNMutableNotificationContent new];
        c.title = title;
        c.body = body;
        c.userInfo = @{@"scnotify": @YES};
        if (!silent) c.sound = [UNNotificationSound defaultSound];
        sck_log(@"NOTIF-POST key=%@ body=%@", key, body);
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

static void sck_hit(id self, SEL _cmd, id a, id b, id c) {
    if (t_inhit) return;
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *cls = NSStringFromClass(object_getClass(self));
    if ([sel isEqualToString:@"userNotificationCenter:willPresentNotification:withCompletionHandler:"]) {
        @try {
            id req = [b valueForKey:@"request"];
            id content = [req valueForKey:@"content"];
            id ui = [content valueForKey:@"userInfo"];
            if ([ui isKindOfClass:[NSDictionary class]] && [[ui objectForKey:@"scnotify"] boolValue]) return;
            NSString *title = [content valueForKey:@"title"] ?: @"";
            NSString *body = [content valueForKey:@"body"] ?: @"";
            sck_log(@"WILLPRESENT title=%@ body=%@", title, body);
            BOOL active = ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive);
            if (!active && (title.length || body.length)) {
                sck_notify_thr([NSString stringWithFormat:@"wp|%@|%@", title, body], @"Snapchat", body.length ? body : title, NO, 2.0);
            }
        } @catch (NSException *e) { sck_log(@"willpresent exc %@", e); }
        return;
    }
    if ([sel isEqualToString:@"application:didRegisterForRemoteNotificationsWithDeviceToken:"]) {
        NSData *tok = [b isKindOfClass:[NSData class]] ? (NSData *)b : nil;
        sck_log(@"PUSH TOKEN len=%lu", (unsigned long)tok.length);
        return;
    }
    if ([sel isEqualToString:@"application:didFailToRegisterForRemoteNotificationsWithError:"]) {
        sck_log(@"PUSH REGISTRATION FAILED: %@", b);
        return;
    }
    if ([sel hasPrefix:@"application:didReceiveRemoteNotification:"]) {
        NSDictionary *ui = [b isKindOfClass:[NSDictionary class]] ? (NSDictionary *)b : nil;
        sck_log(@"PUSH RECV keys=%@", ui.allKeys);
        BOOL active = ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive);
        if (ui && !active) {
            NSString *body = nil;
            id aps = ui[@"aps"];
            if ([aps isKindOfClass:[NSDictionary class]]) {
                id alert = aps[@"alert"];
                if ([alert isKindOfClass:[NSString class]]) body = alert;
                else if ([alert isKindOfClass:[NSDictionary class]]) body = alert[@"body"] ?: alert[@"title"];
            }
            if (!body.length) body = ui[@"body"] ?: ui[@"message"] ?: @"notification";
            sck_notify_thr([@"push" stringByAppendingString:body], @"Snapchat", body, NO, 2.0);
        }
        return;
    }
    if ([sel isEqualToString:@"addNotificationRequest:withCompletionHandler:"]) {
        @try {
            id content = [a valueForKey:@"content"];
            id ui = [content valueForKey:@"userInfo"];
            if ([ui isKindOfClass:[NSDictionary class]] && [[ui objectForKey:@"scnotify"] boolValue]) return;
            NSString *title = [content valueForKey:@"title"] ?: @"";
            NSString *body = [content valueForKey:@"body"] ?: @"";
            sck_log(@"SNAP-LOCAL title=%@ body=%@", title, body);
            BOOL active = ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive);
            if (!active && (title.length || body.length)) {
                sck_notify_thr([NSString stringWithFormat:@"sl|%@|%@", title, body], @"Snapchat", body.length ? body : title, NO, 2.0);
            }
        } @catch (NSException *e) { sck_log(@"snap-local exc %@", e); }
        return;
    }
    if ([sel isEqualToString:@"userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:"]) {
        @try {
            id notif = [b valueForKey:@"notification"];
            id req = [notif valueForKey:@"request"];
            id content = [req valueForKey:@"content"];
            id ui = [content valueForKey:@"userInfo"];
            if ([ui isKindOfClass:[NSDictionary class]] && [[ui objectForKey:@"scnotify"] boolValue]) { sck_log(@"TAP (ours)"); return; }
            sck_log(@"TAP title=%@ body=%@", [content valueForKey:@"title"] ?: @"", [content valueForKey:@"body"] ?: @"");
        } @catch (NSException *e) { sck_log(@"tap exc %@", e); }
        return;
    }
    if ([cls containsString:@"DuplexMessageHandler"] && [sel isEqualToString:@"onReceive:"]) {
        NSData *d = [a isKindOfClass:[NSData class]] ? (NSData *)a : nil;
        NSString *kind = sck_duplex_kind(d);
        NSMutableString *hex = [NSMutableString string];
        const uint8_t *bp = d.bytes;
        NSUInteger hn = d.length < 48 ? d.length : 48;
        for (NSUInteger i = 0; i < hn; i++) [hex appendFormat:@"%02x", bp[i]];
        sck_log(@"DUPLEX kind=%@ len=%lu hex=%@", kind ?: @"?", (unsigned long)d.length, hex.length ? hex : @"-");
        if (!kind || [kind isEqualToString:@"presence"]) return;
        BOOL dactive = ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive);
        if (dactive) return;
        NSString *dbody = nil;
        if ([kind isEqualToString:@"typing"]) dbody = @"quelqu'un est en train d'écrire...";
        else if ([kind isEqualToString:@"snap"]) dbody = @"nouveau snap reçu";
        else dbody = @"nouveau message reçu";
        sck_notify_thr([@"duplex|" stringByAppendingString:kind], @"Snapchat", dbody, NO, 2.0);
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
        sck_notify_thr([@"post" stringByAppendingString:a], @"Snapchat", [NSString stringWithFormat:@"activité (%@)", a], NO, 10.0);
        return;
    }
    @try {
        sck_log(@"HIT [%@] -[%@ %@]", sck_app_state(), cls, sel);
        if ([cls containsString:@"SCCallStateProvider"] && [sel isEqualToString:@"updateWithPresencePlatformActiveConversationsInfo:"]) {
            @try {
                NSString *desc = [a description] ?: @"";
                NSRange r = [desc rangeOfString:@"remoteTypingParticipants"];
                if (r.location != NSNotFound) {
                    NSString *tail = [desc substringFromIndex:r.location];
                    NSRange close = [tail rangeOfString:@"]"];
                    NSString *uid = sck_regex_first(@"userId: *([0-9a-fA-F-]{36})", tail);
                    if (uid.length) {
                        BOOL inSection = (close.location == NSNotFound);
                        if (!inSection) {
                            NSRange uir = [tail rangeOfString:uid];
                            inSection = (uir.location != NSNotFound && uir.location < close.location);
                        }
                        if (inSection) {
                            [gLock lock]; NSString *nm = gNameCache[uid]; [gLock unlock];
                            sck_log(@"PRESENCE-TYPING uid=%@ name=%@", uid, nm.length ? nm : @"(none)");
                            BOOL active = ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive);
                            if (!active) {
                                NSString *body = nm.length ? [NSString stringWithFormat:@"%@ est en train d'écrire...", nm] : @"quelqu'un est en train d'écrire...";
                                sck_notify_thr([@"typing|" stringByAppendingString:(nm.length ? nm : uid)], @"Snapchat", body, NO, 25.0);
                            }
                        }
                    }
                }
            } @catch (NSException *e) { sck_log(@"presence exc %@", e); }
            return;
        }
        sck_log_obj(@"a", a);
        if (b && b != a) sck_log_obj(@"b", b);
        if (c && c != a && c != b) sck_log_obj(@"c", c);
        if ([cls containsString:@"Snapchatter"] || [cls containsString:@"ChatConversation"] || [cls containsString:@"ConversationViewModel"] || [cls containsString:@"ConversationMetadata"] || [cls containsString:@"FriendsFeed"]) {
            sck_extract_name(self, NULL);
            sck_extract_name(a, NULL);
            if (b && b != a) sck_extract_name(b, NULL);
            if (c && c != a && c != b) sck_extract_name(c, NULL);
        }
        if ([cls containsString:@"TypingBubbleView"]) return;
        NSString *t = sck_event_type(cls, sel);
        if (!t) return;
        NSString *sell = [sel lowercaseString];
        if ([t isEqualToString:@"call"]) {
            BOOL realCall = [sell containsString:@"callobserver"] || [sell containsString:@"callchanged"] || [sell containsString:@"incomingcall"] || [sell containsString:@"reportincoming"] || [sell containsString:@"callreceived"] || [sell containsString:@"didreceivecall"];
            if (!realCall) return;
        }
        BOOL active = ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive);
        if (active && ![t isEqualToString:@"call"]) { sck_log(@"SKIP(active) %@ %@", cls, sel); return; }
        BOOL foundName = NO;
        NSString *name = sck_extract_name(a, &foundName);
        if (!name.length && b && b != a) name = sck_extract_name(b, &foundName);
        if (!name.length && c && c != a && c != b) name = sck_extract_name(c, &foundName);
        NSString *body = nil;
        if ([t isEqualToString:@"generic"]) {
            NSString *lowall = [[[cls stringByAppendingString:@":"] stringByAppendingString:sel] lowercaseString];
            if ([lowall containsString:@"presence"]) return;
            BOOL msgLike = [lowall containsString:@"message"] || [lowall containsString:@"chat"];
            BOOL snapLike = [lowall containsString:@"snap"];
            if (!msgLike && !snapLike) return;
            NSString *base = snapLike ? @"nouvelle activité snap" : @"nouveau message";
            body = name.length ? [NSString stringWithFormat:@"%@ : %@", name, base] : base;
        } else {
            body = sck_message_body(t, name);
        }
        double thr = [t isEqualToString:@"typing"] ? 25.0 : 2.0;
        NSString *key = [NSString stringWithFormat:@"%@|%@", t, name.length ? name : @"?"];
        sck_log(@"EVENT type=%@ name=%@ body=%@", t, name.length ? name : @"(none)", body);
        sck_notify_thr(key, @"Snapchat", body, NO, thr);
    } @catch (NSException *e) { sck_log(@"hit exc %@", e); }
}

static void sck_repl0(id self, SEL _cmd) { sck_hit(self, _cmd, nil, nil, nil); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL))o)(self, _cmd); }
static void sck_repl1(id self, SEL _cmd, id a) { sck_hit(self, _cmd, a, nil, nil); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id))o)(self, _cmd, a); }
static void sck_repl2(id self, SEL _cmd, id a, id b) { sck_hit(self, _cmd, a, b, nil); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id, id))o)(self, _cmd, a, b); }
static void sck_repl3(id self, SEL _cmd, id a, id b, id c) { sck_hit(self, _cmd, a, b, c); IMP o = sck_orig(self, _cmd); if (o) ((void (*)(id, SEL, id, id, id))o)(self, _cmd, a, b, c); }

static id sck_repl_id1(id self, SEL _cmd, id a) {
    IMP o = sck_orig(self, _cmd);
    id ret = o ? ((id (*)(id, SEL, id))o)(self, _cmd, a) : nil;
    @try {
        if ([a isKindOfClass:[NSString class]] && [ret isKindOfClass:[NSString class]] && [ret length] > 0 && [ret length] < 40) {
            BOOL changed = NO;
            [gLock lock];
            if (![gNameCache[a] isEqual:ret]) { gNameCache[a] = ret; changed = YES; }
            [gLock unlock];
            if (changed) sck_log(@"NAMECACHE %@ -> %@", a, ret);
        }
    } @catch (NSException *e) {}
    return ret;
}

static id sck_repl_id2(id self, SEL _cmd, id a, id b) {
    IMP o = sck_orig(self, _cmd);
    id ret = o ? ((id (*)(id, SEL, id, id))o)(self, _cmd, a, b) : nil;
    @try {
        if ([a isKindOfClass:[NSString class]] && [ret isKindOfClass:[NSString class]] && [ret length] > 0 && [ret length] < 40) {
            BOOL changed = NO;
            [gLock lock];
            if (![gNameCache[a] isEqual:ret]) { gNameCache[a] = ret; changed = YES; }
            [gLock unlock];
            if (changed) sck_log(@"NAMECACHE %@ -> %@", a, ret);
        }
    } @catch (NSException *e) {}
    return ret;
}

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
    {
        char lowbuf[300];
        size_t ln = strlen(sn);
        if (ln >= sizeof(lowbuf)) ln = sizeof(lowbuf) - 1;
        for (size_t k = 0; k < ln; k++) lowbuf[k] = (char)tolower((unsigned char)sn[k]);
        lowbuf[ln] = 0;
        BOOL resolver = (strstr(lowbuf, "displaynameforuser") != NULL) || (strstr(lowbuf, "usernameforuser") != NULL) || (strstr(lowbuf, "nameforuserid") != NULL) || (strstr(lowbuf, "displaynameforcontact") != NULL);
        if (resolver && (colons == 1 || colons == 2)) {
            IMP newImp = (colons == 1) ? (IMP)sck_repl_id1 : (IMP)sck_repl_id2;
            IMP old = method_setImplementation(m, newImp);
            [gLock lock];
            gOrig[key] = [NSValue valueWithPointer:(void *)old];
            [gLock unlock];
            sck_log(@"swizzled(ret%d) -[%s %s]", colons, class_getName(c), sn);
            return;
        }
    }
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

static void sck_hook_duplex(Class c) {
    unsigned mc = 0;
    Method *ms = class_copyMethodList(c, &mc);
    if (!ms) return;
    for (unsigned j = 0; j < mc; j++) {
        const char *sn = sel_getName(method_getName(ms[j]));
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
            @"_displayNameForUserId:",
            @"displayNameForUserId:",
            @"usernameForUserId:",
            @"application:didReceiveRemoteNotification:fetchCompletionHandler:",
            @"application:didReceiveRemoteNotification:",
            @"application:didRegisterForRemoteNotificationsWithDeviceToken:",
            @"application:didFailToRegisterForRemoteNotificationsWithError:",
            @"addNotificationRequest:withCompletionHandler:",
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
            if (isSnapClass && (strstr(cn, "Typing") || strstr(cn, "CallState") || strstr(cn, "CallLauncher") || strstr(cn, "SCCallLogSyncer") || strstr(cn, "SCPushNotificationDelegate") || strstr(cn, "SCMainAppDelegate") || strstr(cn, "SCAppDelegate") || strstr(cn, "Hermod") || strstr(cn, "ChatConversationUpdater") || strstr(cn, "ChatConversationViewModel") || strstr(cn, "SCChatConversationManager"))) {
                sck_hook_all(c);
                continue;
            }
            if (isSnapClass && strstr(cn, "Duplex")) {
                sck_hook_duplex(c);
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
        NSArray *models = @[@"SCSnapchatter", @"SCChatConversation", @"SCChatConversationViewModel", @"SCChatConversationViewModelV3", @"SCFriendsFeedItem", @"SCFriendsFeedViewModel"];
        for (NSString *mn in models) {
            Class mc = objc_getClass([mn UTF8String]);
            if (!mc) { sck_log(@"model: class %@ not found", mn); continue; }
            sck_hook_all(mc);
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
            sck_log(@"notif permission=%ld alert=%ld sound=%ld badge=%ld", (long)settings.authorizationStatus, (long)settings.alertSetting, (long)settings.soundSetting, (long)settings.badgeSetting);
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sck_notify_thr(@"boot", @"Snapchat", [NSString stringWithFormat:@"SnapNotify v3.6 chargé (%lu hooks)", (unsigned long)gOrig.count], YES, 0.0);
        });
    }];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { sck_log(@"app -> resignActive"); }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { sck_log(@"app -> willEnterForeground"); }];
    [nc addObserverForName:UIApplicationProtectedDataDidBecomeAvailable object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { sck_log(@"protectedData available"); }];
    [nc addObserverForName:UIApplicationProtectedDataWillBecomeUnavailable object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { sck_log(@"protectedData unavailable"); }];
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    gTimer = [NSTimer scheduledTimerWithTimeInterval:20.0 repeats:YES block:^(NSTimer *t) {
        sck_ensure_audio();
        static int hb = 0;
        if (++hb % 3 == 0) sck_log(@"HB state=%@ audio=%d battery=%.2f", sck_app_state(), gPlayer.isPlaying, [UIDevice currentDevice].batteryLevel);
    }];
    sck_log(@"setup done");
}

#pragma mark - entry

__attribute__((constructor)) static void sck_init(void) {
    @autoreleasepool {
        gLock = [NSLock new];
        gOrig = [NSMutableDictionary new];
        gThrottle = [NSMutableDictionary new];
        gNameCache = [NSMutableDictionary new];
        sck_scan();
        dispatch_async(dispatch_get_main_queue(), ^{ sck_setup(); });
    }
}
