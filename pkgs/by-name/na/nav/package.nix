{
  curl,
  fetchFromGitHub,
  gradle,
  lib,
  stdenv,
}:

let
  system =
    {
      x86_64-linux = "X64";
      aarch64-linux = "Arm64";
    }
    .${stdenv.hostPlatform.system} or (throw "unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation rec {
  pname = "nav";
  version = "1.3.1";

  src = fetchFromGitHub {
    owner = "Jojo4GH";
    repo = "nav";
    rev = "v${version}";
    hash = "sha256-irytJA4aNvztI6I08mhVB+NC1rR58Z1iwq94F54qicM=";
  };

  # Kotlin Native dependency resolution (for all supported platforms)
  patchPhase = ''
    echo 'tasks.findByName("nixDownloadDeps")?.apply {
      dependsOn("commonizeNativeDistribution", "compileKotlinLinuxX64", "compileKotlinLinuxArm64")
    }' >> app/build.gradle.kts
  '';

  gradleFlags = [ "--no-configuration-cache" ];
  mitmCache = gradle.fetchDeps {
    inherit pname;
    data = ./deps.json;
  };

  # Kotlin Native build (with manual dependency resolution)
  nativeBuildInputs = [
    curl
    gradle
  ];
  buildPhase = ''
    runHook preBuild

    # Manually configure konan (mitm cache does not return content length header, preventing download)
    export KONAN_DATA_DIR=/build/.konan
    mkdir -p $KONAN_DATA_DIR/dependencies

    for dependency in ${
      let
        deps = builtins.fromJSON (builtins.readFile ./deps.json);
        konan = builtins.attrNames deps."https://download.jetbrains.com/kotlin/native";
        parsed = builtins.concatStringsSep " " konan;
      in
      parsed
    };
    do
      curl -s https://download.jetbrains.com/kotlin/native/$dependency.tar.gz | tar -xz -C $KONAN_DATA_DIR/dependencies
      echo $(basename $dependency) >> $KONAN_DATA_DIR/dependencies/.extracted
    done

    # # Preload other dependencies
    # echo 'tasks.register("nixDownloadDeps") {
    #   dependsOn("commonizeNativeDistribution", "compileKotlinLinux${system}")
    #   doLast { configurations.filter { it.isCanBeResolved }.forEach { it.resolve() } }
    # }' >> app/build.gradle.kts
    # gradle nixDownloadDeps

    gradle :app:linkReleaseExecutableLinux${system}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp app/build/bin/linux${system}/releaseExecutable/nav.kexe $out/bin/nav.exe

    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Interactive and stylish replacement for ls & cd";
    homepage = "https://github.com/Jojo4GH/nav";
    license = lib.licenses.mit;
    longDescription = ''
      To make use of nav, add the following lines to your configuration:
      `programs.bash.shellInit = "eval \"$(nav --init bash)\"";` and
      `programs.zsh.shellInit = "eval \"$(nav --init zsh)\"";`
    '';
    mainProgram = "nav";
    maintainers = with lib.maintainers; [
      David-Kopczynski
      Jojo4GH
    ];
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode # mitm cache
    ];
  };
}
