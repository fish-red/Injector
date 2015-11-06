//
//  InjectionBundler.swift
//  Injector
//
//  Created by John Holdsworth on 15/04/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/InjectorEngine/InjectionBundler.swift#6 $
//
//  Repo: https://github.com/johnno1962/Injector
//

import Foundation
import SwiftRuby

// for switch
public var lastRegexMatchGroups: [String!]!

public func ~= ( left: String, right: String ) -> Bool {
    if let groups = Regexp( target: right, pattern: left ).groups() {
        lastRegexMatchGroups = groups.map { $0 }
        return true
    }
    return false
}

class InjectionBundler {

    let engine: InjectorEngine
    let project: XcodeProject
    let injectionRoot: String
    private let preferences: InjectorAppDelegate

    /**
        Build parameters for project usually found in the environmnt when you run a script
    */
    var buildParams: [String:String]!

    init( runProject: XcodeProject ) {
        project = runProject
        engine = project.engine
        preferences = project.engine.ui
        injectionRoot = project.injectionRoot
    }

    private var toolchain: String {
        return "\(engine.xcodePath)/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
    }

    // MARK: key files

    /**
        Bundle project's .pbxproj file
    */
    private var pbxprojFile: String {
        return "\(injectionRoot)/InjectionBundle.xcodeproj/project.pbxproj"
    }

    /**
        Path of file containing injection bootstrap code on injection
    */
    private var bundleContents: String {
        return "\(injectionRoot)/BundleContents.m"
    }

    /**
        Path to per-architecture file with name

        :param: name of file in per-architecture directory inside bundle project

        :returns: path to file
    */
    private func archFile( name: String ) -> String {
        return "\(injectionRoot)/\(U(engine.arch))/\(name)"
    }

    /**
        Path of cache of recorded bundle build commands when not using xcodebuild
    */
    private var commandsFile: String {
        return archFile( "compile_commands.sh" )
    }

    /**
        Flag file used to avoid unnecessary continual compilation of BundleContents.m
    */
    private var builtFile: String {
        return "\(U(engine.arch))/built_flag.txt"
    }

    // MARK: Bundle Building

    /**
        Last part of injection processing shared with Xcode eval

        :param: modifiedSourceFiles source files to inject

        :param: objectFiles to be linked into the bundle

        :param: resetApp application rootViewController should be reinstated
    */
    func prepareProjectAndInjectBundle( modifiedSourceFiles: [String], objectFiles: [String?], resetApp: Bool ) -> Bool {

        if copyBundleTemplateIfRequired() {

            var nibBundle: String? = project.nibCompiled

            if prepareProjectToLink( objectFiles, injecting: modifiedSourceFiles, nibBundle: &nibBundle ) {

                if let bundlePath = xcodebuildBundleProject() {

                    if engine.clientApp.injectBundle( bundlePath, resetApp: resetApp,
                        identity: buildParams["CODE_SIGN_IDENTITY"], nibBundle: nibBundle ) {
                            return true
                    }
                }
            }
        }

        return false
    }

    /**
        Create projectRoot/iOSInjectorProject or projectRoot/OSInjectorProject

        :returns: whether bundle project could be created
    */
    private func copyBundleTemplateIfRequired() -> Bool {

        if !File.exists( injectionRoot ) {
            let injectionHome = U(File.dirname(injectionRoot))

            if !File.exists( injectionHome ) && !FileUtils.mkdir_p( injectionHome ) {
                    engine.error( "Could not create \(injectionHome)", detail: injectionHome )
                    return false
            }

            let template = U(engine.ui.pathForResource( "\(U(engine.os))BundleTemplate", ofType: nil ))

            if !FileUtils.cp_r( template, injectionRoot ) {
                engine.error( "Template copy error",
                    detail:"\(template) -> \(injectionRoot)" )
                return false
            }

            if let include = engine.ui.pathForResource( "BundleInjection", ofType: "h" ) {
                U(RegexpFile( bundleContents ))["__INJECTION_INCLUDE__"] =~ include
            }
        }

        let archDir = archFile("")
        if !File.exists(archDir) && !FileUtils.mkdir_p( archDir ) {
            engine.error( "Could not create \(archDir)" )
            return false
        }

        return true
    }

