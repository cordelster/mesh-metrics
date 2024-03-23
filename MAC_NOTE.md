If you try to run a script from the Terminal in macOS, you may get an error that says zsh: operation not permitted.

As of this writing, the top Google search results for that all point to needing to grant the Terminal full disk access (either via System Preferences > Security & Privacy > Privacy > Full Disk Access or via MDM-delivered PPPC profile. https://support.apple.com/guide/mdm/privacy-preferences-policy-control-payload-mdm38df53c2a/web

If that works for you, great!

But it could also be that there is an Apple quarantine extended attribute on your script. Now, of course, don’t take that extended attribute off if you don’t trust the script. If you do trust it, though, you can remove that extended attribute.

To see the extended attributes, run

xattr -l /PATH/TO/SCRIPTYOUCANTRUN.sh

If you see com.apple.quarantine in there, you can remove it by running

xattr -d com.apple.quarantine /PATH/TO/SCRIPTYOUCANTRUN.sh

The only other thing you may want to check is that your script is executable:

ls -l /PATH/TO/SCRIPTYOUCANTRUN.sh

There should be some x‘s in there (read man chmod for more details).

If it’s not, you can add the executable flag to it:

chmod +x /PATH/TO/SCRIPTYOUCANTRUN.sh

