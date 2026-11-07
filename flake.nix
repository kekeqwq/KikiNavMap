{
  description = "KikiNavMap — sandboxed Nix build for Apple Silicon";
  nixConfig.sandbox = true;
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;
      swift = pkgs.swift.override {
        enableRepl = false;
        enableSourceKitLSP = false;
      };
      kikinavmap = pkgs.swiftPackages.stdenv.mkDerivation {
        pname = "kikinavmap";
        version = "1.1.1";
        src = lib.cleanSource ./.;
        strictDeps = true;
        nativeBuildInputs = [ swift ];
        buildInputs = [ pkgs.apple-sdk_27 ];
        buildPhase = ''
          runHook preBuild
          test "$SDKROOT" = "${pkgs.apple-sdk_27}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
          export HOME="$TMPDIR/home"
          export CLANG_MODULE_CACHE_PATH="$TMPDIR/clang-module-cache"
          mkdir -p "$HOME" "$CLANG_MODULE_CACHE_PATH"
          mapfile -t sources < <(find Sources/KikiNavMap -name '*.swift' -print | sort)
          ${swift}/bin/swiftc -O -parse-as-library \
            -sdk "$SDKROOT" -target arm64-apple-macosx27.0 \
            -module-cache-path "$TMPDIR/swift-module-cache" \
            -o kikinavmap "''${sources[@]}" \
            -framework SwiftUI -framework AppKit -framework MapKit \
            -framework CoreLocation -framework Combine -framework Foundation -framework Cocoa
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          app="$out/Applications/KikiNavMap.app"
          mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$out/bin"
          install -m755 kikinavmap "$app/Contents/MacOS/kikinavmap"
          cp Info.plist "$app/Contents/Info.plist"
          printf 'APPL????' > "$app/Contents/PkgInfo"
          cp -R Sources/KikiNavMap/Resources/. "$app/Contents/Resources/"
          cat > "$out/bin/kikinavmap" <<EOF
          #!${pkgs.runtimeShell}
          set -eu
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
          EOF
          chmod +x "$out/bin/kikinavmap"
          printf '%s\n' '#!${pkgs.runtimeShell}' "exec /usr/bin/open -n \"$app\" \"\$@\"" > "$out/bin/kikinavmap-app"
          chmod +x "$out/bin/kikinavmap-app"
          runHook postInstall
        '';
        meta = {
          description = "KikiNavMap flight planner";
          license = lib.licenses.gpl3Plus;
          mainProgram = "kikinavmap";
          platforms = [ system ];
        };
      };
    in {
      packages.${system} = { default = kikinavmap; inherit kikinavmap; };
      apps.${system} = {
        default = self.apps.${system}.kikinavmap;
        kikinavmap = { type = "app"; program = "${kikinavmap}/bin/kikinavmap"; };
        app = { type = "app"; program = "${kikinavmap}/bin/kikinavmap-app"; };
      };
      checks.${system} = {
        build = kikinavmap;
        tests = pkgs.swiftPackages.stdenv.mkDerivation {
          pname = "kikinavmap-tests";
          version = kikinavmap.version;
          src = lib.cleanSource ./.;
          strictDeps = true;
          nativeBuildInputs = [ swift pkgs.swiftpm pkgs.darwin.sigtool ];
          buildInputs = [ pkgs.apple-sdk_27 ];
          buildPhase = ''
            runHook preBuild
            export HOME="$TMPDIR/home"
            export CLANG_MODULE_CACHE_PATH="$TMPDIR/clang-module-cache"
            mkdir -p "$HOME" "$CLANG_MODULE_CACHE_PATH"
            # Native SwiftPM + Swift Testing needs neither Xcode nor xctest.
            swift test --build-system native --disable-xctest
            runHook postBuild
          '';
          installPhase = "mkdir -p $out; touch $out/passed";
        };
      };
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = [ swift pkgs.swiftpm pkgs.darwin.sigtool ];
        buildInputs = [ pkgs.apple-sdk_27 ];
      };
      overlays.default = final: prev:
        lib.optionalAttrs (prev.stdenv.hostPlatform.system == system) {
          kikinavmap = self.packages.${system}.default;
        };
    };
}
