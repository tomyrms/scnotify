#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/* Only call for a payload supplied to an explicit in-app presentation path.
   It copies the host's text, never classifies words in a message body.
   Output has title/body and either a stable host id or a localID. The latter
   distinguishes equal text on separate host objects, while sharing an identity
   across overlapping callbacks for the same text-bearing object for up to 1s.
   A changed text snapshot gets a new localID. Do not deduplicate by text alone. */
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
