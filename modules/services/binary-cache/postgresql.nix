{ lib, pkgs, ... }:
let
  inherit (lib.modules) mkForce;
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16_jit;

    # Only available on localhost
    enableTCPIP = false;
    enableJIT = true;

    ensureDatabases = [ "attic" ];
    ensureUsers = [ { name = "atticd"; } ];

    # TODO: We should be able to cut this down to the minimum necessary
    authentication = ''
      # Allow the attic user to access the database
      #
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   attic           atticd                                  trust
      host    attic           atticd          127.0.0.1/32            trust
      host    attic           atticd          ::1/128                 trust
      host    attic           atticd          localhost               trust
    '';

    settings = {
      # Connectivity
      port = 5432;

      # Performance
      max_wal_senders = 0;
      shared_buffers = "4GB";
      synchronous_commit = "off";
      wal_compression = "zstd";
      wal_level = "minimal";
      work_mem = "32MB";

      # Not helpful on CoW filesystems
      wal_init_zero = "off";
      wal_recycle = "off";

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
      $PSQL -tAc 'GRANT ALL ON SCHEMA public TO "atticd"'
    ''
    # Make atticd the owner of the database
    + ''
      $PSQL -tAc 'ALTER DATABASE "attic" OWNER TO "atticd"'
    ''
  );
}
