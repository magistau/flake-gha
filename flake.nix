{
  description = "flake-parts module for easier GitHub Actions setup";
  inputs = {
    flake-parts = {
      type = "github";
      owner = "hercules-ci";
      repo = "flake-parts";
    };
  };
  outputs =
    { flake-parts, ... }@inputs:
    let
      flakeModules = {
        default = import ./modules/default.nix;
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        flake-parts.flakeModules.flakeModules
        flakeModules.default
      ];
      flake = {
        inherit flakeModules;
        templates = rec {
          default = cachix;
          cachix = {
            path = ./templates/cachix;
            description = "A simple flake using GitHub Actions to build packages and upload them to Cachix";
            welcomeText = ''
              # Simple GitHub Actions + Cachix template
              This flake includes everything necessary to build packages, checks, devShells and NixOS/nix-darwin/home-manager configurations and push them to Cachix from GitHub Actions.

              ## Intended usage
              - If your flake does not pass `nix flake check` on some of the systems specified in `systems` you need to set `githubActions.checkAllSystems` to false.
              - These derivations are built by default:
                - `packages.<system>.<name>`
                - `checks.<system>.<name>`
                - `devShells.<system>.<name>`
                - `nixosConfigurations.<name>`
                - `darwinConfigurations.<name>`
                - `homeConfigurations.<name>`

                This can be overriden by changing `perSystem.githubActions.checks` attribute.
              - By default, only `aarch64-darwin`, `x86_64-darwin`, `aarch64-linux` and `x86_64-linux` are available (using `macos-15`, `macos-13`, `ubuntu-24.04-arm` and `ubuntu-24.04` GitHub runners respectively), but you can override this by setting `perSystem.githubActions.platform` to the desired `runs-on` setting.

              ### Cachix
              #### Pull
              List the caches you want to pull from in `githubActions.cachix.pull-caches`

              #### Push
              - Add a repository secret named `CACHIX_AUTH_TOKEN` in https://github.com/_<owner>_/_<repo>_/settings/secrets/actions and set it to the Cachix auth token from https://app.cachix.org/cache/_<name>_/settings/authtokens.
              - Set `githubActions.cachix.push-cache` to the name of your cache.
              - List the paths you want to push in `perSystem.githubActions.cachix.paths`
            '';
          };
        };
      };
    };
}
