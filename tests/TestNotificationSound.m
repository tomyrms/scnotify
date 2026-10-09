#import <Foundation/Foundation.h>
#import "../Sources/SNNotificationSound.h"
#import "../Sources/SNSnapchatSoundData.h"
#include <stdlib.h>
#define CHECK(...) do { if (!(__VA_ARGS__)) { NSLog(@"FAILED notification sound line %d", __LINE__); abort(); } } while (0)

int main(void) { @autoreleasepool {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *sounds = [root stringByAppendingPathComponent:@"Library/Sounds"];
    NSData *expected = [NSData dataWithBytes:SNSnapchatSoundBytes length:sizeof(SNSnapchatSoundBytes)];
    NSError *error = nil;

    /* First launch creates nested directories and installs the exact asset. */
    NSString *name = SNInstallSnapchatNotificationSound(sounds, &error);
    CHECK(name != nil && error == nil);
    CHECK([name isEqualToString:@(SN_SNAPCHAT_SOUND_FILENAME)]);
    CHECK([name isEqualToString:name.lastPathComponent] && [name.pathExtension isEqualToString:@"wav"]);
    NSString *path = [sounds stringByAppendingPathComponent:name];
    CHECK([[NSData dataWithContentsOfFile:path] isEqualToData:expected]);

    /* Repeated initialization preserves the existing matching file. */
    NSDate *oldDate = [NSDate dateWithTimeIntervalSince1970:1000000000];
    CHECK([files setAttributes:@{NSFileModificationDate: oldDate} ofItemAtPath:path error:&error]);
    NSDictionary *before = [files attributesOfItemAtPath:path error:&error];
    error = [NSError errorWithDomain:@"stale" code:1 userInfo:nil];
    CHECK([SNInstallSnapchatNotificationSound(sounds, &error) isEqualToString:name] && error == nil);
    NSDictionary *after = [files attributesOfItemAtPath:path error:&error];
    CHECK([before[NSFileModificationDate] isEqual:after[NSFileModificationDate]]);
    CHECK([[NSData dataWithContentsOfFile:path] isEqualToData:expected]);

    /* A damaged or replaced file is repaired, with an unchanged sound name. */
    CHECK([[@"incorrect bytes" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
    CHECK([SNInstallSnapchatNotificationSound(sounds, &error) isEqualToString:name] && error == nil);
    CHECK([[NSData dataWithContentsOfFile:path] isEqualToData:expected]);

    /* Filesystem failures are reported; they never return a usable filename. */
    NSString *blocked = [root stringByAppendingPathComponent:@"blocked"];
    CHECK([[NSData data] writeToFile:blocked atomically:YES]);
    CHECK(SNInstallSnapchatNotificationSound(blocked, &error) == nil && error != nil);
    CHECK(SNInstallSnapchatNotificationSound(@"relative/Sounds", &error) == nil && error != nil);
    CHECK(SNInstallSnapchatNotificationSound(@"", NULL) == nil);
    CHECK(SNInstallSnapchatNotificationSound(sounds, NULL) != nil);

    NSString *otherSounds = [root stringByAppendingPathComponent:@"other/Sounds"];
    NSString *blockedSound = [otherSounds stringByAppendingPathComponent:name];
    CHECK([files createDirectoryAtPath:blockedSound withIntermediateDirectories:YES attributes:nil error:&error]);
    CHECK(SNInstallSnapchatNotificationSound(otherSounds, &error) == nil && error != nil);
    BOOL stillDirectory = NO;
    CHECK([files fileExistsAtPath:blockedSound isDirectory:&stillDirectory] && stillDirectory);

    CHECK([files removeItemAtPath:root error:&error]);
    NSLog(@"Notification sound tests passed");
    return 0;
} }
