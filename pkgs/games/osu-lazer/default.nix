{ lib
, stdenvNoCC
, buildDotnetModule
, fetchFromGitHub
, makeDesktopItem
, copyDesktopItems
, ffmpeg
, alsa-lib
, SDL2
, lttng-ust
, numactl
, dotnetCorePackages
}:

buildDotnetModule rec {
  pname = "osu-lazer";
  version = "2022.409.0";

  src = fetchFromGitHub {
    owner = "ppy";
    repo = "osu";
    rev = version;
    sha256 = "sha256-qG9797SA0iMq9IF5SzQLgnhoUd2FKSAVXUPem1LQc1M=";
  };

  projectFile = "osu.Desktop/osu.Desktop.csproj";
  nugetDeps = ./deps.nix;

  dotnet-sdk = dotnetCorePackages.sdk_6_0;
  dotnet-runtime = dotnetCorePackages.runtime_6_0;

  nativeBuildInputs = [ copyDesktopItems ];

  dotnetFlags = [
    "--runtime linux-x64"
  ];

  runtimeDeps = [
    ffmpeg
    alsa-lib
    SDL2
    lttng-ust
    numactl
  ];

  executables = [ "osu!" ];

  fixupPhase = ''
    runHook preFixup

    for i in 16 32 48 64 96 128 256 512 1024; do
      install -D ./assets/lazer.png $out/share/icons/hicolor/''${i}x$i/apps/osu\!.png
    done

    ln -sft $out/lib/${pname} ${SDL2}/lib/libSDL2${stdenvNoCC.hostPlatform.extensions.sharedLibrary}
    cp -f ${./osu.runtimeconfig.json} "$out/lib/${pname}/osu!.runtimeconfig.json"

    runHook postFixup
  '';

  desktopItems = [(makeDesktopItem {
    desktopName = "osu!";
    name = "osu";
    exec = "osu!";
    icon = "osu!";
    comment = meta.description;
    type = "Application";
    categories = [ "Game" ];
  })];

  meta = with lib; {
    description = "Rhythm is just a *click* away";
    homepage = "https://osu.ppy.sh";
    license = with licenses; [
      mit
      cc-by-nc-40
      unfreeRedistributable # osu-framework contains libbass.so in repository
    ];
    maintainers = with maintainers; [ oxalica ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "osu!";
  };
  passthru.updateScript = ./update.sh;
}
