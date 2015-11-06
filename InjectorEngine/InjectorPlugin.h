//
//  InjectorPlugin.h
//  Injector
//
//  Created by John Holdsworth on 07/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/InjectorEngine/InjectorPlugin.h#5 $
//
//  Repo: https://github.com/johnno1962/Injector
//

#import "../InjectorPlugin/InjectorPluginController.h"

#define INJECTOR_ONDEMAND "InjectorOnDemand.beta1"
#define INJECTOR_EVAL_LICENSE "INJECTOR_BETA"
#define INJECTOR_VERSION 1.0

@class InjectorEngine;
@interface InjectorPlugin : NSObject <InjectorPlugin>

- (instancetype)initWithEngine:(id)injectorEngine;

- (NSString _Nonnull *)enterLicense:(NSString _Nonnull *)licenseKey;
- (NSString _Nullable *)bonjourName;

- (void)watchProject:(NSString _Nullable *)projectRoot;
- (oneway void)injectSources:(NSArray<NSString *> *)modifiedSourceFiles resetApp:(BOOL)reset isFileWatcher:(BOOL)isFileWatcher evalCode:(NSString _Nullable *)evalCode;

- (BOOL)loadBundleInDebugger:(NSString _Nonnull *)bundlePath;
- (NSArray<NSString *> _Nullable *)addressesForSocket:(int)serverSocket;
- (NSString _Nonnull *)hashStringForPath:(NSString _Nonnull *)path;

@end

#import "../Injector/BundleInjection.h"
