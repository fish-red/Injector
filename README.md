
# Injector, the Swift successor to injectionforxcode

To use Download the [Diamond](https://github.com/johnno1962/Diamond) project
and build it to enable the `diamond` scripting language based on Swift.
Then, run the `run_injector` script in the project directory. In other words
paste the following into terminal:

    cd /tmp
    rm -rf Diamond
    git clone https://github.com/johnno1962/Diamond
    cd Diamond && xcodebuild && ./run_injector

`$HOME/bin` must be in your path for `diamond` to work.

After building a few components you'll have a MenuBar application written
in Swift and once you've restarted Xcode a new plugin that communicates with
it available under the "Product/Injector Plugin" menu item.

Use the following command to edit the Injector project which
will have been cloned automatically for you:

    diamond Injector -edit

Injection is possible on the Injector project itself if you make
changes to the implementation of any Swift sources. This is the
reason Injector uses diamond to become in effect a large script.
It gives the advantages of Swift with the malleability of a script.

Usage is pretty much as for [injectionforxcode](https://github.com/johnno1962/injectionforxcode).
Any program in the simulator can be injected on-demand by using lldb to
load a bootstrap bundle into your program that loads the code change bundles.
To inject on a device or inject storyboards you will need to "patch" your
project's main.m to include this code and connect back to Xcode using Bonjour.
For Pure Swift projects, add a dummy main.m to make this possible.

More details to follow. A beta eval license is installed by default
when it first starts but if you use the menu of the menu bar application
to "Enter License" "INJECTOR_INDIE" for now you'll be licensed for 999
years if there is only one person using Injector on your network. Get it 
while it's free!

For use with AppCode copy the following file from

    ~/Library/Diamond/Projects/Injector/InjectorAppCode/Injector.jar

to 

    ~/Library/Application\ Support/AppCode33/Injector.jar

Injection in the AppCode version requires that you have built the project
at some time in the past inside Xcode as it parses the build logs for
compile commands.

Both plugins support a File Watcher which if enabled will watch for
changes to any source in a project on disk while the app is running.
If this doesn't suit you there is a command line interface to prompt
an injection:

    ~/Library/Application\ Support/Developer/Shared/Xcode/Plug-ins/InjectorPlugin.xcplugin/Contents/Resources/injectorUtil

This binary expects one of _patchProject_, _unpatchProject_ or _injectSources_
then the path to the project or workspace of the app being injected
then full path to the file(s) you want to inject.

Injector is OpenSource but will likely not be "Free Software". The
eventual pricing will what it always was for injectionforxcode i.e.
$10 for an indie license and $25 for an "enterprise" license per
host when there is more than one Injector user on your network.

## License

Copyright (c) 2015 John Holdsworth

Permission is hereby granted, to any person obtaining a copy of this software and associated documentation files (the "Software"), to use the software for iOS development and use it for evaluation for a period of two weeks. It can only be re-distributed in source form through github and subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software and may not be distributed without the DRM software contained in this distribution.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
