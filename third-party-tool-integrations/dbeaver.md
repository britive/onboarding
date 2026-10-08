# DBeaver Integration with Britive

DBeaver offers pre-connect script execution in the local environment, so we can perform a `pybritive` CLI checkout
before attempting to connect to a database. The below shell script is an example of what could be called in this pre-connect
script.

It is recommended that the pre-connect script simply call a shell script vs. trying to code all of the logic into the pre-connect
script window.

~~~bash
/path/to/pybritive checkout "$1" -t your-tenant -s | sed -n '2p' | tr -d '\n' | pbcopy
~~~

Note that `pybritive` is most likely NOT in the `PATH` for this shell script so you will need to specify the full path to it.
The same goes for any non-shell commands.

`$1` in this case is the name of the connection. It is used to map to `pybritive` profile alias so the script can be made more generic.

The contents of the pre-connect script are below.

~~~bash
/path/to/dbeaver.sh "${datasource}"
~~~

`${datasource}` is a DBeaver variable and represents the name of the connection.

To set this edit an existing connection and navigate to `Connection Settings > Shell Commands > Before Connect`. 