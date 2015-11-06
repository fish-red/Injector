//
//  InjectorEngine.swift
//  Injector
//
//  Created by John Holdsworth on 07/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/InjectorEngine/InjectorEngine.swift#9 $
//
//  Repo: https://github.com/johnno1962/Injector
//

import Foundation
import SwiftRuby

import InjectorPlugin

extension String {

    func join( array: [String] ) -> String {
        return array.joinWithSeparator( self )
    }

}

public var injectorEngineInstance: InjectorEngine!

/**
    Procesing core of Juie application. Can be run as XPC inside main app process
*/
@objc(InjectorEngine)
public class InjectorEngine : NSObject {

    class func demangleStackTrace( stack: [String] ) -> [String] {
        return stack.map {
            (symbol: String) in
            let mutable = symbol.mutableString
            mutable["((?:\\S+\\s+){3})(\\S+)(.*)"] =~ {
                (groups: [String?]) in
                return groups[1]!+_stdlib_demangleName( groups[2]! )+groups[3]!
            }
            return mutable as String
        }
    }

    /**
        Pathway back to Injector application UI/main bundle for logging/prefernces
    */
    let ui: InjectorAppDelegate
    private let preferences: InjectorAppDelegate

    /**
        Pathway to talk to application being injected
    */
    let clientApp: ClientApp

    /**
        Instance through which requests are received from the InjectorPlugin
    */
    var plugin: InjectorPlugin!

    /**
        Time file was last injected to prevent to deduplicate events from FileWatcher
    */
    private var lastInjected = [String:NSTimeInterval]()

    /**
        Cache of commands to compile source files reset each time app connects
    */
    var compileCommands = [String:String]()

    /**
        Used to cache paths to sources files for a pattern specifying a eval class
    */
    public var sourcesForClasses = [String:String]()

    /**
        Version of Xcode being plugin is being used in
    */
    var xcodePath = "/Applications/Xcode.app"

    /**
        XcodeProject instance associated with the workspace last selected in Xcode
    */
    public var selectedProject: XcodeProject!

    /**
        selectedProject when client app last connected
    */

    var runProject: XcodeProject?

    /**
        UNIX user name runnig injector
    */
    var user = String( UTF8String: getenv("USER") )!

    /**
        architecture last detected when client app connected
    */
    public var arch: String?

    /**
        Shortcut in /tmp to easse sharing of patch source
    */
    var resourceShortcut = "/tmp/Injector"

    /**
        OS of last connected client app for injection bundle project name (iOS or OSX)
    */
    var os: String?

    init( UI: InjectorAppDelegate, clientApp: ClientApp ) {
        self.ui = UI
        self.preferences = UI
        self.clientApp = clientApp

        super.init()

        plugin = InjectorPlugin( engine: self )
        injectorEngineInstance = self

        File.unlink_f( resourceShortcut )
        File.symlink( U(NSBundle( forClass: self.dynamicType ).resourcePath), resourceShortcut )
    }

    // MARK: logging

    internal func progress( msg: String, detail: String! = nil ) {
        let msg = detail != nil ? msg+"..." : msg
        #if DEBUG && IN_XPC
            println( msg )
        #endif
        clientApp.console( msg ) /// maybe remove
        ui.progress( msg, detail: detail )
    }

    internal func error( msg: String, detail: String! = nil ) {
        let combined = (detail != nil ? detail+"\n" : "")+msg
        #if DEBUG && IN_XPC
            println( combined )
        #endif
        ui.error( msg, detail: detail )
    }

    internal func debug( msg: String ) {
        #if DEBUG
            #if IN_XPC
                println( msg )
            #endif
            ui.debug( msg )
        #endif
    }

    // MARK: From Plugin

    /**
        Called every user changes workspace in Xcode

        :param: workspacePath path to .xcworkspace file (.xcprojects have embedded wrokspace file)

        :param: logDirectory path to log directory contain xcactivity files which (in gzip format)

        :param: User is injecting from AppCode in which case logDirectory will be nil as well
    */
    public func workspaceChanged( workspacePath: String!, logDirectory: String!, isAppCode: Bool ) {

        if workspacePath == nil {
            error( "workspaceChanged: nil workspacePath" )
        }
        else if let newProject = XcodeProject( workspacePath, logDirectory, engine: self ) {
            if selectedProject == nil || // logDirectory != nil ||
                newProject.projectPath != selectedProject.projectPath {
                    selectedProject = newProject
                    if runProject == nil || isAppCode {
                        runProject = selectedProject
                    }
                    ui.activeProject( selectedProject.projectName )
            }
        } else {
            error( "Could not initialise XcodeProject", detail: workspacePath )
        }

        //debug( "workspaceChanged: \(workspacePath) --- \(logDirectory) --- \(selectedProject) \(runProject)" )
    }

