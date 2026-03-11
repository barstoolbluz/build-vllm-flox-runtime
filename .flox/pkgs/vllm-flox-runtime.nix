{ stdenv, lib }:

let
  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/vllm-flox-runtime.json);
  buildVersion = buildMeta.build_version;
  version = "0.9.1";
in

stdenv.mkDerivation {
  pname = "vllm-flox-runtime";
  inherit version;

  src = ../../scripts;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    for script in vllm-serve vllm-preflight vllm-resolve-model; do
      install -m 0755 "$script" "$out/bin/$script"
    done

    mkdir -p $out/share/vllm-flox-runtime
    cat > $out/share/vllm-flox-runtime/flox-build-version-${toString buildVersion} <<'MARKER'
    build-version: ${toString buildVersion}
    upstream-version: ${version}
    upstream-tag: ${version}
    git-rev: ${buildMeta.git_rev}
    git-rev-short: ${buildMeta.git_rev_short}
    force-increment: ${toString buildMeta.force_increment}
    changelog: ${buildMeta.changelog}
    MARKER
  '';

  meta = with lib; {
    description = "Runtime scripts for vLLM model serving with Flox";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
