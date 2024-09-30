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
        templates = {
          cachix = {
            path = ./templates/cachix;
            description = "A simple flake using GitHub Actions to build packages and upload them to Cachix";
            welcomeText = ''
              # Simple GitHub Actions + Cachix template
              ## Intended usage
              - TODO
            '';
          };
        };
      };
    };
}
