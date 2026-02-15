

  

Created 5 todos

读取 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/lib/engine/pikafish_engine.dart#1-1)，行 1 到 20

读取 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/lib/engine/pikafish_engine.dart#150-150)，行 150 到 165

读取 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/lib/engine/pikafish_engine.dart#240-240)，行 240 到 280

读取 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/lib/engine/pikafish_engine.dart#390-390)，行 390 到 430

读取 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/lib/engine/pikafish_engine.dart#480-480)，行 480 到 504

读取 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/lib/engine/pikafish_engine.dart#167-167)，行 167 到 175

Starting: *增强诊断：SHA256+子进程测试* (2/5)

现在实施所有增强诊断代码。关键分析：引擎 `readyok` 只代表 UCI 就绪，**不代表 NNUE 加载成功**。`verify()` 在搜索时才检查，此时才发现加载失败。我需要诊断**为什么** `load_user_net()` 静默失败。 

正在将 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/lib/engine/pikafish_engine.dart) 中的 53 行替换为 146 行


```

```
Now add SHA256 verification in Kotlin:  

读取 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/android/app/src/main/kotlin/com/xiangqi/chinese_chess/MainActivity.kt#75-75)，行 75 到 99

正在将 [](file:///c%3A/Users/xzw65/Desktop/xiangqi/ChineseChess/app/android/app/src/main/kotlin/com/xiangqi/chinese_chess/MainActivity.kt) 中的 5 行替换为 26 行


```

```


Starting: *构建新APK* (4/5)

Ran terminal command: C:\flutter\bin\flutter.bat build apk --debug 2>&1

Completed: *构建新APK* (4/5)

APK 构建成功。以下是**完整的调试方案**：

---

## 新 APK 增强诊断

安装新 APK 后运行，应用内调试日志会多出以下诊断信息：
1. **完整 CPU 特征**（不再截断）
2. **子进程文件访问测试**（`ls -la`、`wc -c`、`sha256sum`、`od`、CWD 相对路径）— 验证引擎子进程能否读取文件  
3. **SHA256 校验**（Kotlin 侧计算并与 Windows 上的哈希对比）
4. **引擎 Debug Log File** — 捕获 UCI 通信内部日志
5. **崩溃后自动读取引擎调试日志**

---

## ADB 调试指令

连上手机后，在电脑终端执行以下命令：

### 1. 查看 Kotlin 侧日志（SHA256 + 文件复制状态）
```bash
adb logcat -s PikafishNNUE:V
```
会看到 `SHA256: xxxx` 和 `SHA256 VERIFIED OK` 或 `SHA256 MISMATCH!`

### 2. 查看所有相关日志
```bash
adb logcat | findstr /i "pikafish nnue evalfile fatal signal"
```

### 3. 查看 SELinux 拒绝日志（最可能的根因之一）
```bash
adb logcat | findstr /i "avc.*denied"
```

### 4. 手动验证文件（最关键的测试）
```bash
adb shell
run-as com.xiangqi.chinese_chess sh
ls -la /data/user/0/com.xiangqi.chinese_chess/cache/pikafish.nnue
sha256sum /data/user/0/com.xiangqi.chinese_chess/cache/pikafish.nnue
```
预期 SHA256: `e6ec544cc330b83346cd47091fa027225ff963d04017d8cd88fc0c82f7c267e4`

### 5. **手动运行引擎（最有价值的测试！）**

这能直接看到引擎的 stderr 输出，判断是文件问题还是引擎问题：

```bash
adb shell
run-as com.xiangqi.chinese_chess sh
cd /data/user/0/com.xiangqi.chinese_chess/cache

# 先试基础版引擎（不用 dotprod）
/data/app/~~L_K13Ox1n1XtLC2z8iiByA==/com.xiangqi.chinese_chess-sD1k25Pnw2fjVBmoI0H6zw==/lib/arm64/libpikafish.so
```

引擎启动后，逐行输入以下 UCI 命令：
```
uci
setoption name EvalFile value /data/user/0/com.xiangqi.chinese_chess/cache/pikafish.nnue
isready
position startpos
go depth 5
```

如果**基础版引擎**可以正常工作（输出 `bestmove`），说明 dotprod 版本有问题。然后再试 dotprod 版本：
```bash
/data/app/~~L_K13Ox1n1XtLC2z8iiByA==/com.xiangqi.chinese_chess-sD1k25Pnw2fjVBmoI0H6zw==/lib/arm64/libpikafish_dotprod.so
```

> 注意：上面的路径 `~~L_K13Ox1n1XtLC2z8iiByA==` 等随机部分来自你的日志，用你实际日志中的路径。

### 6. 查看引擎调试日志文件
```bash
adb shell run-as com.xiangqi.chinese_chess cat /data/user/0/com.xiangqi.chinese_chess/cache/engine_debug.log
```

---

请安装新 APK，**将应用内调试日志完整截图/复制给我**，特别关注：
- `SHA256` 验证结果
- `Subprocess file access test` 部分
- `ENGINE DEBUG LOG` 部分
- 如果方便，运行上面的 **ADB 手动引擎测试**（第 5 步），把输出贴给我

Made changes.