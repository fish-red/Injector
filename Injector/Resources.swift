//
//  Resources.swift
//  Injector
//
//  Created by John Holdsworth on 18/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/Injector/Resources.swift#9 $
//
//  Repo: https://github.com/johnno1962/Injector
//

import Foundation
import SwiftRuby

import InjectorPlugin

class Resources {

    private weak var ui: InjectorAppDelegate!

    init( ui: InjectorAppDelegate ) {
        self.ui = ui

        if !File.exists( injectionLoader ) {
            dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), buildOnDemandBundle )
        }
    }

    private func progress( msg: String, detail: String! = nil ) {
        ui.progress( msg, detail: detail )
    }

    private func error( msg: String, detail: String! = nil ) {
        ui.error( msg, detail: detail )
    }

    private var agentPath: String {
        return "\(NSHomeDirectory())/Library/LaunchAgents/injector.launch.plist"
    }

    func installAgent() {
        if let agentResource = ui.pathForResource( "injector.launch", ofType: "plist" ) {
            File.unlink_f( agentPath )
            if FileUtils.copy( agentResource, agentPath ) && File.chmod( 0o644, agentPath ) &&
                U(RegexpFile( agentPath ))["__APPPATH__"] =~ U(ENV["HOME"])+"/bin/diamond" &&
                U(RegexpFile( agentPath ))["__SCRIPTPATH__"] =~ Process.arguments[0] &&
                U(RegexpFile( agentPath ))["__PORT__"] =~ "\(INJECTOR_PORT)" {
                progress( "Installed agent to start Injector on logon" )
                return
            }
        }
        ui.error( "Could not copy/patch startup agent to \(agentPath)", detail: nil )
    }

    func removeAgent() {
        if File.delete( agentPath ) {
            progress( "Removed agent to start Injector on logon" )
        }
    }

    private func libraryRoot( name: String ) -> String {
        return "\(NSHomeDirectory())/Library/Application Support/\(name)"
    }

    private var injectionLoader: String {
        return libraryRoot( INJECTOR_ONDEMAND )
    }

    func onDemandBundlePath( isOSX: Bool ) -> String {
        let suffix = isOSX ? "" : "-iphonesimulator"
        return "\(injectionLoader)/build/Debug\(suffix)/InjectionLoader.bundle"
    }

    private func buildOnDemandBundle() {
        let loaderResource = ui.pathForResource("InjectionLoader", ofType: nil)
        let tmpInjectionLoader = "\(injectionLoader).tmp"
        FileUtils.rm_rf( tmpInjectionLoader )

        self.error( "Building required components...", detail: injectionLoader )

        if !FileUtils.cp_r( loaderResource, tmpInjectionLoader ) {
            self.error( "Could not copy \(loaderResource)", detail: nil )
            return
        }

        U(RegexpFile( "\(tmpInjectionLoader)/BundleContents.m" ))["__RESOURCES__"] =~ "\(loaderResource)/.."

        for sdk in ["iphonesimulator", "macosx"] {
            let xcodebuild = "xcodebuild -config Debug -sdk \(sdk)"
            progress( "Building On-demand bundle for sdk: \(sdk)", detail: xcodebuild )

            var out = ""
            for line in CommandSequence( "\(xcodebuild) clean && \(xcodebuild)", workingDirectory: tmpInjectionLoader ) {
                out += line
            }

            if yieldTaskExitStatus != 0 {
                self.error( "Could not build InjectionLoader", detail: out )
                return
            }
        }

        progress( "On-demand Injector Loaders built" )

        if !buildPlugin( nil ) {
            return
        }

        installAgent()
        ui.enterLicenseString( INJECTOR_EVAL_LICENSE )

        progress( "Installation complete." )
        FileUtils.rm_rf( injectionLoader )
        File.rename( tmpInjectionLoader, injectionLoader )
    }

    private var pluginsDir = "InjectorPlugins" ////////////

    func buildPlugin( name: String! ) -> Bool {
        var pluginProject = ui.pathForResource( "InjectorPlugin", ofType: nil )

        if name != nil {
            pluginProject = libraryRoot( "\(pluginsDir)/\(name)" )
            FileUtils.rm_rf( pluginProject )

            let gitCommand = "git clone https://github.com/johnno1962/\(name)"
            error( gitCommand )

            let pluginsRoot = libraryRoot( pluginsDir )
            FileUtils.mkdir_p( pluginsRoot )

            for line in CommandSequence( gitCommand, workingDirectory: pluginsRoot ) {
                progress( line )
            }

            if yieldTaskExitStatus != 0 {
                error( "Git clone failed" )
                return false
            }
        }

        if !pluginBuilder( pluginProject, " clean" ) || !pluginBuilder( pluginProject ) {
            error( "Plugin build failed" )
            return false
        }

        let injectorName = "Injector"
        error( "\(name ?? injectorName) Plugin built, please retstart Xcode" )
        return true
    }

    func removePlugin( name: String! ) {
        var pluginProject = ui.pathForResource( "InjectorPlugin", ofType: nil )
        if name != nil {
            pluginProject = libraryRoot( "\(pluginsDir)/\(name)" )
        }
        pluginBuilder( pluginProject, " clean" )
    }

    private func pluginBuilder( pluginProject: String, _ clean: String = "" ) -> Bool {
        progress( "Building plugin\(clean)", detail: pluginProject )

        var out = ""
        for line in CommandSequence( "xcodebuild"+clean, workingDirectory: pluginProject ) {
            out += line
        }

        if yieldTaskExitStatus != 0 {
            error( "Plugin build failed:", detail: out )
            return false
        }

        return true
    }

}
