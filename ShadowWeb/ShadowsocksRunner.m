//
// Created by clowwindy on 14-2-27.
// Copyright (c) 2014 clowwindy. All rights reserved.
//

#import "ShadowsocksRunner.h"
#import "Profile.h"
#include "ssrcipher.h"
#include "defs.h"
#include <uv.h>

struct server_config * build_config_object(void) {
    Profile *profile = [ShadowsocksRunner battleFrontGetProfile];

    const char *protocol = profile.protocol.UTF8String;
    if (protocol && strcmp(protocol, "verify_sha1") == 0) {
        // LOGI("The verify_sha1 protocol is deprecate! Fallback to origin protocol.");
        protocol = NULL;
    }

    struct server_config *config = config_create();

    config->listen_port = DEFAULT_BIND_PORT;
    string_safe_assign(&config->method, profile.method.UTF8String);
    string_safe_assign(&config->remote_host, profile.server.UTF8String);
    config->remote_port = (unsigned short) profile.serverPort;
    string_safe_assign(&config->password, profile.password.UTF8String);
    string_safe_assign(&config->protocol, protocol);
    string_safe_assign(&config->protocol_param, profile.protocolParam.UTF8String);
    string_safe_assign(&config->obfs, profile.obfs.UTF8String);
    string_safe_assign(&config->obfs_param, profile.obfsParam.UTF8String);

    return config;
}

void ssr_main_loop(uv_loop_t *loop) {
    struct server_config *config = NULL;
    do {
        config = build_config_object();
        if (config == NULL) {
            break;
        }

        if (config->method == NULL || config->password==NULL || config->remote_host==NULL) {
            break;
        }

        //uv_loop_t *loop = uv_loop_new(); // uv_default_loop();
        listener_run(config, loop);
        //uv_loop_delete(loop);
    } while(0);

    config_release(config);
}

void ssr_stop(uv_loop_t *loop) {
    if (loop) {
        uv_stop(loop);
    }
}

@implementation ShadowsocksRunner {
}

+ (BOOL)settingsAreNotComplete {
    if ((![ShadowsocksRunner isUsingPublicServer]) &&
        ([[NSUserDefaults standardUserDefaults] stringForKey:kShadowsocksIPKey] == nil ||
         [[NSUserDefaults standardUserDefaults] stringForKey:kShadowsocksPortKey] == nil ||
         [[NSUserDefaults standardUserDefaults] stringForKey:kShadowsocksPasswordKey] == nil))
    {
        return YES;
    } else {
        return NO;
    }
}

uv_loop_t * loop = NULL;

+ (BOOL) runProxy {
    BOOL result = NO;
    if (![ShadowsocksRunner settingsAreNotComplete]) {
        loop = calloc(1, sizeof(uv_loop_t)); // TODO: memory leak fixing.
        uv_loop_init(loop);

        ssr_main_loop(loop);

        uv_loop_close(loop);
        // free(loop); loop = NULL;
        result = YES;
    } else {
#ifdef DEBUG
        NSLog(@"warning: settings are not complete");
#endif
    }
    return result;
}

+ (void) reloadConfig {
    if (![ShadowsocksRunner settingsAreNotComplete]) {
        ssr_stop(loop);
    }
}

+ (BOOL)openSSURL:(NSURL *)url {
    if (!url.host) {
        return NO;
    }
    NSString *urlString = [url absoluteString];
    int i = 0;
    NSString *errorReason = nil;
    while(i < 2) {
        if (i == 1) {
            NSData *data = [[NSData alloc] initWithBase64Encoding:url.host];
            NSString *decodedString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            urlString = decodedString;
        }
        i++;
        urlString = [urlString stringByReplacingOccurrencesOfString:@"ss://" withString:@"" options:NSAnchoredSearch range:NSMakeRange(0, urlString.length)];
        NSRange firstColonRange = [urlString rangeOfString:@":"];
        NSRange lastColonRange = [urlString rangeOfString:@":" options:NSBackwardsSearch];
        NSRange lastAtRange = [urlString rangeOfString:@"@" options:NSBackwardsSearch];
        if (firstColonRange.length == 0) {
            errorReason = @"colon not found";
            continue;
        }
        if (firstColonRange.location == lastColonRange.location) {
            errorReason = @"only one colon";
            continue;
        }
        if (lastAtRange.length == 0) {
            errorReason = @"at not found";
            continue;
        }
        if (!((firstColonRange.location < lastAtRange.location) && (lastAtRange.location < lastColonRange.location))) {
            errorReason = @"wrong position";
            continue;
        }

        Profile *profile = [[Profile alloc] init];

        profile.method = [urlString substringWithRange:NSMakeRange(0, firstColonRange.location)];
        profile.password = [urlString substringWithRange:NSMakeRange(firstColonRange.location + 1, lastAtRange.location - firstColonRange.location - 1)];
        profile.server = [urlString substringWithRange:NSMakeRange(lastAtRange.location + 1, lastColonRange.location - lastAtRange.location - 1)];
        profile.serverPort = [urlString substringWithRange:NSMakeRange(lastColonRange.location + 1, urlString.length - lastColonRange.location - 1)].integerValue;

        profile.protocol;
        profile.protocolParam;
        profile.obfs;
        profile.obfsParam;

        [ShadowsocksRunner battleFrontSaveProfile:profile];

        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kShadowsocksUsePublicServer];
        [ShadowsocksRunner reloadConfig];
        return YES;
    }

    NSLog(@"%@", errorReason);
    return NO;
}

