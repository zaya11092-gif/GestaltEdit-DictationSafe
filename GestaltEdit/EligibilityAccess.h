//
//  EligibilityAccess.h
//  GestaltEdit
//
//  Uses the same worse_query lease as GestaltAccess, targeted at an
//  arbitrary directory, to read and write OS Eligibility data.
//
//  Two targets matter:
//  - the systemgroup.com.apple.oseligibilityservice container — a REAL
//    systemgroup container (the exact path class the lease works on, proven
//    by the MobileGestalt target) whose contents are uncharted;
//  - /var/db/eligibilityd — the classic AI eligibility store, which
//    containermanagerd rejects on iOS 27.2.1 (code -6, not a container).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EligibilityAccess : NSObject

- (instancetype)initWithWorseQueryTarget:(NSString *)worseQueryTarget
                          plistDirectory:(NSString *)plistDirectory
                                fileName:(NSString *)fileName
                             displayName:(NSString *)displayName NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSString *displayName;

/// Acquires a worse_query lease on the target directory and verifies access.
/// Idempotent. Fails cleanly with the system reason surfaced in the error.
- (BOOL)connectWithError:(NSError **)error;

/// YES when the target plist exists.
- (BOOL)plistFileExists;

/// Lists the file names in the leased directory (nil on failure).
- (nullable NSArray<NSString *> *)listFilesWithError:(NSError **)error;

/// Lists the file names inside a subdirectory of the leased directory
/// (nil on failure). Pass nil for the leased directory itself.
///
/// The asset system keeps downloaded bundles one level down, inside
/// `purpose_auto/`, so a root listing reports "no .asset bundles" while the
/// model is fully present underneath. `subdirectory` must be a relative path
/// inside the leased directory; absolute paths and ".." are rejected.
- (nullable NSArray<NSString *> *)listFilesInSubdirectory:(nullable NSString *)subdirectory
                                                    error:(NSError **)error;

/// Reads the live plist, or nil when it does not exist.
- (nullable NSDictionary *)readPlistWithError:(NSError **)error;
- (nullable NSData *)readDataWithError:(NSError **)error;

/// Rewrites the plist (created when absent, mode 0644) and verifies the
/// bytes on disk afterwards.
- (BOOL)savePlist:(NSDictionary *)plist error:(NSError **)error;

/// Removes the plist (only used to revert an override when no pre-existing
/// file was backed up).
- (BOOL)removePlistWithError:(NSError **)error;

/// Renames an entry inside the leased directory (used to disable model
/// asset directories reversibly — hide from the asset system, restore by
/// renaming back). Both names are plain file names within the directory.
- (BOOL)renameEntry:(NSString *)name toName:(NSString *)newName
              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
