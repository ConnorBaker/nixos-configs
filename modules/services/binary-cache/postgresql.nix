{ lib, pkgs, ... }:
let
  inherit (lib.modules) mkForce;
  atticDbName = "attic";
  atticDbUser = "atticd";
in
{
  services.postgresql = {
    enable = true;
    package =
      let
        package = pkgs.postgresql_16_jit;
        defaultPackage = pkgs.postgresql;
        pinnedIsAtLeastAsRecentAsDefault = lib.versionAtLeast package.version defaultPackage.version;
      in
      assert lib.asserts.assertMsg pinnedIsAtLeastAsRecentAsDefault ''
        "The default version of postgresql (${defaultPackage.version}) is now newer than the pinned version
        (${package.version}). Please update to use the default version.
      '';
      package;

    # Only available on localhost
    enableTCPIP = false;
    enableJIT = true;

    ensureDatabases = [ atticDbName ];
    ensureUsers = [ { name = atticDbUser; } ];

    # TODO: We should be able to cut this down to the minimum necessary
    authentication = ''
      # Allow the attic user to access the database
      #
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   ${atticDbName}  ${atticDbUser}                          trust
      host    ${atticDbName}  ${atticDbUser}  127.0.0.1/32            trust
      host    ${atticDbName}  ${atticDbUser}  ::1/128                 trust
      host    ${atticDbName}  ${atticDbUser}  localhost               trust
    '';

    settings = {
      # Connectivity
      port = 5432;

      # Performance
      max_wal_senders = 0;
      shared_buffers = "4GB";
      synchronous_commit = "off";
      wal_compression = "off";  # Let ZFS handle compression
      wal_level = "minimal";
      work_mem = "32MB";

      # Not helpful on CoW filesystems
      wal_init_zero = "off";
      wal_recycle = "off";

      # Not helpful on ZFS
      full_page_writes = "off";

      # logging
      log_connections = true;
      log_destination = mkForce "syslog";
      log_disconnections = true;
      log_statement = "all";
      logging_collector = true;
    };
  };

  # TODO: "/var/lib/postgresql" -- ZFS should be configured for the database
  # NOTE: We cannot use services.postgresql.initialScript because it runs before the users or tables are created!
  systemd.services.postgresql.postStart = lib.mkAfter (
    # Give the ability for atticd to create tables in the public schema
    ''
      $PSQL -tAc 'GRANT ALL ON SCHEMA public TO "${atticDbUser}"'
    ''
    # Make atticd the owner of the database
    + ''
      $PSQL -tAc 'ALTER DATABASE "${atticDbName}" OWNER TO "${atticDbUser}"'
    ''
  );
}
