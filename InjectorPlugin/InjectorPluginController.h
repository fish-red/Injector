//
//  InjectorPluginController.h
//  Injector
//
//  Created by John Holdsworth on 01/05/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/InjectorPlugin/InjectorPluginController.h#4 $
//
//  Repo: https://github.com/johnno1962/Injector
//

#import <Foundation/Foundation.h>

#define INJECTOR_PATTERN @"[^~]\\.(mm?|swift|storyboard|xib)$"

#define INJECTOR_ENGINE_DO @"injector.engine"
#define INJECTOR_PORT 31441

// service plugin makes available to engine
@protocol InjectorPlugin <NSObject>
@required
- (NSString *)pluginVersion;
- (BOOL)loadBundleInDebugger:(NSString *)bundlePath;
@end

// services made available to plugin
@protocol InjectorService
@required
- (NSString *)xcodeStarted:(NSString *)xcodePath plugin:(id<InjectorPlugin>)plugin;
- (oneway void)workspaceChanged:(NSString *)workspacePath logDirectory:(NSString *)logDirectory;
- (oneway void)appCode:(NSString *)workspacePath injectSources:(NSArray *)modifiedSourceFiles;
- (oneway void)injectSources:(NSArray *)modifiedSourceFiles resetApp:(BOOL)reset;
- (BOOL)loadBundleForPlugin:(NSString *)resourcePath;
- (NSString *)sourceForClass:(NSString *)className;
- (oneway void)evalCode:(NSString *)code;
- (oneway void)displayParameters;
- (oneway void)unpatchProject;
- (BOOL)patchProject;
@end

@interface InjectorPluginController : NSObject

@end

