#import "SNNotificationSound.h"
#import "SNSnapchatSoundData.h"
#import <TargetConditionals.h>

NSString *SNInstallSnapchatNotificationSound(NSString *soundsDirectory, NSError **error) {
    if (error) *error = nil;
    if (soundsDirectory.length == 0 || !soundsDirectory.isAbsolutePath) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
            code:NSFileWriteInvalidFileNameError
            userInfo:@{NSLocalizedDescriptionKey: @"The notification sounds directory must be an absolute path."}];
        return nil;
    }

    NSString *name = @(SN_SNAPCHAT_SOUND_FILENAME);
    NSString *path = [soundsDirectory stringByAppendingPathComponent:name];
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:soundsDirectory
        withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    NSData *expected = [NSData dataWithBytes:SNSnapchatSoundBytes length:sizeof(SNSnapchatSoundBytes)];
    NSData *existing = [NSData dataWithContentsOfFile:path];
    if (![existing isEqualToData:expected]) {
        NSDataWritingOptions options = NSDataWritingAtomic;
#if TARGET_OS_IPHONE
        options |= NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
        if (![expected writeToFile:path options:options error:error]) return nil;
    }
#if TARGET_OS_IPHONE
    /* Also repair protection on an already matching file, so locking the
       device after its first unlock does not make this alert inaccessible. */
    if (![files setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
        ofItemAtPath:path error:error]) return nil;
#endif
    return name;
}
