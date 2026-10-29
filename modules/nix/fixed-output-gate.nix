# Nix gives the network to fixed-output and impure derivations only. From a
# farm host that network reaches every nix-grpc-daemon, which trusts any
# caller, and the Tribuchet hub, so no host builds them itself: they build
# in Tribuchet's FOD sandbox. That keeps them to public destinations only
# with a Tribuchet whose fod-network policy refuses loopback, the worker's
# own addresses and non-public destinations unless a rule allows them; an
# older one reaches the LAN, the tailnet, cloud metadata and the worker's
# own loopback.
#
# nix-daemon runs its pre-build hook before every sandboxed build it runs
# itself, and never for a build it hands to an external builder, so on the
# hub fixed-output derivations still reach Tribuchet. The hook runs only in
# the sandbox, hence sandbox = true with no fallback to an unsandboxed
# build. A client the daemon does not trust cannot change either; a trusted
# one (root, @wheel, and the users nix-grpc-daemon and Tribuchet run as)
# can, for its own builds.
#
# flake.nix's mkSystem imports this for every host. Anyone who can change
# this repository is root on these hosts, so its assertion catches mistakes
# here before a deploy; it is no boundary against a setting hidden on
# purpose. Where the daemon's configuration can come from:
# - /etc, by where each entry lands: nothing at xdg/nix, which the daemon
#   reads after nix.conf; under systemd/, of the system manager's files
#   only those NixOS writes today.
# - nix.conf, read as Nix reads it (util.nix's nixConf): the hook, the
#   sandbox, max-jobs, builders and no include but the hub's Tribuchet
#   fragment.
# - The machines file: no machine but the hub without mandatory features.
# - nix-daemon's unit: exactly what systemd.services.nix-daemon renders,
#   whose serviceConfig, commands included, is the hosts' of today, and no
#   unit whose drop-ins systemd also applies to it (a name with a "/", or
#   nix-.service).
# - Its environment, systemd.globalEnvironment and
#   systemd.generatorEnvironment: none of the variables that change the
#   configuration Nix reads; no DefaultEnvironment and no systemd.setenv=
#   kernel parameter.
# - Tribuchet workers' fod-network: deny rules only.
# It does not see units and drop-ins shipped by packages
# (systemd.packages, Nix's own nix-daemon.service included), nix.package
# wrappers, files written at run time, or the contents of root's
# ~/.config/nix/nix.conf, wherever root's home is.
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  inventory = import ../../inventory.nix;
  inherit ((import ../../util.nix { inherit lib; }).nixConf) settings includes machines;

  mounts = config.programs.nix-required-mounts;
  hook =
    if mounts.enable then
      pkgs.refuse-local-fixed-output.override { next = lib.getExe mounts.package; }
    else
      pkgs.refuse-local-fixed-output;

  # /etc entries by where they land, not by their attribute names.
  etc = map (entry: entry // { at = lib.splitString "/" (lib.removePrefix "/" entry.target); }) (
    lib.filter (entry: entry.enable) (lib.attrValues config.environment.etc)
  );
  landing = entry: lib.concatStringsSep "/" entry.at;
  under = dir: entry: builtins.head entry.at == dir;
  # What the hosts have today, which the checks below allow.
  systemManagerFiles = [
    "systemd/system"
    "systemd/system-environment-generators/env-generator"
    "systemd/system-generators"
    "systemd/system-preset/00-nixos.preset"
    "systemd/system-shutdown"
    "systemd/system.conf"
  ];
  serviceConfigKeys = [
    "CPUSchedulingPolicy"
    "IOSchedulingClass"
    "IOSchedulingPriority"
  ];
  # The variables that change the configuration Nix reads: libstore's
  # globals.cc (Settings, loadConfFile, nixConfDir, nixUserConfFiles),
  # libutil's users.cc (getConfigDir), unix/users.cc (getHome) and
  # unix/xdg-dirs.cc.
  configVariables = [
    "HOME"
    "NIX_CONFIG"
    "NIX_CONFIG_HOME"
    "NIX_CONF_DIR"
    "NIX_REMOTE_SYSTEMS"
    "NIX_USER_CONF_FILES"
    "XDG_CONFIG_DIRS"
    "XDG_CONFIG_HOME"
  ];
  text =
    name:
    lib.concatMapStrings (entry: entry.source.text) (lib.filter (entry: landing entry == name) etc);
  conf = settings (text "nix/nix.conf");
  # A setting's value, or Nix's default when nothing sets it.
  value = name: default: conf.${name} or default;

  isHub = config.networking.hostName == inventory.hub;
  # The hub's machine entry names it by its host name, alone or on the
  # tailnet.
  isHubHost =
    host:
    builtins.elem host [
      inventory.hub
      "${inventory.hub}.${inventory.tailnet}"
    ];
  # The one include allowed: the hub's own fragment, Tribuchet's
  # external-builders and max-jobs, which is runtime state.
  fragment = [
    "!include"
    (toString config.services.tribuchet-hub.externalBuilders.nixConfigPath)
  ];

  daemon = config.systemd.services.nix-daemon;
  extend =
    list:
    "add it to ${list} in modules/nix/fixed-output-gate.nix if it does not change what nix-daemon reads or runs.";

  worker = config.services.tribuchet-worker or { };
  # A deny rule only narrows what a fixed-output build reaches.
  widening = lib.optionals (worker.enable or false) (
    lib.filter (rule: rule.action or null != "deny") (worker.settings.fod-network.rules or [ ])
  );

  problems =
    # /etc
    map (entry: "/etc/${landing entry} is where nix-daemon reads its configuration after nix.conf.") (
      lib.filter (
        entry: under "xdg" entry && (builtins.length entry.at == 1 || builtins.elemAt entry.at 1 == "nix")
      ) etc
    )
    ++
      map
        (
          entry:
          "/etc/${landing entry} configures the system manager or its units: ${extend "systemManagerFiles"}"
        )
        (
          lib.filter (
            entry:
            under "systemd" entry
            && builtins.length entry.at > 1
            && builtins.match "system([.-].*)?" (builtins.elemAt entry.at 1) != null
            && !builtins.elem (landing entry) systemManagerFiles
          ) etc
        )
    ++ map (name: "Several /etc entries land on /etc/${name}.") (
      lib.filter (name: builtins.length (lib.filter (entry: landing entry == name) etc) > 1) (
        [
          "nix/machines"
          "nix/nix.conf"
        ]
        ++ systemManagerFiles
      )
    )
    # nix.conf and machines
    ++ map (include: "nix.conf has \"${toString include}\", which this check cannot read.") (
      lib.filter (include: !(isHub && include == fragment)) (includes (text "nix/nix.conf"))
    )
    ++ lib.optional (
      !lib.hasSuffix "/bin/refuse-local-fixed-output" (value "pre-build-hook" "")
    ) "pre-build-hook is \"${value "pre-build-hook" ""}\", not refuse-local-fixed-output."
    ++ lib.optional (
      value "sandbox" "true" != "true"
    ) "sandbox is ${value "sandbox" "true"}: the hook runs only in the sandbox."
    ++
      lib.optional (value "sandbox-fallback" "true" != "false")
        "sandbox-fallback is ${value "sandbox-fallback" "true"}: Nix may build without the sandbox, so without the hook."
    ++
      lib.optional (!isHub && value "max-jobs" "1" != "0")
        "max-jobs is ${value "max-jobs" "1"}: off the hub, a local slot takes the fixed-output derivations nixpkgs' fetchers prefer to build locally, and the hook refuses them instead of the hub building them."
    ++ lib.optional (
      !builtins.elem (value "builders" "@/etc/nix/machines") [
        "@/etc/nix/machines"
        ""
      ]
    ) "builders is \"${value "builders" ""}\": only /etc/nix/machines, whose entries are read here."
    ++
      map
        (
          machine:
          "${machine.uri} has no mandatory features, so it takes fixed-output derivations; only the hub may."
        )
        (
          lib.filter (machine: !isHubHost machine.host && machine.mandatoryFeatures == [ ]) (
            machines (text "nix/machines")
          )
        )
    # nix-daemon's unit and environment
    ++ lib.optional (
      config.systemd.units."nix-daemon.service".text != (utils.systemdUtils.lib.serviceToUnit daemon).text
    ) "nix-daemon's unit is not what systemd.services.nix-daemon renders."
    # systemd also applies nix-.service.d and the top-level service.d
    # (src/shared/dropin.c), and a "/" puts a unit's file in a directory.
    ++ map (name: "systemd.units.\"${name}\" can be a drop-in systemd applies to nix-daemon too.") (
      lib.filter (name: lib.hasInfix "/" name || name == "nix-.service") (
        builtins.attrNames config.systemd.units
      )
    )
    # script, preStart and the other commands land in serviceConfig too.
    ++ map (name: "nix-daemon's serviceConfig sets ${name}: ${extend "serviceConfigKeys"}") (
      lib.subtractLists serviceConfigKeys (builtins.attrNames daemon.serviceConfig)
    )
    ++ lib.concatLists (
      lib.mapAttrsToList
        (
          source: environment:
          map (name: "${source} sets ${name}, which changes the configuration nix-daemon reads.") (
            lib.intersectLists configVariables (builtins.attrNames environment)
          )
        )
        {
          "nix-daemon's environment" = daemon.environment;
          "systemd.globalEnvironment" = config.systemd.globalEnvironment;
          "systemd.generatorEnvironment" = config.systemd.generatorEnvironment;
        }
    )
    ++ lib.optional (
      config.systemd.settings.Manager ? DefaultEnvironment
    ) "systemd.settings.Manager sets DefaultEnvironment, which every service gets."
    ++ map (
      parameter: "The kernel parameter ${parameter} sets an environment variable for every service."
    ) (lib.filter (lib.hasPrefix "systemd.setenv=") config.boot.kernelParams)
    # Tribuchet's FOD sandbox
    ++ map (
      rule:
      "services.tribuchet-worker.settings.fod-network has a rule that is not a deny rule, ${builtins.toJSON rule}: only a rule allowing them reopens non-public destinations to fixed-output builds."
    ) widening;
in
{
  nix.settings = {
    # Replaces nix-required-mounts' hook, which runs after the check.
    pre-build-hook = lib.mkForce (lib.getExe hook);
    sandbox = true;
    sandbox-fallback = false;
  };

  # Present on every host that imports this: nixos-assertions (flake.nix)
  # fails a host without it.
  system.build.fixedOutputGateProblems = problems;

  assertions = [
    {
      assertion = problems == [ ];
      message = ''
        This host's nix-daemon could build fixed-output derivations in its own
        network (modules/nix/fixed-output-gate.nix):
        ${lib.concatMapStringsSep "\n" (problem: "- ${problem}") problems}
      '';
    }
  ];
}
