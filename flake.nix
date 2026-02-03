{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kustomize-envsubst-src = {
      url = "github:logandavies181/kustomize-krm-envsubst/v0.10.0";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, kustomize-envsubst-src }: let
    forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      kustomize-krm-envsubst = pkgs.buildGoModule {
        pname = "kustomize-krm-envsubst";
        version = "0.10.0";
        src = kustomize-envsubst-src;
        vendorHash = "sha256-M3jjeOeOobKCQ7ylbBLMDMFW3feERYBx2qqMG3sMIxg=";
      };
      clusteradm = pkgs.buildGoModule {
        pname = "clusteradm";
        version = "1.1.1";
        src = pkgs.fetchFromGitHub {
          owner = "open-cluster-management-io";
          repo = "clusteradm";
          rev = "v1.1.1";
          sha256 = "sha256-9Qb05EPNl1FPZZs2HH9zXW96IWFcP+Ml5fQcIebHkQY=";
        };
        vendorHash = null;
        ldflags = [
          "-s"
          "-w"
          "-X open-cluster-management.io/clusteradm/pkg/version.gitVersion=v1.1.1"
        ];
        doCheck = false;
        meta = with pkgs.lib; {
          description = "Command-line tool to bootstrap Open Cluster Management control plane";
          homepage = "https://github.com/open-cluster-management-io/clusteradm";
          license = licenses.asl20;
          maintainers = [ ];
        };
      };
    });
    defaultPackage = forAllSystems (system: self.packages.${system}.kustomize-krm-envsubst);
  };
}
