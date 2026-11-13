# llama.cpp Docker image for CUDA 11.4 with Qwen3 8B GGUF support
# 双架构版本：同时支持 Tesla T4 (sm_75) 和 A800/A100 (sm_80)
# 构建阶段使用 devel 镜像（包含 nvcc 编译器和头文件），运行阶段使用 runtime 镜像
# CUDA 11.4 仅提供 ubuntu20.04 变体，不支持 ubuntu22.04
#
# 缓存优化：使用 BuildKit --mount=type=cache 持久化 apt/pip/build 缓存，
# 即使 COPY 层因源码变动失效，cmake 增量编译也能复用已编译的 .o 文件
#
# 支持的 GPU 架构（默认 75;80，可用 --build-arg CUDA_DOCKER_ARCH 覆盖）：
#   sm_75 (compute 7.5) -> Tesla T4 / T4s、GTX 16xx、RTX 20xx (Turing)
#   sm_80 (compute 8.0) -> A800 / A100 / A30 (Ampere)
# 驱动要求：NVIDIA driver >= 470.57（CUDA 11.4 最低驱动），实测 535.54.03 可用

ARG UBUNTU_VERSION=20.04
ARG CUDA_VERSION=11.4.3

ARG BASE_CUDA_DEV_CONTAINER=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}
ARG BASE_CUDA_RUN_CONTAINER=nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

FROM ${BASE_CUDA_DEV_CONTAINER} AS build

# 双架构：75 = T4 (Turing)，80 = A800/A100 (Ampere)
ARG CUDA_DOCKER_ARCH=75;80

# 禁用交互式安装提示（如 tzdata 时区选择）
ENV DEBIAN_FRONTEND=noninteractive

# 全局设置 apt-get 下载重试次数，应对国内网络不稳定
RUN echo 'Acquire::Retries "20";' > /etc/apt/apt.conf.d/80-retries

# 切换为阿里云镜像源，避免国内网络访问 archive.ubuntu.com 超时
RUN sed -i 's|http://archive.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list && \
    sed -i 's|http://security.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list

# 安装 gcc-10 和 g++-10（CUDA 11.4 最高支持 GCC 10，GCC 11 会导致 nvcc 编译报错）
# Ubuntu 20.04 默认源已包含 gcc-10/g++-10，无需额外 PPA
# --mount=type=cache 持久化 apt 缓存，重装时无需重新下载 deb 包
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends gcc-10 g++-10 build-essential git ninja-build python3 python3-pip libgomp1 libcurl4-openssl-dev wget && \
    pip3 install --no-cache-dir -i https://mirrors.aliyuncs.com/pypi/simple/ cmake

# 设置 gcc-10 为默认编译器（CUDA 11.4 不兼容 GCC 11+）
ENV CC=gcc-10 CXX=g++-10 CUDAHOSTCXX=g++-10

WORKDIR /app/llama.cpp

# 直接复制本地 llama.cpp 源码（.dockerignore 已排除 .git 目录）
COPY llama.cpp/ .

# 移除 GCC 10 不支持的 CPU 变体：alderlake 需要 -mavxvnni (GCC 11+)，
# sapphirerapids 需要 -mamx-tile/-mamx-int8 (GCC 12+)
# CUDA 11.4 最高仅支持 GCC 10，必须去掉这两个变体才能开启 GGML_CPU_ALL_VARIANTS
RUN sed -i '/ggml_add_cpu_backend_variant(alderlake/d' ggml/src/CMakeLists.txt && \
    sed -i '/ggml_add_cpu_backend_variant(sapphirerapids/d' ggml/src/CMakeLists.txt

# 使用 CUDA 编译 llama.cpp，指定 sm_75;sm_80 双架构
# --mount=type=cache,target=/app/llama.cpp/build 持久化 cmake 构建目录
# 即使源码有轻微变动，cmake 增量编译也能复用大部分已编译的 .o 文件
RUN --mount=type=cache,target=/app/llama.cpp/build \
    if [ "${CUDA_DOCKER_ARCH}" != "default" ]; then \
    CMAKE_ARGS="-DCMAKE_CUDA_ARCHITECTURES=${CUDA_DOCKER_ARCH}"; \
    else \
    CMAKE_ARGS=""; \
    fi && \
    rm -f build/CMakeCache.txt && \
    cmake -B build \
        -DGGML_NATIVE=OFF \
        -DGGML_CUDA=ON \
        -DGGML_BACKEND_DL=ON \
        -DGGML_CPU_ALL_VARIANTS=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        ${CMAKE_ARGS} \
        -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined . && \
    cmake --build build --config Release -j$(nproc)

# 收集编译产物：共享库（从缓存挂载的 build 目录中复制）
# 若 .so 文件缺失则明确报错，避免后续 COPY --from=build 时产生难以理解的错误
RUN --mount=type=cache,target=/app/llama.cpp/build \
    mkdir -p /app/lib && \
    SO_COUNT=$(find build -name "*.so" | tee /tmp/so_list.txt | wc -l) && \
    if [ "$SO_COUNT" -eq 0 ]; then echo "ERROR: No .so files found in build directory" >&2; exit 1; fi && \
    xargs -a /tmp/so_list.txt -I{} cp {} /app/lib

# 收集编译产物：可执行文件和 Python 辅助文件
RUN --mount=type=cache,target=/app/llama.cpp/build \
    mkdir -p /app/full && \
    BIN_COUNT=$(find build/bin -type f 2>/dev/null | tee /tmp/bin_list.txt | wc -l) && \
    if [ "$BIN_COUNT" -eq 0 ]; then echo "ERROR: No binaries found in build/bin" >&2; exit 1; fi && \
    cp build/bin/* /app/full && \
    cp *.py /app/full 2>/dev/null; true && \
    cp -r gguf-py /app/full 2>/dev/null; true && \
    cp -r requirements /app/full 2>/dev/null; true && \
    cp requirements.txt /app/full 2>/dev/null; true && \
    cp .devops/tools.sh /app/full/tools.sh 2>/dev/null; true

# 运行阶段：使用精简的 runtime 镜像
FROM ${BASE_CUDA_RUN_CONTAINER} AS base

# 全局设置 apt-get 下载重试次数
RUN echo 'Acquire::Retries "10";' > /etc/apt/apt.conf.d/80-retries

# 切换为阿里云镜像源
RUN sed -i 's|http://archive.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list && \
    sed -i 's|http://security.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 curl ca-certificates \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /tmp/* /var/tmp/*

# 复制共享库和可执行文件（.so 放到 /app 与官方一致，避免 rpath 不匹配）
COPY --from=build /app/lib/ /app
COPY --from=build /app/full/llama-cli /app/
COPY --from=build /app/full/llama-server /app/

# 设置库路径
ENV LD_LIBRARY_PATH=/app:${LD_LIBRARY_PATH}

WORKDIR /app/models

# 默认入口：llama-cli 用于交互式推理
ENTRYPOINT ["/app/llama-cli"]
