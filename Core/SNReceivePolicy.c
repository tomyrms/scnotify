#include "SNReceivePolicy.h"
#include <string.h>
#include <math.h>
#include <ctype.h>

static bool one_of(const char *s, const char *const *items) {
    if (!s) return false;
    for (unsigned i=0; items[i]; ++i) if (!strcmp(s,items[i])) return true;
    return false;
}
SNReceiveKind sn_receive_kind(const char *symbol) {
    if (!symbol) return SN_RX_NONE;
    size_t n=strnlen(symbol,128);
    if (!n || n>=128) return SN_RX_NONE;
    char text[128];
    for (size_t i=0;i<n;++i) {
        unsigned char c=(unsigned char)symbol[i];
        if (!(isalnum(c)||c=='_')) return SN_RX_NONE;
        text[i]=(char)toupper(c);
    }
    text[n]=0;const char *s=text;
    /* Protobuf textFormatName/enumName can prepend the enum type. */
    const char *const prefixes[]={"MESSAGING_CONTENT_TYPE_","CONTENT_TYPE_","CONTENTTYPE_",NULL};
    for(unsigned i=0;prefixes[i];i++)if(!strncmp(s,prefixes[i],strlen(prefixes[i]))){s+=strlen(prefixes[i]);break;}
    const char *const snaps[]={"SNAP","RECEIVED_SNAP","SNAP_RECEIVED",NULL};
    const char *const chats[]={"CHAT","TEXT","CHAT_MESSAGE","RECEIVED_CHAT","RECEIVED_CHAT_MESSAGE","MESSAGE_RECEIVED","EXTERNAL_MEDIA","NOTE","AUDIO_NOTE","STICKER","SHARE","LOCATION",NULL};
    const char *const controls[]={"READ","READ_RECEIPT","DELIVERED","DELIVERY_RECEIPT","SNAP_OPENED","SNAP_STATE","TYPING","PRESENCE","CALLER_PUSH","SAVE","UNSAVE","ERASE","DELETE","DELETED","REPLAY","SCREENSHOT","SCREEN_RECORD","RELEASE","EDIT",NULL};
    if(one_of(s,snaps))return SN_RX_SNAP;
    if(one_of(s,chats))return SN_RX_MESSAGE;
    if(one_of(s,controls)||!strncmp(s,"STATUS",6)||!strncmp(s,"CALL_",5))return SN_RX_CONTROL;
    return SN_RX_NONE;
}
static bool component(const char *selector, char out[128]) {
    if(!selector)return false;
    const char *end=strchr(selector,':');size_t n=end?(size_t)(end-selector):strlen(selector);
    if(!n||n>=128)return false;memcpy(out,selector,n);out[n]=0;return true;
}
SNReceiveSource sn_receive_source(const char *cls,const char *selector) {
    if(!cls||!selector)return SN_SOURCE_NONE;
    if(!strcmp(cls,"SCNativeBlizzardLoggerDelegateImpl"))return SN_SOURCE_NONE;
    /* App classes only, never Foundation/UIKit notification plumbing. */
    if(strncmp(cls,"SC",2)&&strncmp(cls,"SOJU",4))return SN_SOURCE_NONE;
    const char *const contextual[]={"conversation:didReceiveMessage:","conversation:didReceiveMessages:","conversationId:didReceiveMessage:","conversationId:didReceiveMessages:",NULL};
    if(one_of(selector,contextual))return SN_SOURCE_LIVE;
    char first[128];if(!component(selector,first))return SN_SOURCE_NONE;
    const char *const live[]={"didReceiveSnap","didReceiveChatMessage","didReceiveMessage","didReceiveMessages","didReceiveNewMessage","onMessageReceived","onMessagesReceived","didReceiveMessageNotification",NULL};
    if(one_of(first,live))return SN_SOURCE_LIVE;
    const char *const snapshots[]={"onNewMessage","onNewMessages","onMessageAdded","onMessagesAdded","onConversationUpdated","onConversationsUpdated","onConversationUpdate","onConversationFeedUpdated","onMessageUpdated","onMessagesUpdated","onConversationMessagesUpdated","didUpdateMessages","didConversationViewModelChange",NULL};
    bool role=strstr(cls,"Listener")||strstr(cls,"Observer")||strstr(cls,"Announcer")||strstr(cls,"Handler")||strstr(cls,"Callback");
    bool domain=strstr(cls,"Message")||strstr(cls,"Messaging")||strstr(cls,"Conversation");
    if(role&&domain&&one_of(first,snapshots))return SN_SOURCE_SNAPSHOT;
    /* Exact in-app presentation entry points from the provided v3 log. They
       are only additional structured-message sources, never text heuristics. */
    if((!strcmp(cls,"SCDefaultInAppNotificationPresentingPlugin")||!strcmp(cls,"SCInAppNotificationController"))&&
       (!strcmp(first,"presentInAppNotification")||!strcmp(first,"presentInAppNotificationAsync")))return SN_SOURCE_LIVE;
    return SN_SOURCE_NONE;
}
SNReceiveKind sn_receive_hint(const char *selector) {
    char first[128];if(!component(selector,first))return SN_RX_NONE;
    if(!strcmp(first,"didReceiveSnap"))return SN_RX_SNAP;
    if(!strcmp(first,"didReceiveChatMessage"))return SN_RX_MESSAGE;
    return SN_RX_NONE;
}
double sn_receive_seconds(double t) {
    if(!isfinite(t)||t<=0)return NAN;
    if(t>=1e17)t/=1e9;
    else if(t>=1e14)t/=1e6;
    else if(t>=1e11)t/=1e3;
    return t;
}
bool sn_receive_time_valid(double t,double now) {
    return isfinite(t)&&isfinite(now)&&t>0&&now>0&&now-t<=300&&t-now<=60;
}

SNReceiveKind sn_receive_native_content_kind(const char *cls,const char *version,int64_t raw) {
    if(!cls||!version||strcmp(cls,"SCNMessagingMessageContent")||strcmp(version,"14.17.1"))return SN_RX_NONE;
    /* Public content enum reference: SNAP=0, CHAT=1 (see SOURCES_RC4.md).
       Other numeric types are intentionally NOT enabled by this compatibility
       path; their native semantic predicates can still recognize them. */
    if(raw==0)return SN_RX_SNAP;
    if(raw==1)return SN_RX_MESSAGE;
    return SN_RX_NONE;
}
