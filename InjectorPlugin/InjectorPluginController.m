//
//  InjectorPluginController.m
//  Injector
//
//  Created by John Holdsworth on 01/05/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/InjectorPlugin/InjectorPluginController.m#4 $
//
//  Repo: https://github.com/johnno1962/Injector
//

#import <Cocoa/Cocoa.h>
#import "InjectorPluginController.h"

typedef NS_ENUM(int, DBGState) {
    DBGStateIdle,
    DBGStatePaused,
    DBGStateRunning
};

@interface DBGLLDBSession : NSObject
- (DBGState)state;
- (void)requestPause;
- (void)requestContinue;
- (void)evaluateExpression:(id)a0 threadID:(unsigned long)a1 stackFrameID:(unsigned long)a2 queue:(id)a3 completionHandler:(id)a4;
- (void)executeConsoleCommand:(id)a0 threadID:(unsigned long)a1 stackFrameID:(unsigned long)a2 ;
@end

@interface InjectorPluginController() <InjectorPlugin>

@property NSWindowController *lastWindowController;
@property Class IDEWorkspaceWindowController;
@property NSConnection *theConnection;
@property id<InjectorService> injectorEngine;
@property NSString *injectorPath;
@property NSString *lastFile;
@property BOOL hasSaved;

@end

@implementation InjectorPluginController

static InjectorPluginController *injectorPlugin;

+ (BOOL)loadBundleForPlugin:(NSString *)resourcePath;
{
    @try {
        return[injectorPlugin.injectorEngine loadBundleForPlugin:resourcePath];
    }
    @catch ( NSException *e ) {
        NSLog( @"InjectorPlugin: loadBundleForPlugin: %@", e );
        return FALSE;
    }
}

+ (NSString *)sourceForClass:(NSString *)className;
{
    @try {
        return [injectorPlugin.injectorEngine sourceForClass:className];
    }
    @catch ( NSException *e ) {
        NSLog( @"InjectorPlugin: sourceForClass: %@", e );
        return nil;
    }
}

+ (void)evalCode:(NSString *)code;
{
    [injectorPlugin communicateWithinjectorEngine:^{
        [injectorPlugin.injectorEngine evalCode:code];
    }];
}

+ (void)showParams;
{
    [injectorPlugin communicateWithinjectorEngine:^{
        [injectorPlugin.injectorEngine displayParameters];
    }];
}

+ (void)pluginDidLoad:(NSBundle *)plugin {
    if ([[NSBundle mainBundle].infoDictionary[@"CFBundleName"] isEqual:@"Xcode"]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            injectorPlugin = [[self alloc] init];
            [[NSNotificationCenter defaultCenter] addObserver:injectorPlugin
                                                     selector:@selector(applicationDidFinishLaunching:)
                                                         name:NSApplicationDidFinishLaunchingNotification object:nil];
        });
    }
}

- (NSString *)pluginVersion {
    return @"1.0";
}

#define COULD_NOT_COMMUNICATE @"Could not communicate"

- (NSModalResponse)error:(NSString *)format, ... {
    va_list argp;
    va_start(argp, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:argp],
       *alternate = [msg hasPrefix:COULD_NOT_COMMUNICATE] ? @"Run it now" : nil;
    return [[NSAlert alertWithMessageText:@"[Injector Plugin:"
                            defaultButton:@"OK" alternateButton:alternate otherButton:nil
                informativeTextWithFormat:@"%@", msg] runModal];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSMenu *productMenu = [[[NSApp mainMenu] itemWithTitle:@"Product"] submenu];
    if (productMenu) {
        struct { const char *item,  *key; SEL action; } items[] = {
            {"Inject Source", "=", @selector(injectSource:)},
            {"Inject & Reset", "+", @selector(injectWithReset:)},
            {"Patch Project", "", @selector(patchProject:)},
            {"Unpatch Project", "", @selector(unpatchProject:)},
            {"Show Parameters", "", @selector(displayParameters:)}
        };

        NSMenu *injectorMenu = [NSMenu new];
        for ( int i=0 ; i<sizeof items/sizeof items[0] ; i++ ) {
            NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:items[i].item]
                                                              action:items[i].action
                                                       keyEquivalent:[NSString stringWithUTF8String:items[i].key]];
            [menuItem setKeyEquivalentModifierMask:NSControlKeyMask];
            [menuItem setTarget:self];
            [injectorMenu addItem:menuItem];
        }

        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"Injector Plugin"
                                                          action:NULL
                                                   keyEquivalent:@""];

        [productMenu addItem:[NSMenuItem separatorItem]];
        [menuItem setSubmenu:injectorMenu];
        [productMenu addItem:menuItem];
    }
    else
        NSLog( @"InjectorPlugin: Could not locate proudct menu" );

    self.IDEWorkspaceWindowController = NSClassFromString(@"IDEWorkspaceWindowController");
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(workspaceDidChange:)
                                                 name:NSWindowDidBecomeKeyNotification object:nil];

    self.injectorPath = @"/Applications/Injector.app"; ////
    [self connectToInjector:NO];
}

