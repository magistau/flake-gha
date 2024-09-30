{
  description = "A simple flake using GitHub Actions and Cachix";
  inputs = {
    flake-parts = {
      type = "github";
      owner = "hercules-ci";
      repo = "flake-parts";
    };
    flake-gha = {
      type = "github";
      owner = "thecaralice";
      repo = "flake-gha";
      inputs.flake-parts.follows = "flake-parts";
    };
  };
  outputs =
    {
      self,
      flake-parts,
      flake-gha,
      nixpkgs,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.platforms.all;
      imports = [
        flake-gha.flakeModules.default
      ];
      perSystem =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        {
          packages.default = pkgs.callPackage ./packages/hello { };
          checks.nixfmt =
            pkgs.runCommand "nixfmt-check"
              {
                nativeBuildInputs = [ pkgs.nixfmt-rfc-style ];
              }
              ''
                nixfmt --check ${self}
                touch "$out"
              '';
          checks.shellcheck = pkgs.runCommand "shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
            shellcheck ${lib.escapeShellArg (lib.getExe config.packages.default)}
            touch "$out"
          '';
        };
    };
}
