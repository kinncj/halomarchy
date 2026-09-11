# Architecture

## The stack, bottom to top

```mermaid
flowchart BT
    subgraph HW["Hardware"]
        CPU["Ryzen AI MAX+ PRO 395<br/>32 threads"]
        IGPU["Radeon 8060S iGPU<br/>gfx1151 · RDNA 3.5"]
        NPU["XDNA NPU<br/>RyzenAI-npu5"]
        MEM["128 GB unified<br/>109 GiB visible"]
    end

    subgraph KERN["Kernel drivers"]
        AMDGPU["amdgpu"]
        XDNA["amdxdna<br/>/dev/accel/accel0"]
    end

    subgraph RT["Userspace runtimes"]
        ROCM["ROCm 7.2.4<br/>HIP · rocBLAS · MIOpen · RCCL"]
        RADV["Mesa RADV<br/>Vulkan"]
    end

    subgraph TOOL["Engines"]
        OLLAMA["Ollama<br/>llama.cpp"]
        LEMON["Lemonade<br/>llama.cpp + own ROCm 7.14"]
        TORCH["PyTorch 2.12.1+rocm7.2<br/>Triton 3.7.1"]
    end

    subgraph APP["Consumers"]
        UNSLOTH["Unsloth<br/><i>training</i>"]
        AGENTS["opencode · agents<br/><i>OpenAI-compatible HTTP</i>"]
        JAVA["Java / C++ / Python"]
        STEAM["Steam · Proton"]
    end

    CPU & IGPU & MEM --> AMDGPU
    NPU --> XDNA
    AMDGPU --> ROCM & RADV
    ROCM --> OLLAMA & LEMON & TORCH
    RADV --> STEAM
    TORCH --> UNSLOTH
    OLLAMA & LEMON --> AGENTS & JAVA
    XDNA -.->|"no util counter,<br/>no PyTorch path"| TORCH

    classDef hw fill:#3d1f1f,stroke:#ff6b6b,color:#fff
    classDef k  fill:#1e3a5f,stroke:#4a9eff,color:#fff
    classDef r  fill:#2d1b4e,stroke:#a970ff,color:#fff
    classDef t  fill:#1a3d2e,stroke:#4ade80,color:#fff
    classDef a  fill:#3d3416,stroke:#fbbf24,color:#fff
    class CPU,IGPU,NPU,MEM hw
    class AMDGPU,XDNA k
    class ROCM,RADV r
    class OLLAMA,LEMON,TORCH t
    class UNSLOTH,AGENTS,JAVA,STEAM a
```

The NPU is driver-present but a dead end: `amdxdna` exposes no utilisation
counter and there is no PyTorch path to it. ROCm enumerates it as an HSA agent;
nothing consumes it.

## Memory: the number that actually constrains you

```mermaid
flowchart LR
    TOTAL["128 GB<br/>physical"] --> VIS["109 GiB<br/>OS-visible"]
    VIS --> VRAM["16 GiB<br/>VRAM carve-out"]
    VIS --> GTT["54.9 GiB<br/>GTT (~50% of RAM)"]
    VIS --> HOST["~54 GiB<br/>host"]
    GTT --> USABLE["what Ollama<br/>reports as VRAM"]

    classDef n fill:#1e3a5f,stroke:#4a9eff,color:#fff
    classDef h fill:#1a3d2e,stroke:#4ade80,color:#fff
    class TOTAL,VIS,VRAM,HOST n
    class GTT,USABLE h
```

`amdgpu` defaults GTT to ~50% of RAM. Raise it with `ttm.pages_limit` on the
kernel cmdline if a model needs more than ~55 GiB resident.

## Install flow

```mermaid
flowchart LR
    S(["./install.sh"]) --> M0["packages"] --> M1["environment"] --> MW["webcam"]
    MW --> M2["gaming"] --> M3["heimdall"] --> M4["ollama"]
    M4 --> M5["lemonade"] --> M6["unsloth"] --> M7["commands"] --> E(["ai status"])

    classDef s fill:#2d1b4e,stroke:#a970ff,color:#fff
    classDef m fill:#1e3a5f,stroke:#4a9eff,color:#fff
    class S,E s
    class M0,M1,MW,M2,M3,M4,M5,M6,M7 m
```

Ordering is load-bearing in two places: `environment` must precede
`unsloth` (bitsandbytes needs `rocminfo` on PATH), and `packages` must
precede everything (it installs `uv` and the ROCm toolchain).
