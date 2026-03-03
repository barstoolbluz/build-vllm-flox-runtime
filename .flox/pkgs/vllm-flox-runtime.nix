{ stdenv, lib }:

stdenv.mkDerivation {
  pname = "vllm-flox-runtime";
  version = "0.9.1";

  src = ../../scripts;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    for script in vllm-serve vllm-preflight vllm-resolve-model; do
      install -m 0755 "$script" "$out/bin/$script"
    done

    mkdir -p $out/share/vllm-flox-runtime
    cat > "$out/share/vllm-flox-runtime/vllm-flox-runtime-$version" <<'MARKER'
    Initial release of vllm-flox-runtime scripts.
    - vllm-serve: model env loading and validated vllm serve execution
    - vllm-preflight: port reclaim, GPU health check, downstream exec
    - vllm-resolve-model: multi-source model provisioning (flox, local, hf-cache, r2, hf-hub)
    MARKER
  '';

  meta = with lib; {
    description = "Runtime scripts for vLLM model serving with Flox";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
