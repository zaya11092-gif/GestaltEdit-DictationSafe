//
//  EligibilityAccess.m
//  GestaltEdit
//
//  worse_query lease targeted at an arbitrary directory for OS Eligibility
//  data. Mirrors GestaltAccess.m with four differences: the target is a
//  parameter, the plist may be created when absent, directory listing for
//  discovery, and file removal for reverts.
//

#import "EligibilityAccess.h"
#import "worse_query.h"
#import "GestaltAppGroupResolver.h"

#import <CoreFoundation/CoreFoundation.h>
#import <errno.h>
#import <fcntl.h>
#import <mach/mach_init.h>
#import <unistd.h>

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
@property (nonatomic, copy) NSString *worseQueryTarget;
@property (nonatomic, copy) NSString *plistDirectory;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, assign) BOOL isConnected;
@end

@implementation EligibilityAccess
{
    int64_t _sandboxHandle;
    BOOL _hasSandboxHandle;
}

- (instancetype)initWithWorseQueryTarget:(NSString *)worseQueryTarget
                          plistDirectory:(NSString *)plistDirectory
                                fileName:(NSString *)fileName
                             displayName:(NSString *)displayName
{
    self = [super init];
    if (self) {
        _worseQueryTarget = [worseQueryTarget copy];
        _plistDirectory = [plistDirectory copy];
        _fileName = [fileName copy];
        _displayName = [displayName copy];
    }
    return self;
}

- (NSString *)plistPath
{
    return [self.plistDirectory stringByAppendingPathComponent:self.fileName];
}

- (BOOL)connectWithError:(NSError **)error
{
    @synchronized (self) {
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27) {
            if (error) *error = EligibilityError(10, NSLocalizedString(@"Eligibility editing requires iOS / iPadOS 27 or later.", nil));
            return NO;
        }

        if (_hasSandboxHandle && self.isConnected) {
            // Re-verify cheaply: the directory must still be openable.
            int dfd = open(self.plistDirectory.fileSystemRepresentation,
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
        for (NSUInteger index = 0; index < groups.count; ++index) {
            for (NSUInteger variant = 0; variant < 2; ++variant) {
                errno = 0;
                int64_t handle = worse_query(self.worseQueryTarget, groups[index], variant != 0, false);
                int savedErrno = errno;
                if (handle >= 0) {
                    // The plist may legitimately not exist yet; directory
                    // reachability through the lease is what matters.
                    int dfd = open(self.plistDirectory.fileSystemRepresentation,
                                   O_RDONLY | O_CLOEXEC | O_DIRECTORY);
                    BOOL directoryReachable = dfd >= 0;
                    if (directoryReachable) close(dfd);
                    if (directoryReachable) {
                        _sandboxHandle = handle;
                        _hasSandboxHandle = YES;
                        self.isConnected = YES;
                        if (error) *error = nil;
                        return YES;
                    }
                    worse_query_release(handle);
                    handle = -9;
                }
                [attempts addObject:[NSString stringWithFormat:@"%@ %lu/%lu: code=%lld, errno=%d",
                    self.worseQueryTarget, (unsigned long)(index + 1),
                    (unsigned long)(variant + 1), (long long)handle, savedErrno]];
            }
        }
        if (error) *error = EligibilityError(2, [NSString stringWithFormat:NSLocalizedString(@"Eligibility access failed:\n%@", nil), [attempts componentsJoinedByString:@"\n"]]);
        return NO;
    }
}

- (BOOL)plistFileExists
{
    return [[NSFileManager defaultManager] fileExistsAtPath:self.plistPath];
}

- (NSArray<NSString *> *)listFilesWithError:(NSError **)error
{
    if (![self connectWithError:error]) return nil;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.plistDirectory error:error];
    return [contents sortedArrayUsingSelector:@selector(compare:)];
}

- (NSData *)readDataWithError:(NSError **)error
{
    if (![self connectWithError:error]) return nil;
    if (![self plistFileExists]) {
        if (error) *error = EligibilityError(12, NSLocalizedString(@"The eligibility plist does not exist.", nil));
        return nil;
    }
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:self.plistPath options:NSDataReadingMappedIfSafe error:&readError];
    if (!data) {
        if (error) *error = readError ?: EligibilityError(4, NSLocalizedString(@"Failed to read the eligibility plist.", nil));
        return nil;
    }
    if (error) *error = nil;
    return data;
}

- (NSDictionary *)readPlistWithError:(NSError **)error
{
    NSData *data = [self readDataWithError:error];
    if (!data) return nil;
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

- (BOOL)savePlist:(NSDictionary *)plist error:(NSError **)error
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

    NSData *original = nil;
    if ([self plistFileExists]) {
        NSError *readError = nil;
        original = [NSData dataWithContentsOfFile:self.plistPath options:0 error:&readError];
    }

    int fd = open(self.plistPath.fileSystemRepresentation,
                  O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
                  0644);
    if (fd < 0) {
        if (error) *error = EligibilityError(9,
            [NSString stringWithFormat:NSLocalizedString(@"Failed to open the eligibility plist for writing (errno=%d). If this is a permission error, the target directory is not writable by the app sandbox on this build.", nil), errno]);
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

    NSData *verification = [NSData dataWithContentsOfFile:self.plistPath];
    if (![verification isEqualToData:data]) {
        if (error) *error = EligibilityError(11, NSLocalizedString(@"Post-write verification failed for the eligibility plist.", nil));
        return NO;
    }

    if (error) *error = nil;
    return YES;
}

- (BOOL)removePlistWithError:(NSError **)error
{
    if (![self connectWithError:error]) return NO;
    if (![self plistFileExists]) {
        if (error) *error = nil;
        return YES;
    }
    if (![[NSFileManager defaultManager] removeItemAtPath:self.plistPath error:error]) {
        return NO;
    }
    if (error) *error = nil;
    return YES;
}

- (BOOL)renameEntry:(NSString *)name toName:(NSString *)newName
              error:(NSError **)error
{
    if (![self connectWithError:error]) return NO;
    if (name.length == 0 || newName.length == 0 ||
        [name containsString:@"/"] || [newName containsString:@"/"]) {
        if (error) *error = EligibilityError(13, NSLocalizedString(@"Invalid entry name for rename.", nil));
        return NO;
    }
    NSString *from = [self.plistDirectory stringByAppendingPathComponent:name];
    NSString *to = [self.plistDirectory stringByAppendingPathComponent:newName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:from]) {
        if (error) *error = EligibilityError(14, NSLocalizedString(@"The entry to rename does not exist.", nil));
        return NO;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:to]) {
        if (error) *error = EligibilityError(15, NSLocalizedString(@"An entry with the new name already exists.", nil));
        return NO;
    }
    NSError *moveError = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:from toPath:to error:&moveError]) {
        if (error) *error = moveError ?: EligibilityError(16, NSLocalizedString(@"Failed to rename the entry.", nil));
        return NO;
    }
    if (error) *error = nil;
    return YES;
}

@end