    /**
        Lock a file out to deduplicate injections which write to the file and set of the filewatcher

        :param: file that has been injected

        :param: isFileWatcher whether it was the file watcher that instigated the injection

        :returns: whether the injection should be locked out
    */
    func lockout( file: String, isFileWatcher: Bool ) -> Bool {
        let lockoutPeriod = 5.0
        let now = NSDate.timeIntervalSinceReferenceDate()
        if (lastInjected["\(file)-\(!isFileWatcher)"] ?? 0.0) + lockoutPeriod > now {
            return true
        } else {
            lastInjected["\(file)-\(isFileWatcher)"] = now
            return false
        }
    }

    /**
        Call each time user injects or FileWatcher detects changed files

        :param: modifiedSourecFiles file injected as curent document or list of files from FileWatcher

        :param: resetApp user wishes app to be reset by reloading rootViewController from storyboard
    */
    func injectSources( modifiedSourceFiles: [String], resetApp: Bool, isFileWatcher: Bool, evalCode: String! ) {
        debug( "injectSources: \(selectedProject) \(runProject) \(modifiedSourceFiles)" )

        if evalCode == nil && preferences.shouldFileWatch {
            // required as plugin menu item "Inject Source"
            // saves file which is picked up by FileWatcher
            for file in modifiedSourceFiles {
                if lockout( file, isFileWatcher: isFileWatcher ) {
                    debug( "Locked out \(file)" )
                    return
                }
            }
        }

        if modifiedSourceFiles[0]["\\.(storyboard|nib)$"] {
            if !ui.injectStoryboards {
                error( "Storyboard injection must be selected in the paramaters panel" )
                return
            }
            if !clientApp.connected {
                error( "Storyboard injection requires project patching" )
                return
            }
        }

        if !ensureClientConnected() {
            return
        }

        ui.updateState(.Building)

        if runProject == nil {
            runProject = selectedProject
        }

        if let objectFiles = selectedProject.findCommandsAndRecompile( modifiedSourceFiles, evalCode: evalCode ) {

            if let runProject = runProject {
                let injection = InjectionBundler( runProject: runProject )

                if injection.prepareProjectAndInjectBundle( modifiedSourceFiles, objectFiles: objectFiles, resetApp: resetApp ) {
                    return
                }
            } else {
                error( "No run project or selected project, have you installed the plugin?" )
            }
        }

        ui.updateState( .CompileError )
        error( "Injection Failed, Consult Console" )
    }

    /**
        If client is not already connected tries loading an "On Demand" bundle using lldb

        :returns: whether on demand bundle was available
    */
    private func ensureClientConnected() -> Bool {
        if !clientApp.connected {
            let bundlePath = ui.onDemandBundlePath( selectedProject.looksLikeOSXProject() )
            if !plugin.loadBundleInDebugger( bundlePath ) {
                error( "Program is not running", detail: bundlePath )
                return false
            }

            let start = NSDate.timeIntervalSinceReferenceDate()
            let connectTimeout = 5.0
            while !clientApp.connected || arch == nil {
                if NSDate.timeIntervalSinceReferenceDate() - start > connectTimeout {
                    error( "Timeout waiting for connect" )
                    return false
                }
                NSThread.sleepForTimeInterval(0.1)
            }
        }

        return true
    }

    /**
        Arrives from Xrobe plugin to evaluate code against an object in an aplication

        :param: an encoded string containg pathID, className, isSwift and code to be evaluated
    */
    func evalCode( code: String! ) {
        ui.updateState(.Building)

        let parts = code.componentsSeparatedByString( "^" )

        //let pathID = Int(parts[0])!
        let className = parts[1]
        let isSwift = Int(parts[2])! != 0
        let code = parts[3].stringByRemovingPercentEncoding
        let modifiedSourceFiles = [removePrefix( className ) + (isSwift ? ".swift" : ".m")]

        plugin.injectSources( modifiedSourceFiles, resetApp: false, isFileWatcher: false, evalCode: code )
    }

    /**
        Convert Swift classname into likely filename by removing any module prefix

        :param: class name as reported by NSStringFromClass()

        :returns: class name with module prefix removed
    */
    private func removePrefix( className: String ) -> String {
        return className[".+\\."][""]
    }

