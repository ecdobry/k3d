{
  description = "k3d - lightweight wrapper to run k3s (Rancher Lab's minimal Kubernetes distribution) in Docker";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    ,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        version =
          if self ? rev
          then "git-${builtins.substring 0 7 self.rev}"
          else "git-dirty";

        # Tag for ghcr.io/k3d-io/k3d-proxy and ghcr.io/k3d-io/k3d-tools.
        # Dev builds derive their default helper tag from the git SHA, which
        # isn't published — pin to the latest released k3d version instead.
        # Bump in lockstep with upstream releases.
        helperVersion = "5.7.0";

        k3d = pkgs.buildGoModule {
          pname = "k3d";
          inherit version;

          go = pkgs.go_1_26;

          src = ./.;

          # Project vendors its dependencies (-mod=vendor in the Makefile).
          vendorHash = null;

          subPackages = [ "." ];

          ldflags = [
            "-w"
            "-s"
            "-X github.com/k3d-io/k3d/v5/version.Version=${version}"
            "-X github.com/k3d-io/k3d/v5/version.HelperVersionOverride=${helperVersion}"
          ];

          env.CGO_ENABLED = 0;

          meta = {
            description = "Little helper to run Rancher Lab's k3s in Docker";
            homepage = "https://k3d.io";
            license = pkgs.lib.licenses.mit;
            mainProgram = "k3d";
          };
        };

        # Wrap a script as a flake app that runs from the project root.
        mkApp = name: script: {
          type = "app";
          program = toString (pkgs.writeShellScript "k3d-${name}" ''
            cd "''${FLAKE_ROOT:-$PWD}"
            ${script}
          '');
        };
      in
      {
        packages = {
          default = k3d;
          k3d = k3d;
        };

        apps = {
          default = {
            type = "app";
            program = "${k3d}/bin/k3d";
          };

          build = mkApp "build" ''
            exec ${pkgs.gnumake}/bin/make build "$@"
          '';

          test = mkApp "test" ''
            exec ${pkgs.go_1_26}/bin/go test -mod=vendor ./... "$@"
          '';

          lint = mkApp "lint" ''
            exec ${pkgs.golangci-lint}/bin/golangci-lint run "$@"
          '';

          fmt = mkApp "fmt" ''
            exec ${pkgs.gnumake}/bin/make fmt "$@"
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.go_1_26
            pkgs.gopls
            pkgs.gotools
            pkgs.golangci-lint
            pkgs.gnumake
            pkgs.kubectl
            pkgs.docker-client
            pkgs.jq
          ];

          shellHook = ''
            export GOFLAGS="-mod=vendor"
          '';
        };

        formatter = pkgs.writeShellScriptBin "gofmt" ''
          exec ${pkgs.go_1_26}/bin/gofmt -s "$@"
        '';
      }
    );
}
