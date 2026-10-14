{
  lib,
  rustPlatform,
  installShellFiles,
  source,
}:
let
  mtime = source.lastModifiedDate;
  date = "${lib.substring 0 4 mtime}-${lib.substring 4 2 mtime}-${lib.substring 6 2 mtime}";
in
rustPlatform.buildRustPackage rec {
  pname = "histodu";
  version = "unstable-${date}";
  src = source;
  cargoLock.lockFile = source + "/Cargo.lock";
  buildFeatures = [ "completion" ];
  CFG_RELEASE = "git-${source.rev}";
  nativeBuildInputs = [ installShellFiles ];
  postInstall = ''
    installShellCompletion \
      --bash completions/bash/${pname}.bash \
      --fish completions/fish/${pname}.fish \
      --zsh completions/zsh/_${pname}
  '';
  meta = {
    description = "Summarize file size distribution, quickly";
    homepage = "https://github.com/oxalica/histodu";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "histodu";
  };
}
