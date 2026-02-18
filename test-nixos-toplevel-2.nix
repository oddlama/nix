# Minimal NixOS evaluation with dependency tracking for system.build.toplevel
#
# This is a thin test harness that uses the integrated dependency tracking
# from eval-config.nix. All processing logic lives in nixpkgs/nixos/lib/dependency-tracking.nix.
#
# Usage:
#   nix build -f test-nixos-toplevel.nix toplevel    # includes tracking.json
#   nix eval -f test-nixos-toplevel.nix filteredDotOutput --raw > deps.dot
#   nix eval -f test-nixos-toplevel.nix configValues --json > config.json
#   nix eval -f test-nixos-toplevel.nix counts
let
  nixpkgs = import ./nixpkgs { };
  lib = nixpkgs.lib;

  nixos = import ./nixpkgs/nixos/lib/eval-config.nix {
    inherit lib;
    trackDependencies = true;
    modules = [
      (
        { modulesPath, ... }:
        {
          imports = [
            (modulesPath + "/profiles/minimal.nix")
          ];

          services.vaultwarden.enable = true;
          boot.loader.grub.device = "nodev";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "24.05";
        }
      )
    ];
  };

in
{
  # config.system.build.toplevel automatically includes tracking.json
  # when trackDependencies = true. No manual builtins.seq needed.
  toplevel = nixos.config.system.build.toplevel;

  inherit (nixos.dependencyTracking)
    rawDeps
    filteredDeps
    configValues
    explicitConfigValues
    leafNodes
    explicitLeafNodes
    keptNodes
    rawDotOutput
    filteredDotOutput
    counts
    ;
}