    /**
        Arrives from Xprobe plugin to determine path to source for a given class

        :param: className name of class

        :returns: path to source for class
    */
    func sourceForClass( className: String! ) -> String! {
        debug( "sourceForClass: \(className)" )
        let className = removePrefix( className )
        return sourcesForClasses["\(className).swift"] ?? sourcesForClasses["\(className).m"]
    }

    deinit {
        NSLog( "InjectorEngine exits" )
    }

}

private let existingPatch = "\n*(// Injector patch starts.*// Injector patch ends\n|" +
                "// From here to end of file added by Injection Plugin //.*|$)"

extension InjectorEngine {

    // MARK: "Local" operations arriving through XPC

    /**
        Used when running with XPC to keep it up and running
    */
    public func keepAlive( arch: String!, os: String! ) {
        self.arch = arch
        self.os = os
    }

    /**
        Request comes from UI to enter the users license string
    */
    public func enterLicense(key: String!, returning response: ((String!) -> Void)!) {
        dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), {
            let reply = self.plugin.enterLicense( key )
            dispatch_async( dispatch_get_main_queue(), {
                response( reply )
            } )
        } )
    }

    /**
        Reset the bundle project to clear out any problems
    */
    public func reset() {
        FileUtils.rm_rf( runProject!.injectionRoot ) ///
        compileCommands = [String:String]()
    }

    /**
        Request to patch project from main app
    */
    public func patch() {
        patchProject()
    }

    /**
        Request to patch project from plugin
    */
    func patchProject() -> Bool {
        let pchPatch = U(File.read( U(ui.pathForResource( "pch", ofType: "patch" )) )).to_s.mutableString
        pchPatch["__INCLUDE__"] =~ resourceShortcut+"/BundleInterface.h"

        selectedProject.patchFilesMatching("refix.pch|Bridging-Header.h", replace: existingPatch, with: pchPatch as String )

        let mainPatch = U(File.read( U(ui.pathForResource( "main", ofType: "patch" )) )).to_s.mutableString
        var serverAddresses = clientApp.serverAddresses()
        if let bonjourName = plugin.bonjourName() {
            serverAddresses.insert( bonjourName, atIndex: 0 )
        }

        mainPatch["__ADDRESSES__"] =~ serverAddresses.map { "\"\($0)\"" }.joinWithSeparator( ", " )
        mainPatch["__IPADDRS__"] =~ (serverAddresses as! [String]).joinWithSeparator( " " )
        mainPatch["__INCLUDE__"] =~  resourceShortcut+"/BundleInjection.h"
        mainPatch["__PORT__"] =~ "\(INJECTOR_PORT)"

        return selectedProject.patchFilesMatching( "main.(m|mm)", replace: existingPatch, with: mainPatch as String )
    }

    /**
        Revert patch to project
    */
    public func unpatch() {
        selectedProject.patchFilesMatching( "main.(m|mm)", replace: existingPatch, with: "\n" )
        selectedProject.patchFilesMatching( "refix.pch|Bridging-Header.h", replace: existingPatch, with: "\n" )
    }

    /**
        Open bundle project assiated with injection
    */
    public func openBundle() {
        if selectedProject != nil {
            open( "\(selectedProject.injectionRoot)/InjectionBundle.xcodeproj" )
        }
    }

    /**
        Open a file or application
    */
    func open( path: String ) {
        for line in CommandSequence( "open \"\(path)\"" ) {
            error( line, detail: path )
        }
    }

    // MARK: From ClientApp

    /**
        Client application has just connected. Start watching it if required
    */
    public func clientConnected( arch: String, os: String, executable: String ) {
        self.arch = arch
        self.os = os
        runProject = selectedProject
        compileCommands = [String:String]() /// should it? - probably
        sourcesForClasses = [String:String]()
        watchProject( ui.shouldFileWatch )
    }

    /**
        An injection has just been performed, order front simulator if required

        :param: Whether the injection bundle loaded sucessfully and autoLoadedNotify: was called
    */
    public func bundleLoaded( success: Bool ) {
        if success {
            ui.progress( "Bundle loaded", detail: nil )
            if clientApp.isSimulator && preferences.shouldOrderFront {
                open( "\(xcodePath)/Contents/Developer/Applications/Simulator.app" )
            }
        } else {
            error( "Bundle load failed" )
        }
    }

    public func watchProject( canWatch: Bool ) {
        plugin.watchProject( canWatch ? runProject?.projectRoot : nil )
    }

}
