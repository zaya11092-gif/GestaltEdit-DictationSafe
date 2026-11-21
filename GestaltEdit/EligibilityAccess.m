//
//  EligibilityAccess.m
//  GestaltEdit
//
//  worse_query lease targeted at /var/db/eligibilityd for the OS Eligibility
//  override plist. Mirrors GestaltAccess.m with three differences: the target
//  directory, creation of the plist when absent, and file removal for
//  reverts.
//

#import "EligibilityAccess.h"
#import "worse_query.h"
#import "GestaltAppGroupResolver.h"

#import <CoreFoundation/CoreFoundation.h>
#import <errno.h>
#import <fcntl.h>
#import <mach/mach_init.h>
#import <unistd.h>

static NSString * const kEligibilityDirectory =
    @"/private/var/db/eligibilityd";
static NSString * const kWorseQueryEligibilityDirectory =
    @"/var/db/eligibilityd";
static NSString * const kEligibilityFileName = @"eligibility.plist";

static NSError *EligibilityError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"com.gestaltedit.eligibility"
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static BOOL EligibilityCanOpenReadWrite(NSString *path)
{
    int fd = open(path.fileSystemRepresentation,
                  O_RDWR | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return NO;
    close(fd);
    return YES;
}

static BOOL EligibilityWriteAll(int fd, NSData *data)
{
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(fd, bytes, remaining);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return NO;
        bytes += written;
        remaining -= (NSUInteger)written;
    }
    return YES;
}

@interface EligibilityAccess ()
@property (nonatomic, assign) BOOL isConnected;
@end

@implementation EligibilityAccess
{
    int64_t _sandboxHandle;
    BOOL _hasSandboxHandle;
}

+ (instancetype)shared
{
    static EligibilityAccess *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [EligibilityAccess new]; });
    return shared;
}

+ (BOOL)supportsDeviceAccess
{
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27;
}

- (BOOL)connectWithError:(NSError **)error
{
    @synchronized (self) {
        if (!EligibilityAccess.supportsDeviceAccess) {
            if (error) *error = EligibilityError(10, NSLocalizedString(@"Eligibility editing requires iOS / iPadOS 27 or later.", nil));
            return NO;
        }

        if (_hasSandboxHandle && self.isConnected &&
            EligibilityCanOpenReadWrite([kEligibilityDirectory stringByAppendingPathComponent:kEligibilityFileName])) {
            return YES;
        }
        // A missing file is fine here (the override creates it), so verify
        // access through the directory itself as well.
        if (_hasSandboxHandle && self.isConnected) {
            int dfd = open(kEligibilityDirectory.fileSystemRepresentation,
                           O_RDONLY | O_CLOEXEC | O_DIRECTORY);
            if (dfd >= 0) { close(dfd); return YES; }
        }

        if (_hasSandboxHandle) worse_query_release(_sandboxHandle);
        _hasSandboxHandle = NO;
        self.isConnected = NO;

        NSArray<NSString *> *groups = [GestaltAppGroupResolver usableAppGroups];
        if (groups.count == 0) {
            if (error) *error = EligibilityError(1, NSLocalizedString(@"No usable App Group was found in the app signature.", nil));
            return NO;
        }

        NSMutableArray<NSString *> *attempts = [NSMutableArray array];
        for (NSString *group in groups) {
            for (NSUInteger variant = 0; variant < 2; ++variant) {
                errno = 0;
                int64_t handle = worse_query(kWorseQueryEligibilityDirectory, group, variant != 0, false);
                int savedErrno = errno;
                if (handle >= 0) {
                    // The plist may legitimately not exist yet; the directory
                    // lease itself is what matters.
                    int dfd = open(kEligibilityDirectory.fileSystemRepresentation,
                                   O_RDONLY | O_CLOEXEC | O_DIRECTORY);
                    BOOL directoryReachable = dfd >= 0;
                    if (directoryReachable) close(dfd);
                    BOOL plistReachable = EligibilityCanOpenReadWrite([kEligibilityDirectory stringByAppendingPathComponent:kEligibilityFileName]);
                    if (directoryReachable || plistReachable) {
                        _sandboxHandle = handle;
                        _hasSandboxHandle = YES;
                        self.isConnected = YES;
                        if (error) *error = nil;
                        return YES;
                    }
                    savedErrno = errno;
                    worse_query_release(handle);
                    handle = -9;
                }
                [attempts addObject:[NSString stringWithFormat:@"%lu/%lu: code=%lld, errno=%d (%@)",
                    (unsigned long)variant + 1, (unsigned long)([groups indexOfObject:group] + 1),
                    (long long)handle, savedErrno,
                    NSLocalizedString(@"The system rejected the eligibility query.", nil)]];
            }
        }
        if (error) *error = EligibilityError(2, [NSString stringWithFormat:NSLocalizedString(@"Eligibility access failed:\n%@", nil), [attempts componentsJoinedByString:@"\n"]]);
        return NO;
    }
}

