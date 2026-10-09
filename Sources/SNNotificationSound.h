#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/* Installs the bundled Snapchat alert in the caller's Library/Sounds directory.
   Returns the basename to pass to UNNotificationSound, or nil with an error.
   This does not play audio or change the application's audio session. */
NSString * _Nullable SNInstallSnapchatNotificationSound(
    NSString *soundsDirectory, NSError * _Nullable * _Nullable error);
NS_ASSUME_NONNULL_END
