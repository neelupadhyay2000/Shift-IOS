#import "SHIFTObjCException.h"

BOOL SHIFTTryBlock(void (NS_NOESCAPE ^block)(void),
                   NSError * _Nullable * _Nullable outError) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (outError) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            userInfo[@"SHIFTExceptionName"] = exception.name;
            if (exception.userInfo) {
                userInfo[@"SHIFTExceptionUserInfo"] = exception.userInfo;
            }
            *outError = [NSError errorWithDomain:@"com.shift.ObjCException"
                                            code:-1
                                        userInfo:userInfo];
        }
        return NO;
    }
}