- (BOOL)eligibilityFileExists
{
    return [[NSFileManager defaultManager] fileExistsAtPath:
        [kEligibilityDirectory stringByAppendingPathComponent:kEligibilityFileName]];
}

- (NSData *)readEligibilityDataWithError:(NSError **)error
{
    if (![self connectWithError:error]) return nil;
    NSString *path = [kEligibilityDirectory stringByAppendingPathComponent:kEligibilityFileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) *error = nil;
        return nil;
    }
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&readError];
    if (!data) {
        if (error) *error = readError ?: EligibilityError(4, NSLocalizedString(@"Failed to read the eligibility plist.", nil));
        return nil;
    }
    if (error) *error = nil;
    return data;
}

- (NSDictionary *)readEligibilityWithError:(NSError **)error
{
    NSData *data = [self readEligibilityDataWithError:error];
    if (!data) {
        // Distinguish "absent" (nil data, no error) from real failures.
        if (error && *error == nil) return nil;
        return nil;
    }
    NSError *parseError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:0
                                                          format:nil
                                                          error:&parseError];
    if (![plist isKindOfClass:NSDictionary.class]) {
        if (error) *error = parseError ?: EligibilityError(5, NSLocalizedString(@"The eligibility plist top level is not a dictionary.", nil));
        return nil;
    }
    return (NSDictionary *)plist;
}

- (BOOL)saveEligibility:(NSDictionary *)plist error:(NSError **)error
{
    if (![self connectWithError:error]) return NO;
    if (![plist isKindOfClass:NSDictionary.class]) {
        if (error) *error = EligibilityError(6, NSLocalizedString(@"The content to save is not a dictionary.", nil));
        return NO;
    }

    NSError *serializeError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&serializeError];
    if (!data) {
        if (error) *error = serializeError ?: EligibilityError(7, NSLocalizedString(@"Failed to serialize the eligibility plist.", nil));
        return NO;
    }

    NSString *targetPath = [kEligibilityDirectory stringByAppendingPathComponent:kEligibilityFileName];
    NSString *originalPath = targetPath;
    NSData *original = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:originalPath]) {
        NSError *readError = nil;
        original = [NSData dataWithContentsOfFile:originalPath options:0 error:&readError];
    }

    // Create when absent; the lease grants directory access and the file is
    // created owned by mobile with standard perms.
    int fd = open(targetPath.fileSystemRepresentation,
                  O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
                  0644);
    if (fd < 0) {
        if (error) *error = EligibilityError(9,
            [NSString stringWithFormat:NSLocalizedString(@"Failed to open the eligibility plist for writing (errno=%d). If this is a permission error, /var/db/eligibilityd is not writable by the app sandbox on this build and the override cannot be applied.", nil), errno]);
        return NO;
    }

    BOOL wrote = EligibilityWriteAll(fd, data) && fsync(fd) == 0;
    int writeErrno = errno;

    if (!wrote) {
        if (original) {
            ftruncate(fd, 0);
            lseek(fd, 0, SEEK_SET);
            EligibilityWriteAll(fd, original);
            fsync(fd);
        }
        close(fd);
        if (error) *error = EligibilityError(10,
            [NSString stringWithFormat:NSLocalizedString(@"Failed to write the eligibility plist (errno=%d).", nil), writeErrno]);
        return NO;
    }
    close(fd);

    NSData *verification = [NSData dataWithContentsOfFile:targetPath];
    if (![verification isEqualToData:data]) {
        if (error) *error = EligibilityError(11, NSLocalizedString(@"Post-write verification failed for the eligibility plist.", nil));
        return NO;
    }

    if (error) *error = nil;
    return YES;
}

- (BOOL)removeEligibilityWithError:(NSError **)error
{
    if (![self connectWithError:error]) return NO;
    NSString *targetPath = [kEligibilityDirectory stringByAppendingPathComponent:kEligibilityFileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
        if (error) *error = nil;
        return YES;
    }
    if (![[NSFileManager defaultManager] removeItemAtPath:targetPath error:error]) {
        return NO;
    }
    if (error) *error = nil;
    return YES;
}

@end
