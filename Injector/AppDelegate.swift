//
//  AppDelegate.swift
//  Injector
//
//  Created by John Holdsworth on 07/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Injector/Injector/AppDelegate.swift#8 $
//
//  Repo: https://github.com/johnno1962/Injector
//

import Cocoa
import WebKit

private var appDelegate: InjectorAppDelegate!

extension NSWindow {

    @objc func _canBecomeKeyWindow() -> Bool {
        return self == appDelegate.licensePanel || self == appDelegate.parameters || self._canBecomeKeyWindow()
    }

}

@objc enum INBundleState: Int32 {
        case OK, Idle, Stale, Connected, Building, Injected, CompileError, LoadingError, Invalid
}

//@NSApplicationMain
@objc(InjectorAppDelegate)
public class InjectorAppDelegate: NSObject, NSApplicationDelegate, WebPolicyDelegate {

    public class func main() {
        NSApplicationMain( 0,  UnsafeMutablePointer<UnsafeMutablePointer<CChar>>(nil) )
    }

    @IBOutlet var console: NSWindow!
    @IBOutlet var statusMenu: NSMenu!
    @IBOutlet weak var webView: WebView!
    @IBOutlet weak var popoverView: NSPopover!
    @IBOutlet weak var projectMenu: NSMenuItem!

    @IBOutlet var parameters: NSWindow!
    @IBOutlet var valuesSuperview: NSView!
    @IBOutlet var paramsSuperview: NSView!
    @IBOutlet var slidersSuperview: NSView!
    @IBOutlet var colorWellsSuperView: NSView!
    @IBOutlet var colorSummary: NSTextField!

    @IBOutlet var watchButton: NSButton!
    @IBOutlet var storyButton: NSButton!
    @IBOutlet var orderButton: NSButton!
    @IBOutlet var notifyButton: NSButton!

    @IBOutlet var licensePanel: NSWindow!
    @IBOutlet var licenseKey: NSTextField!

    private var lastStart: NSTimeInterval = 0.0
    private var statusItem: NSStatusItem!

    private var clientApp: ClientApp!
    private var resources: Resources!
    private var autoOpened = false

    var engine: InjectorEngine!

    public func applicationDidFinishLaunching(aNotification: NSNotification) {

        appDelegate = self

        method_exchangeImplementations(
            class_getInstanceMethod( NSWindow.self, "canBecomeKeyWindow" ),
            class_getInstanceMethod( NSWindow.self, "_canBecomeKeyWindow" ) )

        let statusBar = NSStatusBar.systemStatusBar()
        statusItem = statusBar.statusItemWithLength(statusBar.thickness)
        statusItem.toolTip = "Injector Plugin"
        statusItem.highlightMode = true
        statusItem.menu = statusMenu
        statusItem.enabled = true
        statusItem.title = ""

        updateState(.Stale)

        console.alphaValue = 0.9
        console.backgroundColor = NSColor( deviceWhite: 0.3, alpha: 0.9 )
        NSColor.setIgnoresAlpha( false )

        let url = NSURL( fileURLWithPath: pathForResource( "console", ofType:"html" ) )
        webView.mainFrame.loadRequest(NSURLRequest(URL: url))
    }

    public func webView(webView: WebView!, decidePolicyForNavigationAction actionInformation: [NSObject : AnyObject]!, request: NSURLRequest!, frame: WebFrame!, decisionListener listener: WebPolicyDecisionListener!) {
        if let url = request.URL where url.scheme == "http" {
            NSWorkspace.sharedWorkspace().openURL( url )
            listener.ignore()
        }
        else {
            listener.use()
        }
    }

    func webView(sender: WebView!, didFinishLoadForFrame frame: WebFrame!) {

        progress( "<b>Welcome to Injector!</b>" )

        clientApp = ClientApp( ui: self )

        engine = InjectorEngine( UI: self, clientApp: clientApp )

        resources = Resources( ui: self )

        //keepAliveXPC()
    }

