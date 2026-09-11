# ROCm user tools (amd-smi, rocm-smi, rocminfo, hipcc) live outside the default PATH.
case ":$PATH:" in
    *:/opt/rocm/bin:*) ;;
    *) PATH="/opt/rocm/bin:$PATH" ;;
esac
export PATH

# Flash / mem-efficient attention on RDNA3.5 is gated behind this flag.
# Measured 2x faster LoRA steps on gfx1151 (3.1s -> 1.5s), identical loss.
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
