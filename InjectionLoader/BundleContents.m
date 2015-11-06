//
//  BundleContents.m
//  InjectionLoader
//
//  Created by John Holdsworth on 17/01/2012.
//  Copyright (c) 2012 John Holdsworth. All rights reserved.
//

#import "__RESOURCES__/InjectorPlugin/InjectorPluginController.h"

static char _inMainFilePath[] = __FILE__;
static const char *_inIPAddresses[] = {"127.0.0.1", NULL};

#define INJECTION_APPNAME "Injector"
#define INJECTION_PORT INJECTOR_PORT
#define INJECTION_LOADER
#define INJECTION_ENABLED
#import "__RESOURCES__/BundleInjection.h"
