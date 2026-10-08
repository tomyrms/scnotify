#import "SNContent.h"
#import "SNRuntime.h"
#include <math.h>

static BOOL flag(id object, NSString *key) {
    id v=SNRead(object,key);
    return [v isKindOfClass:NSNumber.class]&&[v boolValue];
}
NSString *SNContentSubtype(id message,id content) {
    /* These semantic getters are present in the supplied iPhone schema. A
       getter not implemented by another build is simply absent, not false
       evidence for another type. No media or private message body is read. */
    if(flag(message,@"isVoiceNote"))return @"voice";
    if(flag(message,@"isStickerMessage")||flag(message,@"isBitmojiSticker")||flag(message,@"isBloopMessage"))return @"sticker";
    if(flag(message,@"isStoryReplyMessage"))return @"story_reply";
    if(flag(message,@"isSingleImageChatMedia")||flag(message,@"isSingleNonSpectaclesImageChatMedia"))return @"photo";
    if(flag(message,@"isChatMediaMessage")||flag(message,@"isSingleImageOrVideoChatMedia"))return @"media";
    if(flag(message,@"isContentShareMessage")||flag(message,@"isSpotlightStoryShareMessage")||flag(message,@"isSpotlightCommentShareMessage")||flag(message,@"isBitmojiUserShare"))return @"share";
    for(id owner in @[message?:NSNull.null,content?:NSNull.null])for(NSString *key in @[@"eventType",@"messageType",@"contentType"]) {
        id v=SNRead(owner,key);if(![v isKindOfClass:NSString.class])continue;
        NSString *symbol=[v uppercaseString];
        for(NSString *prefix in @[@"MESSAGING_CONTENT_TYPE_",@"CONTENT_TYPE_",@"CONTENTTYPE_"])if([symbol hasPrefix:prefix]){symbol=[symbol substringFromIndex:prefix.length];break;}
        if([@[@"NOTE",@"AUDIO_NOTE",@"VOICE_NOTE"] containsObject:symbol])return @"voice";
        if([symbol isEqual:@"STICKER"])return @"sticker";
        if([symbol isEqual:@"EXTERNAL_MEDIA"])return @"media";
        if([symbol isEqual:@"SHARE"])return @"share";
        if([symbol isEqual:@"LOCATION"])return @"location";
    }
    return @"text";
}
NSString *SNNotificationBody(NSDictionary *event,NSString *name) {
    NSString *who=name.length?name:@"Un contact";
    NSString *kind=event[@"kind"];
    if([kind isEqual:@"typing"])return [who stringByAppendingString:@" est en train d’écrire…"];
    if([kind isEqual:@"peek"])return [who stringByAppendingString:@" entrouvre la conversation"];
    if([kind isEqual:@"snap"])return [who stringByAppendingString:@" t’a envoyé un snap"];
    if([kind isEqual:@"call"])return [who stringByAppendingString:[event[@"video"] boolValue]?@" t’appelle en vidéo":@" t’appelle"];
    NSDictionary *suffixes=@{@"voice":@" t’a envoyé un message vocal",@"photo":@" t’a envoyé une photo dans le chat",@"media":@" t’a envoyé un média dans le chat",@"sticker":@" t’a envoyé un sticker",@"share":@" a partagé du contenu avec toi",@"story_reply":@" a répondu à ta story",@"location":@" a partagé une position avec toi"};
    return [who stringByAppendingString:suffixes[event[@"subtype"]?:@""]?:@" t’a envoyé un message"];
}
@interface SNRemoteParticipants ()
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *observed;
@end
@implementation SNRemoteParticipants
- (instancetype)init {self=[super init];if(self)_observed=[NSMutableDictionary dictionary];return self;}
- (void)observeUser:(NSString *)uid conversation:(NSString *)cid atTime:(double)now {
    if(!SNIdentifier(uid)||!SNIdentifier(cid)||!isfinite(now)||now<0)return;
    NSString *key=[@[cid,uid] componentsJoinedByString:@"|"];
    if(!self.observed[key]&&self.observed.count>=4096){
        NSString *oldest=nil;double first=INFINITY;
        for(NSString *k in self.observed)if(self.observed[k].doubleValue<first){first=self.observed[k].doubleValue;oldest=k;}
        if(oldest)[self.observed removeObjectForKey:oldest];
    }
    self.observed[key]=@(now);
}
- (BOOL)containsUser:(NSString *)uid conversation:(NSString *)cid atTime:(double)now {
    if(!uid||!cid||!isfinite(now))return NO;
    NSString *key=[@[cid,uid] componentsJoinedByString:@"|"];NSNumber *seen=self.observed[key];
    if(!seen||now<seen.doubleValue)return NO;
    if(now-seen.doubleValue>86400){[self.observed removeObjectForKey:key];return NO;}
    return YES;
}
- (void)reset {[self.observed removeAllObjects];}
@end
