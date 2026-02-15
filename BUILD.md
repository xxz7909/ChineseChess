# 编译与打包文档（Windows）

本文档用于在本仓库复现 APK 构建，并避免已踩过的问题。

## 1. 环境要求

- Windows 10/11
- Flutter 3.x（建议稳定版）
- Android SDK（含 platform-tools、build-tools）
- JDK 17

建议路径（可按实际调整）：

- Flutter：C:/flutter
- Android SDK：C:/Users/<用户名>/AppData/Local/Android/Sdk
- JDK17：C:/JDK17/jdk-17

## 2. 关键文件要求

必须具备以下文件，否则引擎会启动后直接退出：

- app/android/app/src/main/jniLibs/arm64-v8a/libpikafish.so
- app/android/app/src/main/jniLibs/arm64-v8a/libpikafish_dotprod.so
- app/android/app/src/main/assets/pikafish.nnue

说明：

- libpikafish.so / libpikafish_dotprod.so：引擎可执行体
- pikafish.nnue：神经网络权重（必需）

## 3. 从会话沉淀出的稳定构建流程

在 PowerShell 中执行：

1) 进入工程目录

- cd C:/Users/<用户名>/Desktop/xiangqi/ChineseChess/app

2) 设置环境变量（建议每次构建前设置）

- $env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
- $env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
- $env:ANDROID_HOME="C:/Users/<用户名>/AppData/Local/Android/Sdk"
- $env:ANDROID_SDK_ROOT="C:/Users/<用户名>/AppData/Local/Android/Sdk"
- $env:JAVA_HOME="C:/JDK17/jdk-17"
- $env:PATH="C:/flutter/bin;$env:JAVA_HOME/bin;C:/Program Files/Git/cmd;$env:PATH"

3) 拉取依赖

- flutter pub get

4) 静态检查

- flutter analyze

5) 构建 Release APK

- flutter build apk --release

6) 产物位置

- app/build/app/outputs/flutter-apk/app-release.apk

## 4. 国内网络建议（已在工程配置）

为减少 Google 源访问失败，Android Gradle 仓库已增加镜像：

- storage.flutter-io.cn/download.flutter.io
- maven.aliyun.com/repository/google
- maven.aliyun.com/repository/central

如仍遇网络失败，重试构建通常可恢复。

## 5. 首次安装后的行为

- 首次启动会把 assets 中的 pikafish.nnue 复制到应用缓存目录
- 复制完成后引擎再启动
- 首次耗时略高，属正常

## 6. 常见问题

### 6.1 引擎一直转圈或异常退出

优先检查：

- 是否包含 pikafish.nnue
- 是否能在 App 菜单中看到引擎日志
- 日志中是否出现 NNUE 相关错误

### 6.2 Gradle 锁冲突

现象：Timeout waiting to lock build logic queue

处理：

- 结束残留 Java/Gradle 进程
- 删除 app/android/.gradle 后重试

### 6.3 Flutter 依赖下载失败

处理：

- 确认 FLUTTER_STORAGE_BASE_URL / PUB_HOSTED_URL 已设置为镜像
- 检查 PATH 中是否包含 git 与 powershell

## 7. 发布建议

- 先在至少两台不同 SoC 设备验证（例如骁龙 / 天玑）
- 首次启动等待 NNUE 复制完成后再开始对局
- 如用户反馈异常，优先让其导出并提供“引擎日志”
