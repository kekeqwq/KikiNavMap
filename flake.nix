{
  description = "KikiNavMap macOS — Minimalist Flight Planner, Swift, macOS 27 Liquid Glass";

  nixConfig = {
    sandbox = false;
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      meta = {
        description = "KikiNavMap macOS flight plan creation tool";
        license = lib.licenses.gpl3Plus;
        mainProgram = "kikinavmap";
      };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          triple = if system == "aarch64-darwin" then "arm64-apple-macos27.0" else "x86_64-apple-macos27.0";
          pkg = pkgs.stdenv.mkDerivation {
            pname = "kikinavmap";
            version = "1.0.0";
            src = lib.cleanSource ./.;
            dontUseNixBuildInputsCompiler = true;
            buildPhase = ''
              runHook preBuild
              unset NIX_CFLAGS_COMPILE NIX_LDFLAGS CC CXX MACOSX_DEPLOYMENT_TARGET
              unset SDKROOT
              if [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
                export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
              elif [ -d /Applications/Xcode.app/Contents/Developer ]; then
                export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
              else
                export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
              fi
              SDK=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
              SWIFT=$(/usr/bin/xcrun -f swiftc)
              test -n "$SDK" -a -x "$SWIFT"
              echo "kikinavmap: DEVELOPER_DIR=$DEVELOPER_DIR"
              echo "kikinavmap: SDK=$SDK"
              echo "kikinavmap: SWIFT=$SWIFT"

              EXTRA_ARGS=()
              if [ -d "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" ]; then
                EXTRA_ARGS+=("-plugin-path" "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins")
              fi

              mkdir -p .build/cache
              "$SWIFT" -O -parse-as-library \
                -sdk "$SDK" -target ${triple} \
                -Xfrontend -disable-sandbox \
                -module-cache-path .build/cache \
                "''${EXTRA_ARGS[@]}" \
                -o kikinavmap \
                $(find Sources/KikiNavMap -name "*.swift") \
                -framework SwiftUI -framework AppKit -framework MapKit \
                -framework CoreLocation -framework Combine -framework Foundation -framework Cocoa

              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              app=$out/Applications/KikiNavMap.app
              mkdir -p $app/Contents/MacOS $app/Contents/Resources $out/bin
              cp kikinavmap $app/Contents/MacOS/kikinavmap
              cp Info.plist $app/Contents/Info.plist
              printf 'APPL????' > $app/Contents/PkgInfo
              cp -R Sources/KikiNavMap/Resources/* $app/Contents/Resources/ || true
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --deep --sign - "$app" || true
              fi
              cat > $out/bin/kikinavmap <<EOFS
#!/bin/sh
set -e
dest="\$HOME/Applications/KikiNavMap.app"
src="$app"
mkdir -p "\$HOME/Applications"
stamp="\$dest/Contents/Resources/.nix-out"
if [ "\$(cat "\$stamp" 2>/dev/null || true)" != "\$src" ]; then
  rm -rf "\$dest"
  cp -R "\$src" "\$dest"
  chmod -R u+w "\$dest"
  echo "\$src" > "\$stamp"
fi
exec "\$dest/Contents/MacOS/kikinavmap" "\$@"
EOFS
              chmod +x $out/bin/kikinavmap
              printf '%s\n' '#!/bin/sh' "exec /usr/bin/open -n \"$app\"" > $out/bin/kikinavmap-app
              chmod +x $out/bin/kikinavmap-app
              runHook postInstall
            '';
            inherit meta;
          };
        in
        {
          default = pkg;
          kikinavmap = pkg;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkg = self.packages.${system}.default;
        in
        {
          default = {
            type = "app";
            program = "${pkg}/bin/kikinavmap";
          };
          kikinavmap = self.apps.${system}.default;
        }
      );
    };
}
