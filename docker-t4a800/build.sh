#!/bin/bash
# 构建 llama.cpp CUDA 11.4 Docker 镜像（双架构：sm_75 T4 + sm_80 A800）
# 镜像基于 CUDA 11.4.3 + Ubuntu 20.04
# 必须启用 BuildKit 以支持 --mount=type=cache 实现增量编译缓存
#
# 用法：
#   bash build.sh                    # 默认 75;80 双架构
#   CUDA_ARCH="75" bash build.sh     # 只编 T4
#   CUDA_ARCH="75;80;86" bash build.sh  # 扩展其他架构（如 RTX 30xx = 86）

IMAGE_NAME="zz-llama-cpp-cuda114-ubuntu2004"
IMAGE_TAG="b5401-t4a800"

# 强制启用 BuildKit（Docker 23.0+ 默认已启用，此处显式设置以确保兼容性）
export DOCKER_BUILDKIT=1

CUDA_ARCH="${CUDA_ARCH:-75;80}"

# 自动拉取源码：若当前目录没有 llama.cpp/ 源码，从本仓库 b5401 分支浅克隆
# （仓库布局：本目录位于 walkerlee-lab/llama.cpp 的 docker-t4a800/ 子目录，
#  独立使用时 clone 仓库后 cd docker-t4a800 && bash build.sh 即可）
if [ ! -f llama.cpp/CMakeLists.txt ]; then
  echo ">> llama.cpp 源码不存在，从 walkerlee-lab/llama.cpp b5401 分支浅克隆..."
  git clone -b b5401 --depth 1 git@github.com:walkerlee-lab/llama.cpp.git llama.cpp
fi

docker build \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    --build-arg CUDA_DOCKER_ARCH="${CUDA_ARCH}" \
    -f Dockerfile \
    .
