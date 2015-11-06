//
//  BundleContents.m
//  InjectionBundle
//
//  Created by John Holdsworth on 17/01/2012.
//  Copyright (c) 2012 John Holdsworth. All rights reserved.
//

// generated file with includes of main project classes

/*
 Generated for Injection of class implementations
 */

#define INJECTION_NOIMPL
#define INJECTION_BUNDLE InjectionBundle2

#define INJECTION_ENABLED
#import "__INJECTION_INCLUDE__"

#undef _instatic
#define _instatic extern

#undef _inglobal
#define _inglobal extern

#undef _inval
#define _inval( _val... ) /* = _val */

#import "BundleContents.h"

extern
#if __cplusplus
"C" {
#endif
    int injectionHook(void);
#if __cplusplus
};
#endif

@interface InjectionBundle : NSObject
@end
@implementation InjectionBundle

+ (void)load {
    Class bundleInjection = NSClassFromString(@"BundleInjection");
    [bundleInjection autoLoadedNotify:8 hook:(void *)injectionHook];
}

@end

int injectionHook() {
    NSLog( @"injectionHook():" );
    [InjectionBundle load];
    return YES;
}



