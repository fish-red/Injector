//
//  XcodeProject.swift
//  Injector
//
//  Created by John Holdsworth on 07/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/InjectorEngine/XcodeProject.swift#6 $
//
//  Repo: https://github.com/johnno1962/Injector
//

import Foundation
import SwiftRuby

public class XcodeProject {

    /**
        InjectorEngine instance
    */
    weak var engine: InjectorEngine!

    let projectRoot: String
    var projectPath: String!
    var projectFile: String!
    var projectName: String!
    var nibCompiled: String?

    /**
        Best guess at where .xcactivity logs are to be found
    */
    let logRoot: String?

    init?( _ workspacePath:String, _ logDirectory: String?, engine: InjectorEngine ) {
        self.engine = engine

        if let groups = workspacePath["^(.+?/([^/]+))/(([^/]*)\\.(xcodeproj|xcworkspace|(idea/misc.xml)))"].groups() {
            projectPath = groups[0]
            projectRoot = groups[1]!
            projectFile = groups[3]
            projectName = groups[4]

            if projectName == "" {
                projectName = groups[2]
            }

            // AppCode
            if groups[6] != nil {
                projectFile = "\(projectName).xcworkspace"
                projectPath = "\(projectRoot)/\(projectFile)"

                if !File.exists( projectPath ) {
                    projectFile = "\(projectName).xcodeproj"
                    projectPath = "\(projectRoot)/\(projectFile)"
                }

                if !File.exists( projectPath ) {
                    engine.error( "Could not divine projectFile",
                        detail: "\(workspacePath) --> \(projectPath)" )
                }
            }

            if logDirectory != nil {
                logRoot = logDirectory
            } else {
                // user has fiddled with their "Locations" preferences
                let hash = engine.plugin.hashStringForPath( projectPath ) // have to recover linkely build area for logs
                logRoot = "\(NSHomeDirectory())/Library/Developer/Xcode/DerivedData/\(projectName)-\(hash)/Logs/Build"
                if File.exists( U(logRoot) ) {
                    engine.debug( "Guessed logs directory: \(U(logRoot)) -- \(workspacePath)" )
                } else {
                    engine.error( "Could not guess logs directory", detail: "\(U(logRoot)) -- \(workspacePath)" )
                }
            }
        } else {
            engine.error( "Could not parse workspace document \(workspacePath)" )
            projectRoot = workspacePath
            projectPath = nil
            projectFile = nil
            projectName = nil
            logRoot = nil
            return nil
        }
    }

    /**
        Path to injection bundle project
    */
    var injectionRoot: String {
        return "\(File.dirname( File.dirname( U(logRoot) )! )!)/\(U(engine.os))InjectorProject"
    }

    /**
        Project looks like it for and OSX application (determines "on Demand" bundle loaded when not connected)
    */
    func looksLikeOSXProject() -> Bool {
        let pbxproj: String! = U(File.read( "\(projectRoot)/\(projectName).xcodeproj/project.pbxproj" )).to_s
        return pbxproj != nil && pbxproj["MACOSX_DEPLOYMENT_TARGET ="] && !pbxproj["IPHONEOS_DEPLOYMENT_TARGET ="]
    }

    // MARK: Compilation

    /**
        Go through list of modified files finding compile command and executing it

        :param: modifiedSourceFiles source files wich have changed

        :param: evalCode code to add to source file for Xprobe evaluate

        :returns: List of object files for source files that have been compiled
    */
    func findCommandsAndRecompile( modifiedSourceFiles: [String], evalCode: String? ) -> [String?]? {
        ////var isSwift = false

        var objectFiles = [String?]()
        var objectNum = 0

        for sourceFile in modifiedSourceFiles {

            // determine compile command if we don't already know it
            if engine.compileCommands[sourceFile] == nil {
                if let compileCommand = buildCommandForSourceFile( sourceFile, arch: U(engine.arch) ) {
                    engine.compileCommands[sourceFile] = compileCommand
                } else if evalCode == nil {
                    objectFiles.append( nil )
                    continue
                }
            }

            // source can be built, patch in tmp object file path and add to those returned
            let objectPath = "/tmp/injecting_class\(objectNum++)_\(engine.user).o"
            let compileCommand = (engine.compileCommands[sourceFile] ?? "")[" -o .*$"][" -o \(doubleEscape(objectPath))"]
            objectFiles.append(objectPath)

            // code supporting Xprobe eval by patching category or entension onto source file
            let additionsTag = "// added by XprobePlugin eval //"
            let existingPatch = "\n*(\(additionsTag).*|$)"

            if evalCode != nil {

                if let sourcePathReturned = engine.sourcesForClasses[sourceFile] {

                    if !File.exists( sourcePathReturned ) {
                        engine.error( "Unable to find source for class \(sourceFile)", detail: sourcePathReturned )
                        return nil
                    }

                    // get eval patch to add to end of source file
                    let isSwift = sourceFile["\\.swift"]
                    let codeAddition = U(File.read( U(engine.ui.pathForResource( isSwift ? "swift" : "objc", ofType: "eval" )) )).to_s.mutableString

                    // substitute in required info and code being evaluated
                    codeAddition["__INTERFACE_HEADER__"] =~ U(engine.ui.pathForResource( "BundleInterface", ofType: "h" ))
                    codeAddition["__ADDITIONS_TAG__"] =~ additionsTag
                    codeAddition["__CLASS_NAME__"] =~ U(File.extremoved(sourceFile))
                    codeAddition["__CODE__"] =~ templateEscape( U(evalCode) )

                    // make sure FileWatcher doesn't pick up patch
                    engine.lockout( sourcePathReturned, isFileWatcher: false )

                    // save to source and inject to call onXprobeEval when injected
                    RegexpFile( sourcePathReturned )![existingPatch] =~ [templateEscape( codeAddition as String )]
                } else {
                    engine.error( "No source returned for class", detail: sourceFile )
                    return nil
                }
            }

            // perform the actual compile of the source
            if !execute( "Compiling "+File.basename(sourceFile)!,
                    command: compileCommand, workingDirectory: projectRoot ) {
                return nil
            }

            // remove Xprobe eval patch
            if evalCode != nil {
                if let sourcePathReturned = engine.sourcesForClasses[sourceFile] {
                    // make sure FileWatcher doesn't pick up unpatch
                    engine.lockout( sourcePathReturned, isFileWatcher: false )
                    // reverse Xprobe eval patch
                    RegexpFile( sourcePathReturned )![existingPatch] =~ ["\n"]
                }
            }
        }

        return objectFiles
    }

