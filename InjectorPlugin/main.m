//
//  main.m
//  Injector
//
//  Created by John Holdsworth on 19/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/InjectorPlugin/main.m#3 $
//
//  Repo: https://github.com/johnno1962/Injector
//

#import <stdio.h>
#import "InjectorPluginController.h"

int main( int argc, const char * argv[] )
{
    if ( argc < 3 ) {
        printf( "Usage: <injectSources|patchProject|unpatchProject> workspacePath [filesToInject...]\n\n" );
        exit(1);
    }

    @autoreleasepool {
        NSConnection *theConnection = [NSConnection connectionWithRegisteredName:INJECTOR_ENGINE_DO
                                                                   host:nil];
        id<InjectorService> injectorEngine = (id<InjectorService>)[theConnection rootProxy];
        [(id)injectorEngine setProtocolForProxy:@protocol(InjectorService)];

        const char *action = argv[1];

        NSString *workspacePath = [NSString stringWithUTF8String:argv[2]];
        [injectorEngine workspaceChanged:workspacePath logDirectory:nil];

        if ( strcmp( action, "patchProject" ) == 0 )
            exit( [injectorEngine patchProject] ? 0 : 1 );
        else if ( strcmp( action, "unpatchProject" ) == 0 )
            [injectorEngine unpatchProject];
        else if ( strcmp( action, "injectSources" ) == 0 ) {
            NSMutableArray *sources = [NSMutableArray new];

            for ( int arg = 3 ; arg < argc ; arg++ )
                [sources addObject:[NSString stringWithUTF8String:argv[arg]]];

            [injectorEngine appCode:workspacePath injectSources:sources];
        }
        else {
            printf( "Invalid action %s\n\n", action );
            exit(1);
        }
    }

    sleep(1);
    return 0;
}
