#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/* Only call for a payload supplied to an explicit in-app presentation path.
   It copies the host's text, never classifies words in a message body. */
NSDictionary * _Nullable SNHostNotice(id _Nullable payload);
/* Read a bounded JSON object from an actual incoming transport callback.
   Opaque protobuf/encrypted data remains unsupported, not a fake event. */
id _Nullable SNTransportJSON(id _Nullable payload);
/* Signature-checked observation of the in-app arm of the observed
   SCNotificationDisplayModel union. The system arm is left untouched. */
typedef void (^SNNoticeObserver)(id payload);
BOOL SNInstallNoticeChoice(Class cls, SNNoticeObserver observer);
/* Exposed for native regression tests; nil for incompatible block ABIs. */
id _Nullable SNWrapNoticeBlock(id _Nullable block, SNNoticeObserver observer);
NS_ASSUME_NONNULL_END
