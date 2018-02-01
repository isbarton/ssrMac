//
// Created by clowwindy on 14-2-27.
// Copyright (c) 2014 clowwindy. All rights reserved.
//

#import "ShadowsocksRunner.h"
#import "SWBAppDelegate.h"
#import "Profile.h"
#import "Configuration.h"
#import "ProfileManager.h"
#include "ssrcipher.h"
#include "defs.h"
#include "ssr_qr_code.h"
#include <uv.h>

struct server_config * build_config_object(Profile *profile, unsigned short listenPort) {
    const char *protocol = profile.protocol.UTF8String;
    if (protocol && strcmp(protocol, "verify_sha1") == 0) {
        // LOGI("The verify_sha1 protocol is deprecate! Fallback to origin protocol.");
        protocol = NULL;
    }

    struct server_config *config = config_create();

    config->listen_port = listenPort;
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

void ssr_main_loop(uv_loop_t *loop, unsigned short listenPort) {
    struct server_config *config = NULL;
    do {
        Profile *profile = [ShadowsocksRunner battleFrontGetProfile];
        config = build_config_object(profile, listenPort);
        if (config == NULL) {
            break;
        }

        if (config->method == NULL || config->password==NULL || config->remote_host==NULL) {
            break;
        }

        //uv_loop_t *loop = uv_loop_new(); // uv_default_loop();
        listener_run(config, loop);
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
    if (([[NSUserDefaults standardUserDefaults] stringForKey:kShadowsocksIPKey] == nil ||
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
    SWBAppDelegate *appDelegate = (SWBAppDelegate *) [NSApplication sharedApplication].delegate;
    NSAssert([appDelegate isKindOfClass:[SWBAppDelegate class]], @"SWBAppDelegate");
    
    unsigned short listenPort = (unsigned short) [appDelegate toggleSystemProxyExternal];
    
    BOOL result = NO;
    if (![ShadowsocksRunner settingsAreNotComplete]) {
        loop = calloc(1, sizeof(uv_loop_t)); // TODO: memory leak fixing.
        uv_loop_init(loop);

        ssr_main_loop(loop, listenPort);

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
    
    struct server_config *config = ssr_qr_code_decode([url absoluteString].UTF8String);
    if (config == NULL) {
        return NO;
    }
    
    Profile *profile = [[Profile alloc] init];
    
    profile.method = [NSString stringWithUTF8String:config->method];
    profile.password = [NSString stringWithUTF8String:config->password];
    profile.server = [NSString stringWithUTF8String:config->remote_host];
    profile.serverPort = config->remote_port;
    
    profile.protocol = [NSString stringWithUTF8String:config->protocol];
    profile.protocolParam = [NSString stringWithUTF8String:config->protocol_param?:""];
    profile.obfs = [NSString stringWithUTF8String:config->obfs];
    profile.obfsParam = [NSString stringWithUTF8String:config->obfs_param?:""];
    
    profile.remarks = [NSString stringWithUTF8String:config->remarks?:""];

    config_release(config);

    Configuration *configuration = [ProfileManager configuration];
    [((NSMutableArray *) configuration.profiles) addObject:profile];
    [ProfileManager saveConfiguration:configuration];
    
    [ShadowsocksRunner reloadConfig];

    SWBAppDelegate *appDelegate = (SWBAppDelegate *) [NSApplication sharedApplication].delegate;
    NSAssert([appDelegate isKindOfClass:[SWBAppDelegate class]], @"SWBAppDelegate");
    [appDelegate updateMenu];
    
    return YES;
}

+(NSURL *)generateSSURL {
    char *qrCode = NULL;

    Profile *profile = [ShadowsocksRunner battleFrontGetProfile];
    struct server_config *config = build_config_object(profile, 0);
    qrCode = ssr_qr_code_encode(config, &malloc);
    config_release(config);

    NSString *r = [NSString stringWithUTF8String:qrCode];
    free(qrCode);
    
    return [NSURL URLWithString:r];
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

@end
