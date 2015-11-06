//
//  InjectorProtocols.h
//  Injector
//
//  File obsolete now XPC is not being used.
//
//  Created by John Holdsworth on 09/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/Injector/InjectorProtocols.h#3 $
//
//  Repo: https://github.com/johnno1962/Injector
//

#import <Foundation/Foundation.h>

//#define INJECTOR_VERSION 1.0

// interface to InjectorApp ui
@protocol InjectorApp
@required
// no other place to put them
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext;
- (oneway void)activeProject:(NSString *)projectName;
- (oneway void)watchProject:(NSString *)projectRoot;
- (oneway void)enterLicenseString:(NSString *)key;
- (NSString *)onDemandBundlePath:(BOOL)isOSX;
- (oneway void)displayParameters;
- (NSArray *)allParameterValues;
- (NSString *)appPath;

// real UI
- (oneway void)updateState:(INBundleState)newState;
- (oneway void)error:(NSString *)msg detail:(NSString *)detail;
- (oneway void)progress:(NSString *)msg detail:(NSString *)detail;
- (oneway void)debug:(NSString *)msg;
- (oneway void)log:(NSString *)msg;

// preferences
@property (readonly) BOOL shouldFileWatch;
@property (readonly) BOOL injectStoryboards;
@property (readonly) BOOL shouldOrderFront;
@property (readonly) BOOL shouldNotify;
@end

// services InjectorXPC makes avilable to UI
@protocol InjectorXPC
@required
- (void)keepAlive:(NSString *)arch os:(NSString *)os;
- (void)enterLicense:(NSString *)key returning:(void (^)( NSString * ))response;
- (void)reset;
- (void)patch;
- (void)unpatch;
- (void)openBundle;
- (void)watcherInjectSources:(NSArray *)modifiedSourceFiles;

//  from ClientAppToEngine
- (void)clientConnected:(NSString *)arch os:(NSString *)os executable:(NSString *)executable;
- (void)bundleLoaded:(BOOL)success;
@end

@protocol EngineToClientApp
@property (readonly) BOOL connected;
@property (readonly) BOOL isSimulator;
@property (readonly) BOOL isOSX;
- (NSString *)config;
- (NSArray *)serverAddresses;
- (oneway void)console:(NSString *)msg;
- (BOOL)injectBundle:(NSString *)bundlePath resetApp:(BOOL)reset
            identity:(NSString *)identity nibBundle:(NSString *)nibBundle;
- (BOOL)loadBundleForPlugin:(NSString *)resourcePath;
@end

@protocol ClientAppToEngine
- (void)clientConnected:(NSString *)arch os:(NSString *)os executable:(NSString *)executable;
- (void)bundleLoaded:(BOOL)success;
- (void)clientDisconnected;
@end
