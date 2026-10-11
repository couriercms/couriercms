CourierCMS Local for Windows
============================

1. Extract the complete ZIP to a folder you can keep.
2. Run start-couriercms.ps1 from PowerShell.
3. CourierCMS opens http://127.0.0.1:4000 in your browser.

For unattended startup, use start-couriercms.ps1 -NoBrowser.
If port 4000 is already used (for example by Server mode), set a different
loopback port first: $env:PORT = '4100'. Local and Server can run together when
their ports and data stores are separate.

CourierCMS stores its database, encryption material, extensions, logs, and
backups under %LOCALAPPDATA%\CourierCMS by default. Moving or replacing the
extracted application folder does not remove that data.

Use stop-couriercms.ps1 before shutting down or upgrading. Use
backup-couriercms.ps1 to stop CourierCMS and create a consistent ZIP containing
the database, installation secrets, release cookie, and installed extensions.

Do not share the database, installation-secrets.json, or release-cookie.txt.
They contain or protect sensitive content-system credentials. Local and Server
databases are not interchangeable.

If startup fails, review couriercms-error.log and couriercms.log under the Local
data directory. Do not expose Local on a public or LAN address; use Server mode
for remote access.