    /**
        Determine the build command for a particular source file from xcactivity logs

        :param: sourceFile file that has changed or pattern to find file for Xprobe Eval

        :param: isEvalRegexp Xprobe Eval is in progress sourceFile is a pattern

        :returns: command that can be executed by shell to build the source
    */
    public func buildCommandForSourceFile( sourceFile: String, arch: String ) -> String? {
        var xcarchives: [NSString]
        if logRoot != nil && File.exists( U(logRoot) ) {
            xcarchives = [String]( BashSequence( "ls -t \"\(U(logRoot))\"/*.xcactivitylog" ) )
        } else {
            engine.error( "Build logs not available. Build file in xcode first" )
            // -dry-run parsing someday
            return nil
        }

        // determine patternto be used to file entry in xcactivity log
        var filename = File.basename(sourceFile)!
        let quotedPattern: String, escapedPattern: String
        let hasFullPath = sourceFile.hasPrefix( "/" )

        if hasFullPath {
            engine.progress( "Learning compile for \(filename)", detail:"\(xcarchives)" )
            quotedPattern = sourceFile
            escapedPattern = templateEscape( backslashEscape( sourceFile ) )
        } else {
            filename = sourceFile
            quotedPattern = "/[^\" ]+(?: [^\" ]*)*?/" + sourceFile["(\\.m)$"]["$1m?"]
            escapedPattern = "/[^\" ]+(?:\\\\ [^\" ]*)*?/" + sourceFile["(\\.m)$"]["$1m?"]
        }

        // filename can be either double quoted (swift) or "\" escaped in logs
        let finalFileFilter = "(?:\"(\(quotedPattern))\"|(\(escapedPattern)))"

        if sourceFile["\\.(storyboard|xib)$"] {

            // return command to recompile storyboard/nib
            for log in xcarchives {
                for line in CommandSequence( "gunzip <\"\(log)\"", workingDirectory: "/tmp",
                    linesep: "\r", filter: filename ) {
                    if line.rangeOfString( "/usr/bin/ibtool " ) != nil &&
                        line[finalFileFilter] {
                            U(engine.runProject).nibCompiled = line["-compilation-directory (.*?)/\\w+.lproj"][1]
                            return line
                    }
                }
            }

        } else {

            // return command to recompile Swift or Objective-C source
            let finalFileFilter = (sourceFile["\\.swift$"] ? " -primary-file " :
                    sourceFile["\\.mm?$"] ? " -c " :  " -(?:primary-file|c) ") +
                    finalFileFilter

            engine.debug( "finalFileFilter: \(finalFileFilter)" )

            var chdir = projectRoot
            for log in xcarchives {
                // grepping on an OR of two filters, the second of which must be at the beginning of the line
                for line in CommandSequence( "gunzip <\"\(log)\"", workingDirectory: "/tmp",
                        linesep: "\r", filter: filename, filter2: "    cd " ) {

                            // compile driectory is important so we have to capture it
                    if line["^    cd "] {
                        chdir = line["^    cd (.*)"][1]!
                    }

                    // otherwise if line matches finalFileFilter we have our command
                    else if line.rangeOfString( "XcodeDefault.xctoolchain/" ) != nil &&
                        line.rangeOfString( " \(arch)" ) != nil &&
                        line[finalFileFilter] {

                            // on Xprobe eval capture actual file path found
                            if !hasFullPath {
                                let groups = U(line[finalFileFilter].groups())
                                engine.sourcesForClasses[sourceFile] = groups[1] != nil ?
                                                                groups[1]! : groups[2]!["\\\\"][""]
                                engine.debug( "sourcesForClasses: \(engine.sourcesForClasses[sourceFile])" )
                            }

                            // clean up cd directory for compile command
                            var chdir = U(chdir)
                            if !chdir["^\""] {
                                chdir = "\""+chdir+"\""
                            }

                            // compile command is cd + compiler command
//                            #if DEBUG
//                                logRegexpTest( sourceFile, arch, engine.sourcesForClasses[sourceFile], "    cd "+chdir, line )
//                            #endif
                            return "cd \(chdir) && \(line)"
                    }
                }
            }
        }

        if !hasFullPath {
            return createCompileCommandForDummyFileOnEvalOfClassWithoutSource( sourceFile )
        }

        engine.error( "Could not locate compile command for: "+sourceFile, detail: finalFileFilter )
        return nil
    }

