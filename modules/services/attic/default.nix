{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.modules) mkForce;
  # Named after their paths in secrets.yaml.
  # NOTE: The directory is atticd, not attic
  atticCredentials = "atticd/credentials.env";
in
{
  environment.systemPackages = [ pkgs.attic ];

  # TODO: "/var/lib/postgresql"
  # TODO: "/var/lib/atticd"
  # TODO: ZFS should have a separate dataset for the database
  #
  # Steps:
  # 1. Create token with:
  # sudo atticd-atticadm make-token --sub attic-cuda-tester --validity 1y --pull attic-cuda-test-cache --push attic-cuda-test-cache --delete attic-cuda-test-cache --create-cache attic-cuda-test-cache --configure-cache attic-cuda-test-cache --configure-cache-retention attic-cuda-test-cache --destroy-cache attic-cuda-test-cache
  # 2. Log in to the server:
  # attic login attic-cuda-test-server https://cantcache.me <token from previous step>
  # 3. Create the cache:
  # attic cache create attic-cuda-test-server:attic-cuda-test-cache
  # 4. Push to the cache:
  # attic push attic-cuda-test-server:attic-cuda-test-cache ./result
  # 5. Set up to use the cache:
  # attic use attic-cuda-test-server:attic-cuda-test-cache
  systemd.services = {
    atticd = {
      serviceConfig = {
        # We want our user to be persistent.
        DynamicUser = pkgs.lib.mkForce false;
        # Log everything
        Environment = [
          "RUST_LOG=debug"
          "RUST_BACKTRACE=1"
        ];
      };
      unitConfig = {
        RequiresMountsFor = "/var/lib/atticd/storage";
      };
    };
    # NOTE: We cannot use services.postgresql.initialScript because it runs before the users or tables are created!
    postgresql.postStart = lib.mkAfter (
      # Give the ability for atticd to create tables in the public schema
      ''
        $PSQL -tAc 'GRANT ALL ON SCHEMA public TO "atticd"'
      ''
      # Make atticd the owner of the database
      + ''
        $PSQL -tAc 'ALTER DATABASE "attic" OWNER TO "atticd"'
      ''
    );
  };

  # NOTE: File should have:
  # - ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64
  sops.secrets.${atticCredentials} = {
    owner = "atticd";
    mode = "0440";
    path = "/var/lib/private/${atticCredentials}";
    sopsFile = ./secrets.yaml;
  };

  services = {
    atticd = {
      enable = true;

      credentialsFile = config.sops.secrets.${atticCredentials}.path;

      settings = {
        listen = "[::]:5000";

        # Allowed `Host` headers
        #
        # This _must_ be configured for production use. If unconfigured or the
        # list is empty, all `Host` headers are allowed.
        allowed-hosts = [ "cantcache.me" ];

        database.url = "postgresql://atticd@localhost:5432/attic";
        # database.url = "postgresql:///attic?host=/run/postgresql";

        # TODO: This is where attic is expected to be hosted/available; for now, that's on localhost
        # The canonical API endpoint of this server
        #
        # This is the endpoint exposed to clients in `cache-config` responses.
        #
        # This _must_ be configured for production use. If not configured, the
        # API endpoint is synthesized from the client's `Host` header which may
        # be insecure.
        #
        # The API endpoint _must_ end with a slash (e.g., `https://domain.tld/attic/`
        # not `https://domain.tld/attic`).
        api-endpoint = "https://cantcache.me/";

        # Data chunking
        #
        # Warning: If you change any of the values here, it will be
        # difficult to reuse existing chunks for newly-uploaded NARs
        # since the cutpoints will be different. As a result, the
        # deduplication ratio will suffer for a while after the change.
        chunking = {
          # The minimum NAR size to trigger chunking
          #
          # If 0, chunking is disabled entirely for newly-uploaded NARs.
          # If 1, all NARs are chunked.
          nar-size-threshold = 64 * 1024; # 64 KiB

          # The preferred minimum size of a chunk, in bytes
          min-size = 32 * 1024; # 32 KiB

          # The preferred average size of a chunk, in bytes
          avg-size = 128 * 1024; # 128 KiB

          # The preferred maximum size of a chunk, in bytes
          max-size = 512 * 1024; # 512 KiB
        };

        # TODO: Copying from R2 is *excruciatingly* slow and the API costs are high given the small chunk size.
        compression = {
          type = "zstd";
          level = 19;
        };

        storage = {
          type = "local";
          path = "/var/lib/atticd/storage";
        };
      };
    };
    postgresql = {
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
  };

  # TODO: The module should handle this for us.
  users.groups.atticd = { };
  users.users.atticd = {
    description = "atticd user";
    group = "atticd";
    home = "/var/lib/atticd";
    isSystemUser = true;
  };
}
