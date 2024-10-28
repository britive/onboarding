# DBeaver Integration with Britive

DBeaver offers pre-connect script execution in the local environment, so we can perform a `pybritive` CLI checkout
before attempting to connect to a database. The below shell script is an example of what could be called in this pre-connect
script.

It is recommended that the pre-connect script simply call a shell script vs. trying to code all of the logic into the pre-connect
script window.

~~~bash
/Users/thomas/.pyenv/shims/pybritive checkout "$1" -t demo -s | sed -n '2p' | tr -d '\n' | pbcopy
~~~

Note that `pybritive` is most likely NOT in the `PATH` for this shell script so you will need to specify the full path to it.
The same goes for any non-shell commands.

`$1` in this case is the name of the connection. It is used to map to `pybritive` profile alias so the script can be made more generic.

Future versions of this script would seek to dynamically update the credentials file that DBeaver uses behind the scenes. Examples
of that are below (note these are not yet working but adding for reference).

~~~bash
# connectionid=$(/opt/homebrew/bin/jq --arg datasource "$1" -r '.connections | to_entries[] | select(.value.name == $datasource) | .key' $HOME/Library/DBeaverData/workspace6/General/.dbeaver/data-sources.json)

# /opt/homebrew/bin/openssl aes-128-cbc -d -K babb4a9f774ab853c96c2d653dfe544a -iv 00000000000000000000000000000000 -in $HOME/Library/DBeaverData/workspace6/General/.dbeaver/credentials-config.json
~~~

There appears to be a shared key `babb4a9f774ab853c96c2d653dfe544a` that was found via searching Google. No clue if that is always going to be the case.

The contents of the pre-connect script are below.

~~~bash
/Users/thomas/dbeaver.sh "${datasource}"
~~~

`${datasource}` is a DBeaver variable and represents the name of the connection.

To set this edit an existing connection and navigate to `Connection Settings > Shell Commands > Before Connect`. 