    private func keepAliveXPC() {
        engine.keepAlive( clientApp.arch, os: clientApp.os )
        clientApp.keepAlive()
        dispatch_after( dispatch_time( DISPATCH_TIME_NOW, Int64(2 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), keepAliveXPC )
    }

    func webView( webView:WebView, addMessageToConsole message: NSDictionary ) {
        NSLog( "InjectorConsole: \(message)" )
    }

    private func callJavascriptFunction( function: String, with: String ) {
        dispatch_async( dispatch_get_main_queue(), {
            self.webView.windowScriptObject.callWebScriptMethod( function, withArguments: [with] )
            return
        } )
    }

    func setMenuIcon( tiffName: String ) {
        if let path = pathForResource( tiffName, ofType:"tif" ) {
            statusItem.image = NSImage( contentsOfFile:path )
        }
    }

    func updateState( newState: INBundleState ) {
        switch (newState) {
        case .Stale:
            statusItem.toolTip = "Injector Not Connected"
            setMenuIcon("InjectionStale")
        case .Idle:
            statusItem.toolTip = "Injector Was Connected"
            setMenuIcon("InjectionIdle")
        case .OK:
            statusItem.toolTip = "Injector Connected to Xcode"
            setMenuIcon("InjectionOK")
        case .Connected:
            statusItem.toolTip = "Injector Connected"
            setMenuIcon("InjectionConnected")
        case .Building:
            statusItem.toolTip = "Injector Building"
            setMenuIcon("InjectionBuilding")
        case .Injected:
            statusItem.toolTip = "Injector Successful"
            setMenuIcon("InjectionConnected")
        case .CompileError:
            statusItem.toolTip = "Injector Compilation Error"
            setMenuIcon("InjectionError")
        case .LoadingError:
            statusItem.toolTip = "Injector Bundle Load Error, Check app console"
            setMenuIcon("InjectionError")
        default:
            error("Invalid status \(newState.rawValue)")
        }
    }

    func detachableWindowForPopover(popover: NSPopover!) -> NSWindow! {
        return console
    }

    @IBAction func installAgent( sender: NSMenuItem! ) {
        resources.installAgent()
    }

    @IBAction func removeAgent( sender: NSMenuItem! ) {
        resources.removeAgent()
    }

    @IBAction func enterLicense( sender: NSButton! ) {
        enterLicenseString( licenseKey.stringValue )
    }

    private func repoName( item: NSMenuItem ) -> String! {
        let repoName = item.menu!.supermenu!.itemAtIndex( item.tag )!.title
        if repoName == "Injector" {
            return nil
        }
        else if repoName == "Xprobe" {
            return "XprobePlugin"
        }
        return repoName
    }

    @IBAction func buildPlugin( sender: NSMenuItem! ) {
        dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), {
            self.resources.buildPlugin( self.repoName( sender ) )
            return
        } )
    }

    @IBAction func removePlugin( sender: NSMenuItem! ) {
        dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), {
            self.resources.buildPlugin( self.repoName( sender ) )
            return
        }  )
    }

    @IBAction func openPlugin( sender: NSMenuItem! ) {
        openURL( "https://github.com/johnno1962/\(repoName( sender ))" )
    }

    @IBAction func showOverview( sender: NSMenuItem ) {
        openURL( "http://totallydope.io" )
    }

    private func openURL( url: String ) {
        NSWorkspace.sharedWorkspace().openURL( NSURL( string: url )! )
    }

    @IBAction func resetProject( sender: NSMenuItem ) {
        engine.reset()
    }

    @IBAction func patchProject( sender: NSMenuItem ) {
        engine.patch()
    }

    @IBAction func unpatchProject( sender: NSMenuItem ) {
        engine.unpatch()
    }

    @IBAction func openBundle( sender: NSMenuItem ) {
        engine.openBundle()
    }

    func displayParameters() {
        displayParameters( nil )
    }

    @IBAction func displayParameters( sender: NSMenuItem! ) {
        parameters.makeKeyAndOrderFront(sender)
    }

    @IBAction func parameterChanged( sender: NSSlider ) {
        let valueField = valuesSuperview.viewWithTag(sender.tag) as! NSTextField
        valueField.stringValue = "\(sender.stringValue)"
        clientApp.clientSend( "\(sender.tag)\(sender.stringValue)" )
    }

    @IBAction func rangeChanged( sender: NSTextField ) {
        let slider = slidersSuperview.viewWithTag(sender.tag) as! NSSlider
        let newRange = (sender.stringValue as NSString).doubleValue
        slider.maxValue = newRange
    }

    @IBAction func colorChanged( sender: NSColorWell ) {
        let colorString = stringForColorWell( sender )
        colorSummary.stringValue = "Color changed: rgba = {\(colorString)}"
        clientApp.clientSend( "\(sender.tag+INJECTION_PARAMETERS)\(colorString)" )
    }

    private func stringForColorWell( colorWell: NSColorWell ) -> String {
        if let color = colorWell.color.colorUsingColorSpaceName(NSCalibratedRGBColorSpace) {
            var r: CGFloat = 1.0, g: CGFloat = 1.0, b: CGFloat = 1.0, a: CGFloat = 1.0
            color.getRed( &r, green:&g, blue:&b, alpha:&a )
            return "\(r),\(g),\(b),\(a)"
        } else {
            error( "colorUsingColorSpaceName error" )
            return "1,1,1,1"
        }
    }

    @IBAction func watchChaged( sender: NSButton! ) {
        engine.watchProject( shouldFileWatch )
    }

    @IBAction func quit( sender: NSMenuItem ) {
        NSApplication.sharedApplication().terminate(sender)
    }

    public func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }

}

