package com.injectionforxcode;

import com.intellij.openapi.actionSystem.AnAction;
import com.intellij.openapi.actionSystem.AnActionEvent;
import com.intellij.openapi.actionSystem.PlatformDataKeys;
import com.intellij.openapi.fileEditor.FileDocumentManager;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.vfs.VirtualFile;
import com.intellij.openapi.ui.Messages;
import com.intellij.util.ui.UIUtil;

import java.util.regex.Pattern;

import java.io.InputStreamReader;
import java.io.BufferedReader;
import java.io.IOException;

/**
 * Copyright (c) 2013 John Holdsworth. All rights reserved.
 *
 * Created with IntelliJ IDEA.
 * Date: 24/02/2013
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * If you want to "support the cause", consider a paypal donation to:
 *
 * injectionforxcode@johnholdsworth.com
 *
 */

public class InjectionAction extends AnAction {

    static InjectionAction plugin;

    {
        plugin = this;
    }

    public void actionPerformed(AnActionEvent event) {
        runScript("injectSources", event);
    }

    static public class PatchAction extends AnAction {
        public void actionPerformed(AnActionEvent event) {
            plugin.runScript("patchProject", event);
        }
    }

    static public class UnpatchAction  extends AnAction {
        public void actionPerformed(AnActionEvent event) {
            plugin.runScript("unpatchProject", event);
        }
    }

    static int alert( final String msg ) {
        UIUtil.invokeAndWaitIfNeeded(new Runnable() {
            public void run() {
                Messages.showMessageDialog(msg, "Injector Plugin", Messages.getInformationIcon());
            }
        } );
        return 0;
    }

    static void error( String where, Throwable e ) {
        alert(where + ": " + e + " " + e.getMessage());
        throw new RuntimeException( "Injector Plugin error", e );
    }

    static String resourcesPath = System.getProperty( "user.home" )+"/Library/Application Support/Developer/Shared/Xcode/Plug-ins/InjectorPlugin.xcplugin/Contents/Resources";

    int runScript( String script, AnActionEvent event ) {
        try {
            Project project = event.getData(PlatformDataKeys.PROJECT);
            VirtualFile vf = event.getData(PlatformDataKeys.VIRTUAL_FILE);
            if ( vf == null )
                return 0;

            String selectedFile = vf.getCanonicalPath();

            if ( selectedFile == null || !Pattern.matches( ".+\\.(m|mm|swift)$", selectedFile ) )
                return alert( "Select text in an implementation file to inject..." );

            FileDocumentManager.getInstance().saveAllDocuments();

            processScriptOutput(script, new String[]{resourcesPath+"/injectorUtil", script, project.getProjectFilePath(), selectedFile}, event);
        }
        catch ( Throwable e ) {
            error( "Run script error", e );
        }

        return 0;
    }

    void processScriptOutput(final String script, String command[], final AnActionEvent event) throws IOException {

        final Process process = Runtime.getRuntime().exec( command, null, null);
        final BufferedReader stdout = new BufferedReader( new InputStreamReader( process.getInputStream(), "UTF-8" ) );

        new Thread( new Runnable() {
            public void run() {
                try {
                    String line;
                    while ( (line = stdout.readLine()) != null )
                        alert( line );
                }
                catch ( IOException e ) {
                    error( "Script i/o error", e );
                }

                try {
                    stdout.close();
                    if ( process.waitFor() != 0 )
                       alert(script + " returned failure.");
                }
                catch ( Throwable e ) {
                    error( "Wait problem", e );
                }
            }
        } ).start();
    }

}
