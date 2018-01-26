//
// Created by clowwindy on 14-2-27.
// Copyright (c) 2014 clowwindy. All rights reserved.
//

#import "ShadowsocksRunner.h"
#import "local.h"
#include "ssrcipher.h"
#include "defs.h"
#include <uv.h>

struct server_config * build_config_object(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *method = [defaults objectForKey:kShadowsocksEncryptionKey];
    if (method.length == 0) {
        method = @"aes-256-cfb";
    }
    const char *host = [[defaults stringForKey:kShadowsocksIPKey] cStringUsingEncoding:NSUTF8StringEncoding];
    const char *port = [[defaults stringForKey:kShadowsocksPortKey] cStringUsingEncoding:NSUTF8StringEncoding];
    const char *password = [[defaults stringForKey:kShadowsocksPasswordKey] cStringUsingEncoding:NSUTF8StringEncoding];

    const char *protocol = [[defaults stringForKey:kShadowsocksProtocolKey] cStringUsingEncoding:NSUTF8StringEncoding];
    if (protocol && strcmp(protocol, "verify_sha1") == 0) {
        // LOGI("The verify_sha1 protocol is deprecate! Fallback to origin protocol.");
        protocol = NULL;
    }
    const char *protocolParam = [[defaults stringForKey:kShadowsocksProtocolParamKey] cStringUsingEncoding:NSUTF8StringEncoding];
    const char *obfs = [[defaults stringForKey:kShadowsocksObfsKey] cStringUsingEncoding:NSUTF8StringEncoding];
    const char *obfsParam = [[defaults stringForKey:kShadowsocksObfsParamKey] cStringUsingEncoding:NSUTF8StringEncoding];

    struct server_config *config = config_create();

    if (port) {
        config->remote_port = atoi(port);
    }
    config->listen_port = DEFAULT_BIND_PORT;
    string_safe_assign(&config->method, method.UTF8String);
    string_safe_assign(&config->remote_host, host);
    string_safe_assign(&config->password, password);
    string_safe_assign(&config->protocol, protocol);
    string_safe_assign(&config->protocol_param, protocolParam);
    string_safe_assign(&config->obfs, obfs);
    string_safe_assign(&config->obfs_param, obfsParam);
    
    return config;
}

void ssr_main(void) {
    struct server_config *config = NULL;
    do {
        config = build_config_object();
        if (config == NULL) {
            break;
        }
        
        if (config->method == NULL || config->password==NULL || config->remote_host==NULL) {
            break;
        }
        
        uv_loop_t *loop = uv_loop_new(); // uv_default_loop();
        listener_run(config, loop);
        //uv_loop_delete(loop);
    } while(0);
    
    config_release(config);
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

+ (BOOL)runProxy {
    if (![ShadowsocksRunner settingsAreNotComplete]) {
        local_main();
        return YES;
    } else {
#ifdef DEBUG
        NSLog(@"warning: settings are not complete");
#endif
        return NO;
    }
}

+ (void)reloadConfig {
    if (![ShadowsocksRunner settingsAreNotComplete]) {
        if ([ShadowsocksRunner isUsingPublicServer]) {
            set_config("106.186.124.182", "8911", "Shadowsocks", "aes-128-cfb");
            memcpy(shadowsocks_key, "\x45\xd1\xd9\x9e\xbd\xf5\x8c\x85\x34\x55\xdd\x65\x46\xcd\x06\xd3", 16);
        } else {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSString *v = [defaults objectForKey:kShadowsocksEncryptionKey];
            if (v.length == 0) {
                v = @"aes-256-cfb";
            }
            const char *host = [[defaults stringForKey:kShadowsocksIPKey] cStringUsingEncoding:NSUTF8StringEncoding];
            const char *port = [[defaults stringForKey:kShadowsocksPortKey] cStringUsingEncoding:NSUTF8StringEncoding];
            const char *password = [[defaults stringForKey:kShadowsocksPasswordKey] cStringUsingEncoding:NSUTF8StringEncoding];

            kShadowsocksProtocolKey;
            kShadowsocksProtocolParamKey;
            kShadowsocksObfsKey;
            kShadowsocksObfsParamKey;

            set_config(host, port, password, [v cStringUsingEncoding:NSUTF8StringEncoding]);
        }
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
        NSString *method = [urlString substringWithRange:NSMakeRange(0, firstColonRange.location)];
        NSString *password = [urlString substringWithRange:NSMakeRange(firstColonRange.location + 1, lastAtRange.location - firstColonRange.location - 1)];
        NSString *IP = [urlString substringWithRange:NSMakeRange(lastAtRange.location + 1, lastColonRange.location - lastAtRange.location - 1)];
        NSString *port = [urlString substringWithRange:NSMakeRange(lastColonRange.location + 1, urlString.length - lastColonRange.location - 1)];
        [ShadowsocksRunner saveConfigForKey:kShadowsocksIPKey value:IP];
        [ShadowsocksRunner saveConfigForKey:kShadowsocksPortKey value:port];
        [ShadowsocksRunner saveConfigForKey:kShadowsocksPasswordKey value:password];
        [ShadowsocksRunner saveConfigForKey:kShadowsocksEncryptionKey value:method];

        kShadowsocksProtocolKey;
        kShadowsocksProtocolParamKey;
        kShadowsocksObfsKey;
        kShadowsocksObfsParamKey;

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
    NSString *parts = [NSString stringWithFormat:@"%@:%@@%@:%@",
                       [ShadowsocksRunner configForKey:kShadowsocksEncryptionKey],
                       [ShadowsocksRunner configForKey:kShadowsocksPasswordKey],
                       [ShadowsocksRunner configForKey:kShadowsocksIPKey],
                       [ShadowsocksRunner configForKey:kShadowsocksPortKey]];

    kShadowsocksProtocolKey;
    kShadowsocksProtocolParamKey;
    kShadowsocksObfsKey;
    kShadowsocksObfsParamKey;

    NSString *base64String = [[parts dataUsingEncoding:NSUTF8StringEncoding] base64Encoding];
    NSString *urlString = [NSString stringWithFormat:@"ss://%@", base64String];
    return [NSURL URLWithString:urlString];
}

+ (void)saveConfigForKey:(NSString *)key value:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
}

+ (NSString *)configForKey:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] objectForKey:key];
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
