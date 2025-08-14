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
  flake-out-attr = pipe' [
    (map (
      lib.escape [
        ''\''
        ''"''
      ]
    ))
    (map (x: ''."${x}"''))
    lib.concatStrings
  ];
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
                  nix build -L --keep-going .#${
                    lib.escapeShellArg (flake-out-attr [
                      "githubActions"
                      "target"
                      system
                      "pushTarget"
                    ])
                  }
                  find ./result/ -print -exec cachix -v push ${lib.escapeShellArg globalCfg.cachix.cache} {} +
                '';
              };
            };
            pushTarget = lib.mkOption {
              type = types.package;
              readOnly = true;
              visible = false;
              default = lib.pipe cfg.cachix.paths [
                (lib.imap0 lib.nameValuePair)
                (lib.mapAttrs (_: toString))
                builtins.listToAttrs
              ];
            };
          };
          buildTarget = lib.mkOption {
            type = types.package;
            readOnly = true;
            visible = false;
            default = pkgs.linkFarm "gha-build" cfg.checks;
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
                nix build -L --keep-going --no-out-link .#${
                  lib.escapeShellArg (flake-out-attr [
                    "githubActions"
                    "target"
                    system
                    "buildTarget"
                  ])
                }
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
          inherit (x) run buildTarget;
          inherit (x.cachix) pushTarget;
        }) ghaSystems;
        config = {
          inherit (globalCfg) checkAllSystems;
          matrix = lib.mapAttrsToList (
            double:
            { platform, ... }:
            {
              inherit platform;
              run = flake-out-attr [
                "githubActions"
                "target"
                double
                "run"
              ];
            }
          ) ghaSystems;
        };
      };
  };
}