    /**
        createCompileCommandForDummyFileOnEvalOfClassWithoutSource like it says on the cover

        :param: sourceFileRegexp regexp that has been used to search for source file

        :returns: compile command to build dummy Objective-C source
    */
    private func createCompileCommandForDummyFileOnEvalOfClassWithoutSource( sourceFile: String ) -> String {
        let className = U(File.extremoved(sourceFile))
        let tmpSource =  "/tmp/injection_\(engine.user)_\(className).m"

        engine.sourcesForClasses[sourceFile] = tmpSource

        // create dummy source file
        let isOSX = engine.clientApp.isOSX, isSimulator = engine.clientApp.isSimulator
        let unknown = U(File.read( U(engine.ui.pathForResource( "unknown", ofType: "m_" )) )).to_s.mutableString
        unknown["__HEADER__"] =~ (isOSX ? "Cocoa/Cocoa.h" : "UIKit/UIKit.h")
        unknown["__CLASS_NAME__"] =~ className
        File.write( tmpSource, unknown as String )

        // create command to build it and return
        let compileCommand = U(File.read( U(engine.ui.pathForResource( "unknown", ofType: "sh" )) )).to_s.mutableString
        compileCommand["__XCODE__"] =~ engine.xcodePath
        compileCommand["__ARCH__"] =~ U(engine.arch)
        compileCommand["__MINVERS__"] =~ (isOSX ? "10.6" : "6.0")
        let platform = isOSX ? "MacOSX" : "iPhone"+(isSimulator ? "Simulator" : "OS")
        compileCommand["__PLATFORM__"] =~ platform
        compileCommand["__PLATFORM2__"] =~ (isOSX ? "MacOSX10.10" : platform )
        compileCommand["__SOURCE__"] =~ tmpSource
        compileCommand["__SDK__"] =~ (isOSX ? "macosx" : isSimulator ? "ios-simulator" : "iphoneos" )
        return compileCommand as String
    }

    // MARK: utility functions

    func patchFilesMatching( pattern: String, replace: String, with template: String ) -> Bool {
        var patched = false
        for file in BashSequence( "find \"\(projectRoot)\" | grep -E '(\(pattern))$' | grep -vE '(Injector|Injection)Project'" ) {
            if RegexpFile( file )![replace, .DotMatchesLineSeparators] =~ [template] {
                engine.open( file )
                patched = true
            }
        }
        return patched
    }

    /**
        escape any \ and $ for use in a template in a substitution

        :param: template

        :returns: template with "\" and "$" escaped to preserve them
    */
    private func templateEscape( template: String ) -> String {
        return template["\\\\"]["\\\\\\\\"]["\\$"]["\\\\$"]
    }

    /**
        escape file path as Xcode does in compile commands

        :param: filepath as received from injectSources

        :returns: filepath as Xcode would escape it in .xcactivity logs
    */
    private func backslashEscape( filepath: String ) -> String {
        return filepath["[' ]"]["\\\\$0"]
    }

    /**
        escape twice to be sent to shell

        :param: filepath

        :returns: filpath with "'" and " " escaped twice
    */
    func doubleEscape( filepath: String ) -> String {
        return backslashEscape(backslashEscape(filepath))
    }

    /**
        Execute a command and display output if there is an error

        :param: command to execute in using /bin/bash -c

        :param: working directory for task

        :returns: whether command was successful
    */
    func execute( reason: String, command: String, workingDirectory: String = "/tmp" ) -> Bool {
        engine.progress( reason, detail: command )

        var output = ""
        for line in BashSequence( command, workingDirectory: workingDirectory ) {
            output += line+"\n"
        }

        if yieldTaskExitStatus != 0 {
            engine.error( "\(reason) failed", detail:output )
            return false
        }

        return true
    }

}
