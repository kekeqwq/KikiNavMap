{
  description = "KikiNavMap macOS — Minimalist Flight Planner, Swift, Liquid Glass UI";

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
          targetArch = if system == "aarch64-darwin" then "arm64" else "x86_64";
          pkg = pkgs.stdenv.mkDerivation {
            pname = "kikinavmap";
            version = "1.1.0";
            src = lib.cleanSource ./.;
            dontUseNixBuildInputsCompiler = true;
            buildPhase = ''
              runHook preBuild
              unset NIX_CFLAGS_COMPILE NIX_LDFLAGS CC CXX MACOSX_DEPLOYMENT_TARGET
              unset SDKROOT DEVELOPER_DIR

              # Detect developer directory and plugins
              XCODE_DIR=""
              for candidate in "$DEVELOPER_DIR" "$(/usr/bin/xcode-select -p 2>/dev/null)" $(ls -d /Applications/Xcode*.app/Contents/Developer 2>/dev/null) "/Applications/Xcode.app/Contents/Developer"; do
                if [ -n "$candidate" ] && [ -d "$candidate" ] && [ -d "$candidate/Platforms/MacOSX.platform" ]; then
                  XCODE_DIR="$candidate"
                  break
                fi
              done

              EXTRA_FLAGS=""
              if [ -n "$XCODE_DIR" ]; then
                export DEVELOPER_DIR="$XCODE_DIR"
                SWIFT="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
                SDK="$XCODE_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
                PLUGIN_DIR="$XCODE_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
                if [ -d "$PLUGIN_DIR" ]; then
                  EXTRA_FLAGS="-plugin-path $PLUGIN_DIR"
                fi
              elif [ -x "/Library/Developer/CommandLineTools/usr/bin/swiftc" ]; then
                export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
                SWIFT="/Library/Developer/CommandLineTools/usr/bin/swiftc"
                SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
              else
                SDK=$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
                SWIFT=$(/usr/bin/xcrun -f swiftc 2>/dev/null || command -v swiftc 2>/dev/null || echo "/usr/bin/swiftc")
              fi

              echo "kikinavmap build: SDK=$SDK"
              echo "kikinavmap build: SWIFT=$SWIFT"
              echo "kikinavmap build: EXTRA_FLAGS=$EXTRA_FLAGS"

              mkdir -p .build/cache
              "$SWIFT" -O -parse-as-library \
                -sdk "$SDK" -target ${targetArch}-apple-macos14.0 \
                -Xfrontend -disable-sandbox \
                -module-cache-path .build/cache \
                $EXTRA_FLAGS \
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
