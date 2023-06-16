{
  nix.settings = {
    extra-substituters = [
      "https://cantcache.me"
    ];
    extra-trusted-public-keys = [
      "cantcache.me:Y+FHAKfx7S0pBkBMKpNMQtGKpILAfhmqUSnr5oNwNMs="
    ];
    post-build-hook = ./../../secrets/cantcacheme-post-build-hook.sh;
    secret-key-files = [./../../secrets/cantcacheme-secret.key];
  };
}
