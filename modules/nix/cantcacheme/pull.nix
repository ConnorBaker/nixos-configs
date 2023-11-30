{
  nix.settings =
    let
      substituters = ["https://cantcache.me"];
    in
    {
      extra-substituters = substituters;
      extra-trusted-substituters = substituters;
      extra-trusted-public-keys = ["cantcache.me:Y+FHAKfx7S0pBkBMKpNMQtGKpILAfhmqUSnr5oNwNMs="];
    };
}
