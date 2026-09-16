{
  description = "StarIntel Auto Research static publication";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          emacs = pkgs.emacs.pkgs.withPackages (epkgs: [
            epkgs.htmlize
            epkgs.org-roam
          ]);
          site = pkgs.stdenvNoCC.mkDerivation {
            pname = "starintel-auto-research-site";
            version = "0.1.0";
            src = nixpkgs.lib.cleanSourceWith {
              src = self;
              filter =
                path: type:
                let
                  name = baseNameOf path;
                in
                !builtins.elem name [
                  ".cache"
                  ".git"
                  ".prolog"
                  "_site"
                ];
            };
            nativeBuildInputs = [
              emacs
              pkgs.gitMinimal
              pkgs.graphviz
              pkgs.plantuml
              pkgs.python3
              pkgs.sqlite
            ];
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              bash scripts/publish-pages
              python3 scripts/check-pages-links.py _site
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp -r _site/. "$out/"
              runHook postInstall
            '';
          };
        in
        {
          default = site;
          inherit site;
        }
      );

      checks = forAllSystems (system: {
        site = self.packages.${system}.site;
      });
    };
}
