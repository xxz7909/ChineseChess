# 中国象棋（Pikafish 引擎）

一个基于 Flutter 的中国象棋 Android 应用，后端使用 Pikafish（UCI 协议）实现人机对战。

## 项目目标

- 支持 Android 9+（API 28+）
- 人机对战，默认最强难度
- 自动按 CPU 特征选择引擎变体（armv8 / armv8-dotprod）
- 支持引擎异常重启与日志查看

## 技术架构

- 前端：Flutter
- 引擎：Pikafish（子进程 + UCI）
- 平台桥接：Android MethodChannel
- 引擎文件：
  - libpikafish.so（基础 armv8）
  - libpikafish_dotprod.so（支持 dotprod 指令时优先）
  - pikafish.nnue（神经网络权重，必须存在）

## 根因与关键修复（本项目已落地）

历史问题：引擎进程启动后反复崩溃、AI 一直转圈。

核心根因：Pikafish 缺少 pikafish.nnue 时会直接退出。

已修复：

- 将 pikafish.nnue 打包到 Android assets
- 首次启动流式复制到应用缓存目录（避免 51MB 一次性入内存）
- 引擎启动前先确保 NNUE 文件可用
- UCI 通信增加 flush / isready 同步
- 监听引擎 exitCode 并自动重启
- 增加引擎日志弹窗与复制功能

## 仓库结构

- app：Flutter 主工程
- scripts：构建与下载脚本
- BUILD.md：详细编译与打包文档

## 快速开始（Windows）

1. 准备环境：Flutter、Android SDK、JDK 17
2. 将 NNUE 文件放在仓库根目录：
   - pikafish.nnue
3. 在 app 目录执行：
   - flutter pub get
   - flutter build apk --release
4. 产物路径：
   - app/build/app/outputs/flutter-apk/app-release.apk

完整步骤见 BUILD.md。

## 运行与排错

- App 内菜单可打开“引擎日志”
- 支持“复制日志”便于问题定位
- 首次启动会复制 NNUE，耗时略长属正常

## 说明

- 当前 Android ABI 目标为 arm64-v8a（主流 Android 9+ 设备覆盖率高）
- 若后续需要 x86_64 / armeabi-v7a，可再扩展 jniLibs 与打包配置
