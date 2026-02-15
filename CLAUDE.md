# CLAUDE.md


## 项目上下文

每次会话开始时，先读取以下文件了解项目状态：

1. 读取 `.claude-summary.md` 了解项目概述
2. 读取 `.tasks/current.md` 了解当前任务状态


## 关键技术发现

### NNUE 加载问题根因分析（2025-01-XX）

**核心结论**: NNUE 文件 (pikafish.nnue) 与引擎二进制 100% 兼容。

- 引擎预期的 `Network::hash` = `0x6E24D34A`
- NNUE 文件头中的哈希值 = `0x6E24D34A`
- **完全匹配**

**根因**: 引擎进程无法从 CWD 找到 NNUE 文件。
- Android 上 `Process.start(workingDirectory: cacheDir)` 可能未正确设置子进程 CWD
- 引擎构造函数尝试 `read_compressed_nnue("pikafish.nnue")` (相对路径) → 失败
- 之后尝试 `binaryDirectory + "pikafish.nnue"` → 文件不在 lib 目录 → 也失败

**修复方案**: 使用绝对路径设置 `setoption name EvalFile value /data/.../cache/pikafish.nnue`
- Pikafish 源码确认：`load_user_net("", "/absolute/path")` → 打开绝对路径
- 成功后 `evalFile.current = "/absolute/path"`
- `verify(options["EvalFile"])` 对比同样的绝对路径 → 匹配
- 之前分析说绝对路径导致路径不匹配是**错误的**

### 哈希计算公式
```
Network::hash = Transformer::get_hash_value() ^ Arch::get_hash_value()

Transformer hash = FullThreats::HashValue(0x0D17B100) ^ (OutputDimensions * 2)
                 = 0x0D17B100 ^ (1024 * 2) = 0x0D17B900

Arch hash 链:
  init: 0xEC42E90D ^ (1024*2) = 0xEC42E10D
  → AffineTransformSparseInput<1024,16> → 0x3A22AA72
  → ClippedReLU<16> → 0x8DAFCF39
  → AffineTransform<30,32> → 0x0AD43C98
  → ClippedReLU<32> → 0x5E61615F
  → AffineTransform<32,1> → 0x63336A4A

Network::hash = 0x0D17B900 ^ 0x63336A4A = 0x6E24D34A ✓
```