extension InjectorAppDelegate {

    func pathForResource( name: String, ofType ext: String! ) -> String! {
        if let path = NSBundle.mainBundle().pathForResource(name, ofType: ext) {
            return path
        } else {
            error("Could not locate resource \(name).\(ext)" )
            return nil
        }
    }

    func clientSend( path: String!, data: NSData! = nil ) {
        if clientApp != nil && clientApp.connected {
            clientApp.clientSend( path, data: nil )
        }
    }

    func allParameterValues() -> [AnyObject]! {
        var paramters = [String]()
        for pno in 0..<INJECTION_PARAMETERS {
            paramters.append( (slidersSuperview.viewWithTag(Int(pno)) as! NSSlider).stringValue )
        }
        for pno in 0..<INJECTION_PARAMETERS {
            let colorWell = colorWellsSuperView.viewWithTag(Int(pno))! as! NSColorWell
            paramters.append( stringForColorWell( colorWell ) )
        }
        return paramters
    }

    func onDemandBundlePath( isOSX: Bool ) -> String! {
        return resources.onDemandBundlePath( isOSX )
    }

    func activeProject( projectName: String! ) {
        dispatch_async( dispatch_get_main_queue(), {
            self.projectMenu.title = projectName
        } )
    }

    func enterLicenseString( key: String! ) {
        engine.enterLicense( key, returning: {
            (response: String!) in
            self.licensePanel.orderOut( self )
            self.error( response )
        } )
    }

    func appPath() -> String! {
        return NSBundle.mainBundle().bundlePath
    }

    var shouldFileWatch: Bool {
        return watchButton.state != 0
    }

    var injectStoryboards: Bool {
        return storyButton.state != 0
    }

    var shouldNotify: Bool {
        return notifyButton.state != 0
    }

    var shouldOrderFront: Bool {
        return orderButton.state != 0
    }

    func progress( msg: String!, detail: String! = nil ) {
        let now = NSDate.timeIntervalSinceReferenceDate()
        if lastStart != 0.0 {
            callJavascriptFunction( "logUpdate", with: NSString( format: " %.3fs", now-lastStart ) as String )
        }

        var msg = msg
        if detail != nil {
            let detail = detail.stringByReplacingOccurrencesOfString( "\n", withString: "<br>" )
            msg = msg + " <span><a href='#' onclick='return showDetail(this)'>" +
                "show detail</a><span style='display:none'>\(detail)</span></span>"
            lastStart = now
        } else {
            lastStart = 0.0
        }
        #if DEBUG
        log( msg )
        #endif
        callJavascriptFunction( "logAdd", with:msg )
    }

    func error( msg: String!, detail: String! = nil ) {
        log( "Injector Error: \(msg): \(detail)" )
        let consoleDetail = ""////detail != nil ? detail["([^\\n])$"]["$1\n"] : ""
        clientApp?.console( consoleDetail+msg )
        progress( "<b class=error>"+msg+"</b>", detail: detail )

        if clientApp != nil { //&& !clientApp.connected {
            dispatch_async( dispatch_get_main_queue(), {
                self.console.orderFront( self )
            } )
            autoOpened = true
            // popoverView.showRelativeToRect(statusItem.button!.frame, ofView: statusItem.button!, preferredEdge: NSMaxYEdge)
        }
    }

    func debug( msg: String ) {
        #if DEBUG
        log( msg )
        #endif
    }

    func log( msg: String ) {
        NSLog( "Injector: \(msg)"["%"]["%%"] )
    }

}

extension InjectorAppDelegate {

    func clientConnected(arch: String!, os: String!, executable: String!) {
        progress( "Client connected, arch: \(arch)", detail: executable )
        engine.clientConnected( arch, os: os, executable: executable )
        updateState( .Connected )
    }

    func bundleLoaded(success: Bool) {
        updateState( success ? .Connected : .LoadingError )
        engine.bundleLoaded( success )
        if success && autoOpened {
            console.orderOut( self )
        }
    }

    func clientDisconnected() {
        progress( "Disconnected" )
        updateState( .OK )
        engine.watchProject( false )
    }

}