    /**
        prepareProjectToLink Prepare bundle project's .pbxproj file to buidl bundle for linked sources

        :param: objectFiles array of object file path to include as "Other Linker Options"

        :param: list of modified files which can be #imported into BundleCOntents.m compile command if not found

        :param: nibBundle app bundle returned if injecting storyboards so contents can be copied into injection bundle
    */
    private func prepareProjectToLink( objectFiles: [String?], injecting modifiedSourceFiles: [String], inout nibBundle: String? ) -> Bool {

        var notify = (preferences.shouldNotify ? INJECTION_NOTSILENT : 0) |
            (preferences.shouldOrderFront ? INJECTION_ORDERFRONT : 0)
        var anyStoryboard = false, anySwift = false
        var linkerOptions = ""
        var imports = ""

        for fileNumber in 0..<modifiedSourceFiles.count {
            let objectFile = objectFiles[fileNumber]
            let sourceFile = modifiedSourceFiles[fileNumber]
            let isSwift = sourceFile["\\.swift$"]

            if sourceFile["\\.(storyboard|nib)$"] {
                notify = notify | INJECTION_STORYBOARD
                anyStoryboard = true
            }
            else if objectFile != nil {
                if linkerOptions != "" {
                    linkerOptions += "\", \""
                }
                linkerOptions += project.doubleEscape(project.doubleEscape(objectFile!))
            }
            else if isSwift {
                engine.error( "Swift files must have been built in Xcode first" )
                return false
            } else {
                imports += "#import \"\(sourceFile)\"\n"
            }

            anySwift = anySwift || isSwift
        }

        // swift runtime libraries
        linkerOptions += "\", \"-L'\(toolchain)'/usr/lib/swift/\\$(PLATFORM_NAME)"

        // app's frameworks????
        if project.logRoot != nil {
            linkerOptions += "\", \"-F\(U(project.logRoot))/../../Build/Products/\\$(CONFIGURATION)-\\$(PLATFORM_NAME)"
        }

        // build Params used to determine local path of app bundle being built
        if buildParams == nil {
            let paramsFile = archFile( "build_params.txt" )
            if !File.exists( paramsFile ) {
                project.execute( "Fetching project build parameters",
                    command: "\(xcodebuildCommand) -showBuildSettings >\"\(paramsFile)\"",
                    workingDirectory: project.projectRoot )
            }

            // regexp parse output and load as dictionary
            buildParams = U(File.read( paramsFile )).to_s["    (\\w+) = ([^\n]*)"].dictionary()
        }

        // pod frameworks in app bundle
        if var localAppBundle = buildParams["CODESIGNING_FOLDER_PATH"] {

            // trying to cope with various "Locations" preferences
            if !File.exists( localAppBundle ) {
                for relative in ["../..", "../../.."] {
                    let alternateAppBundle = localAppBundle["^.*/Build/"]["\(U(project.logRoot))/\(relative)/Build/"]
                    if File.exists( alternateAppBundle ) {
                        engine.debug( "localAppBundle: \(localAppBundle) --> \(alternateAppBundle)" )
                        localAppBundle = alternateAppBundle
                    }
                }
            }

            if anyStoryboard {
                engine.debug( "nibBundle: \(nibBundle)" )
                ////nibBundle = localAppBundle
            }

            // does app use framworks - they can all be found in app bundle
            let frameworkDir = "\(localAppBundle)/Frameworks"
            if File.exists(frameworkDir) {
                linkerOptions += "\", \"-F\(frameworkDir)"
            }
        }

        // patch pbxproj file in .xcproject package if required
        U(RegexpFile( pbxprojFile ))["(OTHER_LDFLAGS = \\().*?(\"-undefined)", .DotMatchesLineSeparators] =~ "$1\"\(linkerOptions)\", $2"

        // Update BundleContents.m for flags and #imports of unknown classes
        let flagsChanged = U(RegexpFile( bundleContents ))["(autoLoadedNotify:)\\d+"] =~ "$1\(notify)"
        let includesChanged = U(RegexpFile( bundleContents ))["\n(// INJECTING.*|)$", .DotMatchesLineSeparators] =~ "\n// INJECTING\n\n\(imports)"

        // make sure BundleContents.m gets rebuilt
        if flagsChanged || includesChanged || imports != "" {
            File.unlink_f( "\(injectionRoot)/\(builtFile)" )
        }

        return true
    }