- (void)connectToInjector:(BOOL)prompt {
    @try {
        self.theConnection = [NSConnection connectionWithRegisteredName:INJECTOR_ENGINE_DO
                                                                   host:nil];//@"localhost"];
        self.injectorEngine = (id<InjectorService>)[self.theConnection rootProxy];
        [(id)self.injectorEngine setProtocolForProxy:@protocol(InjectorService)];

        if ( !self.injectorEngine ) {
            NSLog( @"InjectorPlugin: Could not connect to Injector %@ %@", INJECTOR_ENGINE_DO, self.theConnection );

            if ( prompt && [self error:COULD_NOT_COMMUNICATE" with Injector App"] == NSAlertAlternateReturn ) {

                [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:self.injectorPath]];
                sleep( 2 );

                [self connectToInjector:prompt];
            }
            return;
        }

        self.injectorPath = [self.injectorEngine xcodeStarted:[[NSBundle mainBundle] bundlePath] plugin:self];
        NSString *workspacePath = [self workspacePath];
        if ( workspacePath )
            [self.injectorEngine workspaceChanged:workspacePath logDirectory:[self logDirectory]];
    }
    @catch ( NSException *e ) {
        NSLog( @"InjectorPlugin: Could not connect to injector, is Injector App running? %@", e );
    }
}

- (void)communicateWithinjectorEngine:(void(^)())block prompt:(BOOL)prompt {
    if ( !self.injectorEngine )
        [self connectToInjector:prompt];
    dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            [self.injectorEngine workspaceChanged:[self workspacePath] logDirectory:[self logDirectory]];
            block();
        }
        @catch ( NSException *e ) {
            @try {
                dispatch_sync( dispatch_get_main_queue(), ^{
                    [self connectToInjector:prompt];
                } );
                block();
            }
            @catch ( NSException *e ) {
                NSLog( @"InjectorPlugin: Could not communicate with Injector App: %@", e );
            }
        }
    } );
}

- (void)communicateWithinjectorEngine:(void(^)())block {
    [self communicateWithinjectorEngine:block prompt:YES];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    return self.lastWindowController != nil;
}

- (IBAction)displayParameters:(id)sender {
    [self communicateWithinjectorEngine:^{
        [self.injectorEngine displayParameters];
    }];
}

- (IBAction)patchProject:(id)sender {
    [self communicateWithinjectorEngine:^{
        if ( ![self.injectorEngine patchProject] )
            dispatch_async( dispatch_get_main_queue(), ^{
                [self error:@"Unable to locate project's main.m to patch "
                 "(or project is already patched.) "
                 "To inject Swift projects on a device or in AppCode add a dummy main.m."];
            } );
    }];
}

- (IBAction)unpatchProject:(id)sender {
    [self communicateWithinjectorEngine:^{
        [self.injectorEngine unpatchProject];
    }];
}

- (void)inject:(id)sender actualCmd:(SEL)actualCmd {
    if ( [sender isKindOfClass:[NSMenuItem class]] )
        self.lastFile = [self lastFileSaving:YES];

    if ( !self.hasSaved )
        [self performSelector:actualCmd withObject:self afterDelay:.05];
    else {
        if ( [self.lastFile rangeOfString:@"/main\\.mm?$"
                                  options:NSRegularExpressionSearch].location != NSNotFound )
            [self error:@"Injecting main.m is not permitted."];
        else if ( [self.lastFile rangeOfString:INJECTOR_PATTERN
                                       options:NSRegularExpressionSearch].location == NSNotFound )
            [self error:@"Only class implementations (.m, .mm, .swift), or .storyboard files can be injected."];
        else {
            NSArray *sources = @[self.lastFile];
            [self communicateWithinjectorEngine:^{
                [self.injectorEngine injectSources:sources
                                       resetApp:actualCmd == @selector(injectWithReset:)];
            }];
        }

        self.lastFile = nil;
    }
}

