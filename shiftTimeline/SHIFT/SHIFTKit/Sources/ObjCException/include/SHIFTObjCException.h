#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executes `block` and converts any `NSException` thrown within into an
/// `NSError` return value so Swift can catch it.
///
/// SwiftData's `ModelContainer(for:migrationPlan:configurations:)` can throw
/// Objective-C exceptions out of `NSLightweightMigrationStage` when the
/// on-disk store's schema checksum doesn't match any known `VersionedSchema`.
/// Swift's `do/catch` cannot catch `NSException`, so without this shim the
/// process aborts with SIGABRT. Using `@try/@catch` here converts the
/// exception into a recoverable error and lets callers delete the store
/// and retry.
FOUNDATION_EXPORT BOOL SHIFTTryBlock(void (NS_NOESCAPE ^block)(void),
                                     NSError * _Nullable * _Nullable outError);

NS_ASSUME_NONNULL_END
