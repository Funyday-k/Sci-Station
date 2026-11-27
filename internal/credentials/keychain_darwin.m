//go:build darwin && cgo

#import <Foundation/Foundation.h>
#import <Security/Security.h>

// Keep the user's default file-based Keychain for the ad-hoc signed app.
// The ThisDeviceOnly accessibility classes require the data-protection
// Keychain, which needs an authorized access group. File-based items are
// outside iCloud Keychain sync and retain the file-based backup behavior.
static NSDictionary *credentialQuery(const char *account) {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.funyday.scistation.desktop.credentials",
        (__bridge id)kSecAttrAccount: [NSString stringWithUTF8String:account],
    };
}

OSStatus sciCredentialStatus(const char *account) {
    @autoreleasepool {
        NSMutableDictionary *query = [credentialQuery(account) mutableCopy];
        query[(__bridge id)kSecReturnAttributes] = @YES;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        CFTypeRef attributes = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &attributes);
        if (attributes != NULL) CFRelease(attributes);
        return status;
    }
}

OSStatus sciCredentialRead(const char *account, CFDataRef *value) {
    @autoreleasepool {
        NSMutableDictionary *query = [credentialQuery(account) mutableCopy];
        query[(__bridge id)kSecReturnData] = @YES;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        CFTypeRef match = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &match);
        if (status != errSecSuccess) return status;
        if (match == NULL) return errSecDecode;
        if (CFGetTypeID(match) != CFDataGetTypeID()) {
            CFRelease(match);
            return errSecDecode;
        }
        *value = (CFDataRef)match;
        return errSecSuccess;
    }
}

OSStatus sciCredentialSave(const char *account, const void *bytes, size_t length) {
    @autoreleasepool {
        NSDictionary *query = credentialQuery(account);
        NSData *value = [NSData dataWithBytes:bytes length:length];
        NSDictionary *update = @{(__bridge id)kSecValueData: value};
        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
        if (status != errSecItemNotFound) return status;

        NSMutableDictionary *entry = [query mutableCopy];
        [entry addEntriesFromDictionary:update];
        status = SecItemAdd((__bridge CFDictionaryRef)entry, NULL);
        if (status == errSecDuplicateItem) {
            return SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
        }
        return status;
    }
}

OSStatus sciCredentialDelete(const char *account) {
    @autoreleasepool {
        return SecItemDelete((__bridge CFDictionaryRef)credentialQuery(account));
    }
}