+(NSURL *)generateSSURL {
    if ([ShadowsocksRunner isUsingPublicServer]) {
        return nil;
    }

    Profile *profile = [ShadowsocksRunner battleFrontGetProfile];

    NSString *parts = [NSString stringWithFormat:@"%@:%@@%@:%@",
                       profile.method,
                       profile.password,
                       profile.server,
                       [NSString stringWithFormat:@"%ld", (long)profile.serverPort]];

    profile.protocol;
    profile.protocolParam;
    profile.obfs;
    profile.obfsParam;

    NSString *base64String = [[parts dataUsingEncoding:NSUTF8StringEncoding] base64Encoding];
    NSString *urlString = [NSString stringWithFormat:@"ss://%@", base64String];
    return [NSURL URLWithString:urlString];
}

+ (void)saveConfigForKey:(NSString *)key value:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
}

+ (NSString *) configForKey:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] objectForKey:key];
}

+ (void) battleFrontSaveProfile:(Profile *)profile {
    if (profile == nil) {
        return;
    }
    [ShadowsocksRunner saveConfigForKey:kShadowsocksIPKey value:profile.server];
    [ShadowsocksRunner saveConfigForKey:kShadowsocksPortKey value:[NSString stringWithFormat:@"%ld", (long)profile.serverPort]];
    [ShadowsocksRunner saveConfigForKey:kShadowsocksPasswordKey value:profile.password];
    [ShadowsocksRunner saveConfigForKey:kShadowsocksEncryptionKey value:profile.method];

    [ShadowsocksRunner saveConfigForKey:kShadowsocksProtocolKey value:profile.protocol];
    [ShadowsocksRunner saveConfigForKey:kShadowsocksProtocolParamKey value:profile.protocolParam];
    [ShadowsocksRunner saveConfigForKey:kShadowsocksObfsKey value:profile.obfs];
    [ShadowsocksRunner saveConfigForKey:kShadowsocksObfsParamKey value:profile.obfsParam];
}

+ (Profile *) battleFrontGetProfile {
    Profile *profile = [[Profile alloc] init];

    NSString *server = [ShadowsocksRunner configForKey:kShadowsocksIPKey];
    profile.server = [server isKindOfClass:[NSString class]] ? server : @"";

    NSString *port = [ShadowsocksRunner configForKey:kShadowsocksPortKey];
    profile.serverPort = [port isKindOfClass:[NSString class]] ? port.integerValue : 0;

    NSString *password = [ShadowsocksRunner configForKey:kShadowsocksPasswordKey];
    profile.password = [password isKindOfClass:[NSString class]] ? password : @"";

    NSString *method = [ShadowsocksRunner configForKey:kShadowsocksEncryptionKey];
    profile.method = [method isKindOfClass:[NSString class]] ? method : @"";

    NSString *protocol = [ShadowsocksRunner configForKey:kShadowsocksProtocolKey];
    profile.protocol = [protocol isKindOfClass:[NSString class]] ? protocol : @"";

    NSString *protocolParam = [ShadowsocksRunner configForKey:kShadowsocksProtocolParamKey];
    profile.protocolParam = [protocolParam isKindOfClass:[NSString class]] ? protocolParam : @"";

    NSString *obfs = [ShadowsocksRunner configForKey:kShadowsocksObfsKey];
    profile.obfs = [obfs isKindOfClass:[NSString class]] ? obfs : @"";

    NSString *obfsParam = [ShadowsocksRunner configForKey:kShadowsocksObfsParamKey];
    profile.obfsParam = [obfsParam isKindOfClass:[NSString class]] ? obfsParam : @"";

    return profile;
}

+ (void)setUsingPublicServer:(BOOL)use {
    [[NSUserDefaults standardUserDefaults] setBool:use forKey:kShadowsocksUsePublicServer];
}

+ (BOOL)isUsingPublicServer {
    NSNumber *usePublicServer = [[NSUserDefaults standardUserDefaults] objectForKey:kShadowsocksUsePublicServer];
    if (usePublicServer != nil) {
        return [usePublicServer boolValue];
    } else {
        return YES;
    }
}

@end
