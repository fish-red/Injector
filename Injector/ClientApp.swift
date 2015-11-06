//
//  ClientApp.swift
//  Injector
//
//  Created by John Holdsworth on 07/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/Injector/ClientApp.swift#5 $
//
//  Repo: https://github.com/johnno1962/Injector
//

import Foundation
import SwiftRuby

import InjectorPlugin

private let INJECTION_MAJIC = off_t(-INJECTOR_PORT*INJECTOR_PORT)

let INJECTION_PARAMETERS = 5
let INJECTION_FLAGCHANGE = (1<<0)
let INJECTION_STORYBOARD = (1<<1)
let INJECTION_NOTSILENT  = (1<<2)
let INJECTION_ORDERFRONT = (1<<3)
let INJECTION_USEAPPCODE = (1<<4)
let INJECTION_DEVICEIOS8 = (1<<5)

@asmname("fcntl")
private func fcntl( filedesc: Int32, _ command: Int32, _ arg: Int32 ) -> Int32

// socket shenanigans
private let INADDR_ANY = in_addr_t(0)
private let htons = Int(OSHostByteOrder()) == OSLittleEndian ? _OSSwapInt16 : { $0 }
private func sockaddr_cast(p: UnsafeMutablePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> {
    return UnsafeMutablePointer<sockaddr>(p)
}
private let clientQueue = dispatch_queue_create("InjectorClient", DISPATCH_QUEUE_CONCURRENT)

/**
    The three types of client app that can be connected
*/
private enum ClientType {
    case Sim
    case Device
    case OSX
}

/**
    Instance representing the connection to a client application
*/
@objc(ClientApp)
class ClientApp : NSObject {

    private weak var ui: InjectorAppDelegate!
    private let manager = NSFileManager.defaultManager()

    private var ip4addr = sockaddr_in(sin_len: 0,
        sin_family: sa_family_t(AF_INET), sin_port: htons(UInt16(INJECTOR_PORT)), sin_addr: in_addr(s_addr: INADDR_ANY),
        sin_zero: (Int8(0),Int8(0),Int8(0),Int8(0),Int8(0),Int8(0),Int8(0),Int8(0)))

    /**
        Socket on which to accept() new connections from client apps
    */
    private let serverSocket: Int32

    /**
        TCP socket connection to currently connected client app
    */
    private var clientSocket: Int32?

    /**
        Path to binary being executed
    */
    private var executablePath: String?

    /**
        As of iOS8 a different path returned by NSHomeDirectory()
    */
    private var deviceRoot: String?

    /**
        Whether app is connected (not quite the same as clientSocket != nil)
    */
    var connected = false

    /**
        Architecture reported by NXGetArchInfoFromCpuType()
    */
    var arch: String?

    /**
        Type of client connected
    */
    private var type: ClientType = .Sim

    /**
        Is physical device as opposed to simulator
    */
    private var isDevice: Bool {
        return type == .Device
    }

    /**
        Is running in simulator
    */
    var isSimulator: Bool {
        return type == .Sim
    }

    /**
        is running iOS on device or in simulator
    */
    var isOSX: Bool {
        return type == .OSX
    }

    /**
        OS name used to determine bundle project template and name
    */
    var os: String {
        return isOSX ? "OSX": "iOS"
    }

    /**
        Increments to give continually changing bundle names so they reload
    */
    private var injectionNumber = 0

    /**
        Convenience for socket errors
    */
    private func Strerror( msg: String ) {
        ui.error( "Injector: "+msg, detail: String( UTF8String: strerror(errno) )! )
    }

    init( ui: InjectorAppDelegate ) {
        self.ui = ui

        serverSocket = socket(AF_INET, SOCK_STREAM, 0)

        super.init()

        var yes: u_int = 1, yeslen = socklen_t(sizeof(yes.dynamicType))

        if serverSocket < 0 {
            Strerror( "Could not get mutlicast socket" )
        }
        else if fcntl( serverSocket, F_SETFD, FD_CLOEXEC ) < 0 {
            Strerror( "Could not set close exec" )
        }
        else if setsockopt( serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, yeslen ) < 0 {
            Strerror( "Could not set SO_REUSEADDR" )
        }
        else if setsockopt( serverSocket, IPPROTO_TCP, TCP_NODELAY, &yes, yeslen ) < 0 {
            Strerror( "Could not set TCP_NODELAY" )
        }
        else if Darwin.bind( serverSocket, sockaddr_cast(&ip4addr), socklen_t(sizeof(ip4addr.dynamicType)) ) < 0 {
            Strerror( "Could not bind service socket on port \(INJECTOR_PORT)" )
        }
        else if listen( serverSocket, 5 ) < 0 {
            Strerror( "Service socket would not listen" )
        } else {
            dispatch_async( clientQueue, runService )
        }
    }

    // MARK: Injector injection TCP service

    /**
        Accepts new incoming TCP connections from device in background thread
    */
    private func runService()  {
        while true {
            var addrLen = socklen_t(sizeof(ip4addr.dynamicType))
            clientSocket = accept( serverSocket, sockaddr_cast(&ip4addr), &addrLen )
            if clientSocket < 0 {
                Strerror( "Dud incomming connection accept" )
                NSThread.sleepForTimeInterval(1.0)
                continue
            }
            dispatch_async( clientQueue, serviceClient )
        }
    }

    /**
        Process a single connection from a client app through it's lifecycle
    */
    private func serviceClient() {
        var header = _in_header( pathLength: 0, dataLength: 0 )
        let buffer = [Int8]( count: 10000, repeatedValue: 0 )
        let bufferPtr = UnsafeMutablePointer<Int8>( buffer )

        // prevent Injector.app being take out bu SIGPIPE
        var optval: Int32 = 1, optlen = socklen_t(sizeof(optval.dynamicType))
        if setsockopt( serverSocket, SOL_SOCKET, SO_NOSIGPIPE, &optval, optlen ) < 0 {
            Strerror( "Could not set SO_NOSIGPIPE" )
        }

        BundleInjection.readHeader( &header, forPath: bufferPtr, from: clientSocket! )

        // don't just let anybody connect..
        if header.dataLength != Int32(INJECTION_MAJIC) {
            ui.error( "Bogus connection attemnpt",
                detail:"\(header.dataLength) != \(INJECTION_MAJIC)" )
            close( clientSocket! )
            clientSocket = nil
            return
        }

        var status = Int32((ui.injectStoryboards ? INJECTION_STORYBOARD : 1) | INJECTION_DEVICEIOS8)
        clientWrite( &status, length: sizeof(status.dynamicType) )

        BundleInjection.readHeader( &header, forPath: bufferPtr, from: clientSocket! )
        executablePath = String( UTF8String: buffer )

        // All this shenannigans is due for compatibility
        if header.dataLength != 0 {
            self.deviceRoot = self.executablePath
        } else {
            repeat {
                BundleInjection.readHeader( &header, forPath: bufferPtr, from: clientSocket! )
                deviceRoot = String( UTF8String: buffer )
            } while header.dataLength == 0
        }

        // finally read architecture
        read( clientSocket!, bufferPtr, Int(header.dataLength) )
        arch = String( UTF8String: buffer )

        // determine client type based on executable path
        switch executablePath! {
        case "/Contents/MacOS/":
            type = .OSX
        case "(iPhone |Core)Simulator":
            type = .Sim
        case "^(/private)?/var/mobile/":
            type = .Device
        default:
            ui.error( "Could not recognise executable path, assuming Simulator", detail: executablePath )
            type = .Sim
        }

        injectionNumber = 0
        connected = true

        dispatch_async( dispatch_get_main_queue(), {
            self.ui.clientConnected( self.arch,
                os: self.os, executable: self.executablePath )
        } )

        // refresh current values of parameters
        let parameters = ui.allParameterValues() as! [String]
        for parameterNumber in 0..<parameters.count {
            clientSend( "\(parameterNumber)\(parameters[parameterNumber])" )
        }

        // Loop while connected reporting bundle loading success or failure
        var loaded: Int32 = 0, loadedSize = sizeof(loaded.dynamicType)
        while read( clientSocket!, &loaded, loadedSize ) == loadedSize {
            if ( fdout == nil ) {
                dispatch_async( dispatch_get_main_queue(), {
                    self.ui.bundleLoaded( loaded != 0 )
                } )
            } else {
                // for reading a file/directory listing from a device
                BundleInjection.writeBytes( off_t(loaded), withPath:nil, from:clientSocket!, to:fdout! )
                close( fdout! )
                fdout = nil
            }
        }

        dispatch_async( dispatch_get_main_queue(), {
            self.ui.clientDisconnected()
        } )

        connected = false
        close( clientSocket! )
        clientSocket = nil
    }

    // MARK: client i/o

    /**
        Send struct _in_header  data structure to device

        :param: path bundle to load or other command for device to process

        :data: data to be included in command e.g. when downloading bundle to device
    */
    func clientSend( path: String!, data: NSData! = nil ) {
        let buffer = (path as NSString).UTF8String, pathLength = strlen(buffer)+1
        var header = _in_header( pathLength: Int32(pathLength), dataLength: Int32(data?.length ?? Int(INJECTION_MAJIC)) )

        clientWrite( &header, length: sizeof(header.dynamicType) )
        clientWrite( buffer, length: Int(pathLength) )
        if data != nil {
            clientWrite( data!.bytes, length: data!.length )
        }
    }

    /**
        Low level write to device socket logging any errors
    */
    private func clientWrite( buffer: UnsafePointer<Void>, length: Int ) {
        if clientSocket == nil || write( clientSocket!, buffer, length ) != length {
            Strerror( "Error writing to socket" )
        }
    }

    /**
        This keeps device WiFi alive during periods of inactivity
    */
    func keepAlive() {
        if clientSocket != nil && fdin == nil {
            BundleInjection.writeBytes( INJECTION_MAJIC, withPath:"", from:0, to:clientSocket! )
        }
    }

    /**
        Copy a directory (bundle) of content to the device, filtering

        :param: from local path to bundle to be copied

        :param: to device path for bundle to be copied to

        :param: pattern no longer implemented
    */
    private func copyToDevice( from: String, to: String, pattern: String! = nil ) -> String {
        ui.progress( "Sending to device", detail: "\(from) --> \(to)" )
        console( "Sending to device..." )

        localRead( from )
        remoteWrite( to )

        for file in BashSequence( "find . -print", workingDirectory: from ) {
            localRead( "\(from)/\(file)" )
            remoteWrite( "\(to)/\(file)" )
        }

        return to
    }

    // MARK: file transfer

    private var fdin: Int32?, fdout: Int32?

    /**
        Open a local file to be transferred to/from the device
    */
    private func localRead( path: String ) {
        fdin = open( path, O_RDONLY )
        if fdin! < 0 {
            Strerror( "Could not open: \(path)" )
            fdin = nil
            return
        }
        if fdout != nil {
            var fdinfo = stat()
            if fstat( fdin!, &fdinfo ) != 0 {
                Strerror( "Could not stat \"\(path)\"" )
                return
            }
            BundleInjection.writeBytes( fdinfo.st_size, withPath:nil, from:fdin!, to:fdout! )
            close( fdout! )
            close( fdin! )
            fdout = nil
            fdin = nil
        }
    }

    /**
        Open a local file for transfer from the device
    */
    private func localWrite( path: String ) {
        fdout = open( path, O_CREAT|O_TRUNC|O_WRONLY, 0o644 )
        if ( fdout! < 0 ) {
            Strerror( "Could not open output file: \(path)" )
            fdout = nil
        }
    }

    /**
        If local file is already open transfer the file to the device
    */
    private func remoteWrite( path: String ) {
        let file = (">\(path)" as NSString).UTF8String
        if fdin != nil && clientSocket != nil {
            var fdinfo = stat()
            fstat( fdin!, &fdinfo )
            let S_ISDIR = (UInt16(fdinfo.st_mode) & S_IFMT) == S_IFDIR
            let bytes = S_ISDIR ? off_t(INJECTION_MKDIR) : off_t(fdinfo.st_size)
            BundleInjection.writeBytes( bytes, withPath:file, from:fdin!, to:clientSocket! )
            close( fdin! )
            fdin = nil
        }
    }

}

extension ClientApp {

    /**
        xcodebuild arguments for build for type of app connected
    */
    func config() -> String {
        var config = "-configuration Debug -arch \(arch!)"
        if isSimulator {
            config += " -sdk iphonesimulator"
        }
        else if isDevice {
            config += " -sdk iphoneos"
        }
        return config
    }

    // MARK: inject to client

    private var appResources: String {
        return "\(File.dirname(executablePath!)!)/../Resources"
    }

    /**
        Take locally produced bundle, copy it to a varying name and send it to the device
    */
    func injectBundle( bundlePath: String, resetApp: Bool, identity: String!, nibBundle: String! ) -> Bool {
        let bundleRoot = U(File.dirname( bundlePath ))
        let incrementingBundleName = "InjectionBundle\(injectionNumber++).bundle"
        let incrementingBundlePath = "\(isOSX ? appResources : bundleRoot )/\(incrementingBundleName)"

        //injector.debug("Copying: \(bundlePath) ---> \(incrementingBundlePath)")

        for line in BashSequence( "rm -rf \"\(incrementingBundlePath)\" && " +
                    "cp -r \"\(bundlePath)\" \"\(incrementingBundlePath)\"" ) {
            ui.error( "Error copying bundle", detail: line )
            return false
        }

        // copy in nibs if injecting storyboard

        if nibBundle != nil {
            for nib in BashSequence( "find .", workingDirectory: nibBundle! ) {
                let from = "\(nibBundle!)/\(nib)", to = "\(incrementingBundlePath)/\(nib)"

                if File.ftype( from ) == "directory" { ///
                    if !File.exists( to ) {
                        Dir.mkdir( to )
                    }
                }
                else if to["\\.(nib|png|jpe?g)$"] {
                    localWrite( to )
                    localRead( from )
                }
            }
        }

        if isDevice {
            if identity == nil {
                ui.error( "Could not find codesign identity", detail: nil )
                return false
            } else {
                var output = ""
                let command = "codesign -s \"\(identity)\" \"\(incrementingBundlePath)\""
                for line in BashSequence( command ) {
                    output += line+"\n"
                }
                if yieldTaskExitStatus != 0 {
                    ui.error( "Codesigning failed", detail: output )
                    return false
                }
            }
        }

        if resetApp {
            clientSend( "~" )
        }

        loadBundle( incrementingBundlePath )
        return true
    }

    /**
        Load bundle previously sent to device
    */
    func loadBundle( bundlePath: String ) {
        var bundlePath = bundlePath

        // copy to device and message client

        if isDevice {
            bundlePath = copyToDevice( bundlePath,
                to: "\(deviceRoot!)/tmp/\(injectionNumber++)\(U(File.basename(bundlePath)))" )
        }
        else if isOSX && executablePath != nil && !bundlePath.hasPrefix( appResources ) {
            let newLocation = "\(appResources)/\(U(File.basename(bundlePath)))"
            FileUtils.cp_rf( bundlePath, newLocation )
            bundlePath = newLocation;
        }

        clientSend( bundlePath )
    }

    /**
        Load "On Demand" bundle on behalf of another plugin
    */
    func loadBundleForPlugin( resourcePath: String! ) -> Bool {
        if connected {
            let prefix = isOSX ? "OSX" : isSimulator ? "Sim" : "Device"
            let loaderPath = "\(resourcePath)/\(prefix)Bundle.loader"
            if manager.fileExistsAtPath( loaderPath ) {
                ui.progress( "Loading bundle for plugin", detail: loaderPath )
                loadBundle( loaderPath )
                return true
            } else {
                ui.error( "Bundle not available for "+prefix, detail: loaderPath )
            }
        }
        return false
    }

    /**
        Output to the Xcode console by bouncing it through the connected client App
    */
    func console( msg: String ) {
        if connected  {
            clientSend( "!Injector: "+msg, data: nil )
        }
    }

    // MARK: server IP address list

    /**
        Addresses to be used when patching the project's main.m to connect back to user's mac
    */
    func serverAddresses() -> [AnyObject]! {
        if let addresses = ui.engine.plugin.addressesForSocket( serverSocket ) {
            return addresses.sort { prec($0) > prec($1) }
        } else {
            Strerror( "Unable to determine server addresses" )
            return []
        }
    }

}

/**
    Attempt to get more relevant IP addresses tried first when client app connects back to developers mac
*/
private let ipPrecedence: [String:Int] = [
    "10": 2,
    "192": 1,
    "169": -1,
    "172": -2,
    "127": -9
]

/**
    Used in serverAddresses to sort IP addresses
*/
private func prec( addr: String ) -> Int {
    let network = addr["^(\\d+)\\."][1]!
    return ipPrecedence[network] ?? 0
}
