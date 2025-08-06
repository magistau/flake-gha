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
    aarch64-linux = "ubuntu-24.04-arm";
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
  globalCfg = config.githubActions;
in
{
  options = {
    perSystem = flake-parts-lib.mkPerSystemOption (
      {
        self',
        system,
        pkgs,
        config,
        ...
      }:
      let
        cfg = config.githubActions;
      in
      {
        options.githubActions = {
          checks = lib.mkOption {
            type = types.lazyAttrsOf types.package;
            default = flattenAttrs (fst: snd: "${fst}-${snd}") (
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
            package = lib.mkPackageOption pkgs "cachix" { };
            paths = lib.mkOption {
              type = types.listOf types.package;
            };
            start = lib.mkOption {
              type = types.package;
              readOnly = true;
              visible = false;
              default = pkgs.writeShellApplication {
                name = "gha-cachix-start";
                runtimeInputs = [ cfg.cachix.package ];
                text = ''
                  for cache in ${lib.escapeShellArgs globalCfg.cachix.pull-caches}; do
                    cachix -v use "$cache"
                  done
                '';
              };
            };
            end = lib.mkOption {
              type = types.package;
              readOnly = true;
              visible = false;
              default = pkgs.writeShellApplication {
                name = "gha-cachix-end";
                runtimeInputs = [ cfg.cachix.package ];
                text = lib.optionalString (globalCfg.cachix.push-cache != null) ''
                  cachix -v push ${lib.escapeShellArg globalCfg.cachix.cache} \
                    ${lib.escapeShellArgs cfg.cachix.paths}
                '';
              };
            };
          };
          run = lib.mkOption {
            type = types.package;
            readOnly = true;
            visible = false;
            default = pkgs.writeShellApplication {
              name = "gha-run";
              runtimeInputs = with cfg.cachix; [
                start
                end
              ];
              text = ''
                gha-cachix-start
                nix-build --no-out-link --keep-going --expr '{ system }: (builtins.getFlake (toString ./.)).githubActions.target.${system}.checks' --argstr system ${lib.escapeShellArg system}
                gha-cachix-end
              '';
            };
          };
        };
      }
    );
    githubActions = {
      cachix = {
        push-cache = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        pull-caches = lib.mkOption {
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
      in
      {
        target = lib.mapAttrs (_: x: {
          inherit (x) run;
          checks = lib.recurseIntoAttrs x.checks;
        }) ghaSystems;
        config = {
          inherit (globalCfg) checkAllSystems;
          matrix = lib.mapAttrsToList (
            double:
            { platform, ... }:
            {
              inherit double platform;
            }
          ) ghaSystems;
        };
      };
  };
}
