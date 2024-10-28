# MobaXterm Integration with Britive

MobaXterm does not support a "pre-connect" script execution in the local environment when connecting to a session.

To date the best integration is creating a Macro which perform a checkout and then launches the session.


An example of a Macro is below. Since `MobaXterm.exe` is only available in PowerShell/CMD we have to execute the below
macro in a MobaXterm PowerShell window (or any PowerShell window). It seems some of the `.exe` files related to MobaXterm
are available in `bash` or `zsh` it appears this specific one is not.

~~~shell
pybritive checkout demo_box -s | Out-File -FilePath "c:\Users\Administrator\Downloads\demo_box.pem" -Encoding ASCII
RETURN
& "C:\Program Files (x86)\Mobatek\MobaXterm\MobaXterm.exe" -bookmark "demo_box"
RETURN
~~~

In the example above, `demo_box` is both the `pybritive` profile alias of a profile as well as the name of the MobaXterm bookmark/session.
Each of these can be adjusted as needed.

