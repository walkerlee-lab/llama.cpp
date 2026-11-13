# llama.cpp CUDA 11.4 双架构镜像（T4 + A800）

基于原 `D:\docker\llama_cpp_cuda114` 项目构建思路，独立目录，源码取自
`walkerlee-lab/llama.cpp` 的 `b5401` 分支（commit `bc098c3cf`，与原目录完全一致，
官方源码无任何本地修改）。

## 版本支持说明

| 项目 | 版本 / 要求 |
|---|---|
| CUDA Runtime | **11.4.3**（cudart 11.4.148，与原 cuda114 镜像一致） |
| NVIDIA 驱动 | **≥ 470.57**（CUDA 11.4 最低驱动；实测 535.54.03、596.52 均可用） |
| llama.cpp | b5401（含 qwen3 架构 + minja 聊天模板支持） |
| 模型 | Qwen3 8B GGUF（如 Qwen3-8B-Q4_K_M） |

## GPU 架构支持（默认编译 `CUDA_DOCKER_ARCH=75;80`）

| GPU | 架构 | 是否支持 |
|---|---|---|
| **Tesla T4 / T4s**（Turing） | sm_75 (compute 7.5) | ✅ 原生 SASS |
| **A800 / A100 / A30**（Ampere） | sm_80 (compute 8.0) | ✅ 原生 SASS |
| RTX 2060~2080 / GTX 16xx（Turing） | sm_75 | ✅ 原生 SASS |
| RTX 30xx（sm_86）/ RTX 40xx（sm_89）/ Hopper 等 | 86 / 89 / 90 | ⚠️ 通过内嵌 PTX JIT 兼容（首次加载较慢），或重编 `CUDA_ARCH="75;80;86;89"` |
| V100（sm_70）/ Pascal 等 | 70 / 6x | ❌ 未编译，需扩展 ARCH |

说明：CMake 会为每个架构同时生成 SASS（原生二进制）和 PTX（虚拟指令集），
PTX 可向新架构 JIT，因此高代卡一般也能跑，但原生 SASS 性能最好、启动最快。

## 构建方法

```bash
cd /d/docker/llama_cpp_cuda114_t4a800
bash build.sh                    # 默认 75;80
# 或指定架构
CUDA_ARCH="75" bash build.sh     # 只编 T4，速度减半
```

需要 Docker 23.0+（或手动 `export DOCKER_BUILDKIT=1`）。

## 运行验证（本机有 GPU 时）

```bash
# llama-cli 简单推理
docker run --rm --gpus all -v D:/models:/app/models \
  zz-llama-cpp-cuda114-ubuntu2004:b5401-t4a800 \
  -m /app/models/Qwen3-8B-Q4_K_M.gguf -n 64 --temp 0 -p "Hello"

# llama-server（OpenAI 兼容 API）
docker run -d --gpus all -p 8080:8080 -v D:/models:/app/models \
  --entrypoint /app/llama-server zz-llama-cpp-cuda114-ubuntu2004:b5401-t4a800 \
  -m /app/models/Qwen3-8B-Q4_K_M.gguf --host 0.0.0.0 --port 8080 -c 4096 --jinja
```

`--jinja` 启用 minja 模板渲染（b5401 已同步 qwen3 模板）；若 GGUF 内嵌了
`tokenizer.chat_template` 则输出格式正确，无需额外模板文件。

## 与原目录（D:\docker\llama_cpp_cuda114）的差异

仅 3 处，源码与编译流程完全一致：

1. `CUDA_DOCKER_ARCH` 默认值：`80` → **`75;80`**（新增 T4 支持）
2. 源码来源：本地目录 → **walkerlee-lab/llama.cpp b5401 分支**（同 commit `bc098c3cf`）
3. Dockerfile 头部注释更新 + pip 镜像改为 aliyuncs.com