- (IBAction)injectSource:(id)sender {
    [self inject:sender actualCmd:_cmd];
}

- (IBAction)injectWithReset:(id)sender {
    [self inject:sender actualCmd:_cmd];
}

- (NSString *)lastFileSaving:(BOOL)save {
    NSDocument *doc = [[self lastEditor] document];
    if ( save ) {
        if ( [doc isDocumentEdited] ) {
            self.hasSaved = FALSE;
            [doc saveDocumentWithDelegate:self
                          didSaveSelector:@selector(document:didSave:contextInfo:)
                              contextInfo:NULL];
        }
        else
            self.hasSaved = TRUE;
    }
    return [[doc fileURL] path];
}

- (void)document:(NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void  *)contextInfo {
    self.hasSaved = TRUE;
}

- (id)lastEditor {
    return [self.lastWindowController valueForKeyPath:@"editorArea.lastActiveEditorContext.editor"];
}

- (void)workspaceDidChange:(NSNotification *)notification {
    NSWindow *object = [notification object];
    NSWindowController *currentWindowController = [object windowController];
    if ([currentWindowController isKindOfClass:self.IDEWorkspaceWindowController] &&
            [[[(id)currentWindowController document] fileURL] path] ) {
        self.lastWindowController = currentWindowController;
        [self communicateWithinjectorEngine:^{
            //[self.injectorEngine workspaceChanged:[self workspacePath] logDirectory:[self logDirectory]];
        } prompt:NO];
    }
}

- (NSString *)workspacePath {
    return [[[self.lastWindowController document] fileURL] path];
}

- (NSString *)logDirectory {
    return [self.lastWindowController valueForKeyPath:@"workspace.executionEnvironment.logStore.rootDirectoryPath"];
}

- (NSWindowController *)debugController {
    if ( [self sessionForController:self.lastWindowController] )
        return self.lastWindowController;

    for ( NSWindow *win in [NSApp windows] ) {
        NSWindowController *controller = [win windowController];
        if ( [controller isKindOfClass:self.IDEWorkspaceWindowController] &&
            [[[controller document] fileURL] path] &&
            [self sessionForController:controller] )
            return controller;
    }

    return self.lastWindowController;
}

- (DBGLLDBSession *)sessionForController:(NSWindowController *)controller {
    return [controller valueForKeyPath:@"workspace"
            ".executionEnvironment.selectedLaunchSession.currentDebugSession"];
}
 
 - (DBGLLDBSession *)session {
     return [self sessionForController:[self debugController]];
 }
 

- (BOOL)loadBundleInDebugger:(NSString *)bundlePath {
    DBGLLDBSession *session = [self session];

    if ( !session ) {
        [[NSAlert alertWithMessageText:@"Injector Plugin:"
                        defaultButton:@"OK" alternateButton:nil otherButton:nil
             informativeTextWithFormat:@"Program is not running."] runModal];
        return FALSE;
    }

    NSString *MacOS = [[self.lastWindowController valueForKeyPath:@"workspace.executionEnvironment.currentLaunchSession"
                       ".launchParameters.filePathToBinary.pathString"] stringByDeletingLastPathComponent];
    if ( [MacOS hasSuffix:@"/Contents/MacOS"] ) {
        NSString *newLocation = [[MacOS stringByAppendingPathComponent:@"../Resources"]
                                 stringByAppendingPathComponent:bundlePath.lastPathComponent];
        [[NSFileManager defaultManager] copyItemAtPath:bundlePath toPath:newLocation error:nil];
        bundlePath = newLocation;
    }

    if ( session.state != DBGStatePaused )
        [session requestPause];
    [self performSelector:@selector(loadBundle:) withObject:bundlePath afterDelay:.1];
    return TRUE;
}

- (void)loadBundle:(NSString *)bundlePath {
    DBGLLDBSession *session = [self session];

    if ( session.state != DBGStatePaused )
        [self performSelector:@selector(loadBundle:) withObject:bundlePath afterDelay:.1];
    else
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0), ^{
            NSString *lldbTemplate = @"p (void)[[NSBundle bundleWithPath:@\"%@\"] load]\r",
                *loader = [NSString stringWithFormat:lldbTemplate, bundlePath];
            [session executeConsoleCommand:loader threadID:1 stackFrameID:0];
            dispatch_async(dispatch_get_main_queue(), ^{
                [session requestContinue];
            });
        });
}

@end
