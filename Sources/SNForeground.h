#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN
/* Preserve the delegate's existing callback for host notifications. Only our
   scnotify-marked notifications receive the supplied presentation options.
   An inherited callback is overridden on this class, never on its superclass.
   A missing optional callback is supplied with the default (no presentation)
   behavior for unmarked notifications. Both functions are idempotent. */
BOOL SNInstallForegroundDelegate(Class _Nullable delegateClass, NSUInteger options);
/* Prepare each real delegate BEFORE the original setDelegate: caches optional
   protocol methods. The caller must also prepare any already assigned delegate. */
BOOL SNInstallForegroundCenter(Class _Nullable centerClass, NSUInteger options);
NS_ASSUME_NONNULL_END
