# WordPress connector

The optional WordPress connector is installed in WordPress and sends signed
publish/update events to CourierCMS. It does not contain a source Adapter and
does not send post bodies. The CourierCMS-hosted WordPress extension re-reads
the authoritative post through the REST API.

See the connector's [installation and behavior guide](../../connectors/wordpress/README.md).
Build its installable ZIP with `scripts/package-wordpress-connector.ps1` or
`scripts/package-wordpress-connector.sh`; generated packages are written under
`.local/packages/` and are not committed.
