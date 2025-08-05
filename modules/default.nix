{
  self,
  lib,
  config,
  flake-parts-lib,
  ...
}:
let
  inherit (lib) types;
  pipe' = lib.flip lib.pipe;
  defaultPlatforms = {
    aarch64-darwin = "macos-15";
    x86_64-darwin = "macos-13";
    aarch64-multiplatform = "ubuntu-24.04-arm";
    x86_64-linux = "ubuntu-24.04";
  };
  flattenAttrs =
    key: lib.concatMapAttrs (outer: lib.mapAttrs' (inner: lib.nameValuePair (key outer inner)));
  configurationPaths = {
    nixos = [
      "config"
      "system"
      "build"
      "toplevel"
    ];
    darwin = [ "system" ];
    home = [ "activationPackage" ];
  };
  configurations = pkgPath: lib.mapAttrs (_: lib.getAttrFromPath pkgPath);
  perSystemConfigurations = pipe' [
    lib.attrsToList
    (lib.groupBy (x: x.value.pkgs.stdenv.buildPlatform.system))
    (lib.mapAttrs (_: lib.listToAttrs))
  ];
in
{
  options = {
    perSystem = flake-parts-lib.mkPerSystemOption (
      { self', system, ... }:
      {
        options.githubActions = {
          checks = lib.mkOption {
            type = types.lazyAttrsOf types.package;
            default =
              flattenAttrs (fst: snd: "${fst}-${snd}") (
                {
                  inherit (self') checks packages devShells;
                }
                // lib.mapAttrs (pipe' [
                  (x: self."${x}Configurations" or { })
                  perSystemConfigurations
                  (lib.attrByPath [ system ] { })
                  (lib.flip configurations)
                ]) configurationPaths
              );
          };
          platform = lib.mkOption {
            type = types.nullOr types.str;
            default = defaultPlatforms.${system} or null;
          };
          cachix = {
            enable = lib.mkEnableOption "cachix" // {
              default = true;
            };
            pathsToPush = lib.mkOption {
              type = types.nullOr (types.listOf types.package);
              default = null;
            };
          };
        };
      }
    );
    githubActions = {
      cachix = {
        enable = lib.mkEnableOption "cachix";
        cacheName = lib.mkOption {
          type = types.str;
        };
        pushFilter = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        extraCaches = lib.mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
      };
      checkAllSystems = lib.mkOption {
        type = types.bool;
        default = true;
        example = false;
      };
    };
  };
  config = {
    flake.githubActions =
      let
        ghaSystems = lib.pipe config.allSystems [
          (lib.mapAttrs (_: x: x.githubActions))
          (lib.filterAttrs (_: x: x.platform != null))
        ];
        globalCfg = config.githubActions;
      in
      {
        target = lib.mapAttrs (_: x: lib.recurseIntoAttrs x.checks) ghaSystems;
        config = {
          inherit (globalCfg) checkAllSystems;
          cacheName = lib.optionalString globalCfg.cachix.enable globalCfg.cachix.cacheName;
          pushFilter = lib.optionalString (globalCfg.cachix.pushFilter != null) globalCfg.cachix.pushFilter;
          extraPullNames = lib.concatStringsSep "," globalCfg.cachix.extraCaches;
          matrix = lib.mapAttrsToList (system: cfg: {
            double = system;
            os = cfg.platform;
            enableCachix = globalCfg.cachix.enable && cfg.cachix.enable;
            pathsToPush =
              if cfg.cachix.pathsToPush == null then "" else lib.concatStringsSep " " cfg.cachix.pathsToPush;
            skipPush = cfg.cachix.pathsToPush == [ ];
          }) ghaSystems;
        };
      };
  };
}