    private var xcodebuildCommand: String {
        return "\(engine.xcodePath)/Contents/Developer/usr/bin/xcodebuild \(engine.clientApp.config())"
    }

    /**
        xcodebuildBundleProject Perform actual build of bundle

        :param: rebuilding used to give single retry when ".pch header out of date" error encountred

        :returns: path to bundle that has been prepared
    */
    private func xcodebuildBundleProject( rebuilding: Bool = false ) -> String? {

        // recording is where slow xcodebuild is used
        var recording = mtime( pbxprojFile ) > mtime( commandsFile ), rebuild = false
        var commands = "", output = ""
        var bundlePath: String!

        // normally a script with three clang commands would be used
        var buildCommand = "/bin/bash \"\(commandsFile)\""
        if recording {
            buildCommand = xcodebuildCommand

            // make sure BundleContents.m gets rebuilt
            project.execute( "Touch BundleContent.m",
                command: "touch \"\(injectionRoot)/BundleContents.m\"" )
        }

        engine.progress( "Preparing Bundle"+(recording ? " (first injection is a little slow)" : "" ), detail: buildCommand )

        for line in BashSequence( buildCommand, workingDirectory: injectionRoot ) {
            output += line+"\n"
            var line = line

            // switch uses SwiftRegexp version of ~= operator to match by regexp
            switch line {

                // this is where path to bundle that has been built is done - it is always touched
            case "(/usr/bin/touch -c (\"([^\"]+)\"|(\\S+(\\ \\S*)*)))|ddsymutil (.+/InjectionBundle.bundle)/InjectionBundle":
                let groups = lastRegexMatchGroups
                bundlePath = groups[4] ?? groups[3] ?? groups[6]
                if bundlePath == nil {
                    engine.error("Could not determine bundle path")
                }
                fallthrough

                // capture compile/link/touch commands
            case "/usr/bin/(clang|\\S*gcc)":
                if line["-header -arch"] {
                    break
                }
                if line["BundleContents\\.m"] {
                    line = "if [[ ! -f \(builtFile) ]]; then \(line) && touch \(builtFile); fi"
                }
                commands += "echo \"\(line)\" && time \(line) &&\n"
                ///engine.debug( line )

                // check for problematic errors that require rebuild after clean
            case "has been modified since the precompiled header|malformed or corrupted AST file":
                rebuild = true

            default:
                break
            }
        }

        if ( yieldTaskExitStatus != 0 ) {

            // error has occured in build, retry with xcodebuild
            File.delete( commandsFile )

            // can retry
            if rebuild && !rebuilding {
                project.execute( "Cleaning project",
                    command: "\(xcodebuildCommand) clean", workingDirectory: injectionRoot )
                return xcodebuildBundleProject( true )
            }

            engine.error( "Bundle build failed", detail:output )
            return nil
        }

        // complete recording of commands file to use next time
        if recording {
            commands += "echo && echo '** RECORDED BUILD SUCCEEDED **' && echo;\n"
            File.write( commandsFile, commands )
        }

        // return path to bundle created
        return bundlePath != nil ? bundlePath["\\\\(.)"]["$1"] : nil
    }

    /**
        file modification time

        :param: filepath path to file

        :returns: UNIX timestamp
    */
    private func mtime( filepath: String ) -> NSTimeInterval {
        return File.exists( filepath ) ? File.mtime( filepath )?.to_f ?? 0.0 : 0.0
    }

}
