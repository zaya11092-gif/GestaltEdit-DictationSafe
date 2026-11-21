//
//  EligibilityAccess.h
//  GestaltEdit
//
//  Uses the same worse_query lease as GestaltAccess, targeted at
//  /var/db/eligibilityd, to read and write the OS Eligibility override
//  plist (eligibility.plist) that gates the Apple Intelligence feature
//  domains (GreyMatter) independently of MobileGestalt.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EligibilityAccess : NSObject

+ (instancetype)shared;

/// Acquires a worse_query lease on /var/db/eligibilityd and verifies access.
/// Idempotent. Fails cleanly with EACCES surfaced in the error when the
/// directory is not writable by the app sandbox on this build.
- (BOOL)connectWithError:(NSError **)error;

/// YES when eligibility.plist exists in the leased directory.
- (BOOL)eligibilityFileExists;

/// Reads the live eligibility.plist, or nil when it does not exist.
- (nullable NSDictionary *)readEligibilityWithError:(NSError **)error;
- (nullable NSData *)readEligibilityDataWithError:(NSError **)error;

/// Rewrites eligibility.plist (created when absent, mode 0644) and verifies
/// the bytes on disk afterwards.
- (BOOL)saveEligibility:(NSDictionary *)plist error:(NSError **)error;

/// Removes eligibility.plist (only used to revert an override when no
/// pre-existing file was backed up).
- (BOOL)removeEligibilityWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
