import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Pikafish UCI引擎通信接口
/// 关键修复：utf8解码、stdin flush、isready同步、进程退出监控、FEN定位、CPU自动检测
class PikafishEngine {
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  bool _isReady = false;
  String? _enginePath;
  bool _isSearching = false;

  // 同步等待机制
  String? _waitToken;
  Completer<bool>? _waitCompleter;

  /// 引擎是否就绪
  bool get isReady => _isReady;

  /// 是否正在搜索
  bool get isSearching => _isSearching;

  /// 最佳走法回调
  Function(String bestMove, String? ponder)? onBestMove;

  /// 搜索信息回调
  Function(String info)? onInfo;

  /// 引擎错误回调
  Function(String error)? onError;

  /// 引擎意外退出回调
  Function()? onEngineExit;

  /// 选中的引擎变体名称
  String engineVariant = '';

  /// 调试日志
  final List<String> _debugLog = [];
  List<String> get debugLog => List.unmodifiable(_debugLog);

  void _log(String msg) {
    final ts = DateTime.now().toString().substring(11, 23);
    _debugLog.add('$ts $msg');
    if (_debugLog.length > 500) _debugLog.removeAt(0);
  }

  /// 初始化引擎
  Future<bool> init() async {
    try {
      _enginePath = await _findEngineBinary();
      if (_enginePath == null) {
        _log('ERROR: No engine binary found');
        return false;
      }
      _log('Engine binary: $_enginePath');

      // 验证文件
      final file = File(_enginePath!);
      if (!await file.exists()) {
        _log('ERROR: Engine file does not exist at $_enginePath');
        return false;
      }
      final size = await file.length();
      _log('Engine size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');

      // *** 关键：确保NNUE神经网络文件已就位 ***
      final nnueReady = await _ensureNnueFile();
      if (!nnueReady) {
        _log('ERROR: NNUE file not available - engine will crash without it');
        return false;
      }

      return await _startProcess();
    } catch (e, st) {
      _log('ERROR: init exception: $e\n$st');
      return false;
    }
  }

  /// 确保NNUE神经网络文件在引擎工作目录（缓存目录）中
  Future<bool> _ensureNnueFile() async {
    try {
      const platform = MethodChannel('com.xiangqi.chinese_chess/engine');
      _log('Copying NNUE file to cache dir...');
      final nnuePath =
          await platform.invokeMethod<String>('copyNnueFile');
      if (nnuePath != null && nnuePath.isNotEmpty) {
        final nnueFile = File(nnuePath);
        if (await nnueFile.exists()) {
          final nnueSize = await nnueFile.length();
          _log('NNUE ready: $nnuePath (${(nnueSize / 1024 / 1024).toStringAsFixed(2)} MB)');
          return true;
        }
      }
      _log('ERROR: copyNnueFile returned invalid path: $nnuePath');
      return false;
    } catch (e) {
      _log('ERROR: Failed to prepare NNUE file: $e');
      return false;
    }
  }

  /// 查找最适合当前设备的引擎二进制
  Future<String?> _findEngineBinary() async {
    if (!Platform.isAndroid) {
      _log('Not Android platform');
      return null;
    }

    const platform = MethodChannel('com.xiangqi.chinese_chess/engine');

    // 获取 nativeLibraryDir
    String? nativeDir;
    try {
      nativeDir = await platform.invokeMethod<String>('getEngineDir');
    } catch (e) {
      _log('ERROR: MethodChannel getEngineDir failed: $e');
      return null;
    }

    if (nativeDir == null || nativeDir.isEmpty) {
      _log('ERROR: nativeLibraryDir is null/empty');
      return null;
    }
    _log('nativeLibraryDir: $nativeDir');

    // 列出可用的 native 库文件
    try {
      final dir = Directory(nativeDir);
      if (await dir.exists()) {
        final files = await dir.list().toList();
        final names = files.map((f) => f.path.split('/').last).toList();
        _log('Available libs: ${names.join(', ')}');
      }
    } catch (e) {
      _log('Cannot list nativeDir: $e');
    }

    // 检测CPU特征，选择最优引擎变体
    final cpuFeatures = await _getCpuFeatures();
    final cpuArch = await _getCpuArchitecture();
    _log('CPU arch: $cpuArch');
    _log('CPU features: ${cpuFeatures.take(15).join(' ')}');

    // 优先: dotprod变体（现代ARM处理器性能更好）
    if (cpuFeatures.contains('asimddp') || cpuFeatures.contains('dotprod')) {
      final dotprodPath = '$nativeDir/libpikafish_dotprod.so';
      if (await File(dotprodPath).exists()) {
        engineVariant = 'armv8-dotprod';
        _log('Selected: dotprod variant (best for this CPU)');
        return dotprodPath;
      }
    }

    // 回退: 基础armv8变体
    final basicPath = '$nativeDir/libpikafish.so';
    if (await File(basicPath).exists()) {
      engineVariant = 'armv8';
      _log('Selected: basic armv8 variant');
      return basicPath;
    }

    _log('ERROR: No engine binary found in $nativeDir');
    return null;
  }

  /// 从 /proc/cpuinfo 读取CPU特征
  Future<Set<String>> _getCpuFeatures() async {
    try {
      final content = await File('/proc/cpuinfo').readAsString();
      final features = <String>{};
      for (final line in content.split('\n')) {
        final lower = line.toLowerCase();
        if (lower.startsWith('features') || lower.startsWith('flags')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            features.addAll(parts[1].trim().split(RegExp(r'\s+')));
          }
        }
      }
      return features;
    } catch (e) {
      _log('Cannot read /proc/cpuinfo: $e');
      return {};
    }
  }

  /// 获取CPU架构
  Future<String> _getCpuArchitecture() async {
    try {
      final result = await Process.run('uname', ['-m']);
      return result.stdout.toString().trim();
    } catch (e) {
      return 'unknown';
    }
  }

  /// 启动引擎进程
  Future<bool> _startProcess() async {
    if (_enginePath == null) return false;

    try {
      // 获取可写目录作为引擎工作目录
      String? workDir;
      try {
        const platform = MethodChannel('com.xiangqi.chinese_chess/engine');
        workDir = await platform.invokeMethod<String>('getCacheDir');
        _log('Working dir: $workDir');
      } catch (e) {
        _log('getCacheDir failed: $e');
      }

      _log('Starting engine process...');
      _process = await Process.start(
        _enginePath!,
        [],
        mode: ProcessStartMode.normal,
        workingDirectory: workDir,
      );
      _log('Engine PID: ${_process!.pid}');

      // *** 关键：监控进程退出 ***
      _process!.exitCode.then((code) {
        _log('*** ENGINE EXITED with code: $code ***');
        final wasSearching = _isSearching;
        _isReady = false;
        _isSearching = false;
        _process = null;
        // 完成所有挂起的等待
        if (_waitCompleter != null && !_waitCompleter!.isCompleted) {
          _waitCompleter!.complete(false);
        }
        if (wasSearching) {
          onError?.call('引擎异常退出(code=$code)');
        }
        onEngineExit?.call();
      });

      // *** 关键修复：使用 utf8 解码器替代 SystemEncoding ***
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleOutput,
            onError: (e) => _log('stdout error: $e'),
            onDone: () => _log('stdout closed'),
          );

      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _log('STDERR: $line'),
            onError: (e) => _log('stderr error: $e'),
            onDone: () => _log('stderr closed'),
          );

      // *** UCI握手 ***
      _sendCommand('uci');
      await _flush(); // 关键：确保命令到达引擎

      final gotUciOk = await _waitFor('uciok',
          timeout: const Duration(seconds: 10));
      if (!gotUciOk) {
        _log('ERROR: Timeout waiting for uciok');
        dispose();
        return false;
      }

      _isReady = true;
      _log('UCI handshake OK - engine ready');
      return true;
    } catch (e, st) {
      _log('ERROR: startProcess failed: $e\n$st');
      return false;
    }
  }

  /// 处理引擎stdout输出
  void _handleOutput(String line) {
    _log('>> $line');

    // 检查是否有等待中的同步请求
    if (_waitToken != null &&
        _waitCompleter != null &&
        !_waitCompleter!.isCompleted) {
      if (line.trim() == _waitToken) {
        _waitCompleter!.complete(true);
        _waitToken = null;
      }
    }

    // bestmove 处理
    if (line.startsWith('bestmove')) {
      _isSearching = false;
      final parts = line.split(' ');
      final bestMove = parts.length > 1 ? parts[1] : '';
      final ponder =
          parts.length > 3 && parts[2] == 'ponder' ? parts[3] : null;
      onBestMove?.call(bestMove, ponder);
    }
    // 搜索信息
    else if (line.startsWith('info')) {
      onInfo?.call(line);
    }
  }

  /// 等待引擎输出特定token
  Future<bool> _waitFor(String token,
      {Duration timeout = const Duration(seconds: 5)}) async {
    _waitToken = token;
    _waitCompleter = Completer<bool>();

    try {
      return await _waitCompleter!.future.timeout(timeout, onTimeout: () {
        _log('TIMEOUT waiting for: $token');
        _waitToken = null;
        _waitCompleter = null;
        return false;
      });
    } catch (e) {
      _log('ERROR waitFor($token): $e');
      _waitToken = null;
      _waitCompleter = null;
      return false;
    }
  }

  /// 发送命令到引擎stdin
  void _sendCommand(String command) {
    if (_process == null) {
      _log('WARN: process null, cannot send: $command');
      return;
    }
    _log('<< $command');
    try {
      _process!.stdin.writeln(command);
    } catch (e) {
      _log('ERROR: stdin write failed: $e');
    }
  }

  /// *** 关键修复：显式flush stdin缓冲区 ***
  Future<void> _flush() async {
    try {
      await _process?.stdin.flush();
    } catch (e) {
      _log('WARN: stdin flush failed: $e');
    }
  }

  /// 配置最强难度
  Future<void> configureMaxStrength() async {
    final cores = Platform.numberOfProcessors;
    // 线程数：留1个核给系统，最多4个确保稳定
    final threads = (cores > 1 ? cores - 1 : 1).clamp(1, 4);
    _sendCommand('setoption name Threads value $threads');
    // Hash: 64MB，对手机友好
    _sendCommand('setoption name Hash value 64');
    // 最高棋力
    _sendCommand('setoption name Skill Level value 20');
    await _flush();
    _log('Config: Threads=$threads, Hash=64MB, SkillLevel=20');
  }

  /// 开始新游戏（带同步等待确保引擎就绪）
  Future<bool> syncNewGame() async {
    _sendCommand('ucinewgame');
    _sendCommand('isready');
    await _flush();
    final ok =
        await _waitFor('readyok', timeout: const Duration(seconds: 10));
    if (ok) {
      _log('New game: engine ready');
    } else {
      _log('WARN: newGame readyok timeout');
    }
    return ok;
  }

  /// *** 核心修复：设置位置并开始搜索 ***
  /// 使用FEN直接设置局面（比position startpos moves更可靠）
  /// 搜索前先isready同步确认引擎活着
  Future<bool> startSearch(String fen,
      {int depth = 40, int movetime = 10000}) async {
    if (!_isReady || _process == null) {
      _log('WARN: Engine not ready, cannot search');
      onError?.call('引擎未就绪');
      return false;
    }

    // 先同步确认引擎仍在运行
    _sendCommand('isready');
    await _flush();
    final ready =
        await _waitFor('readyok', timeout: const Duration(seconds: 5));
    if (!ready) {
      _log('ERROR: Engine not responding before search');
      onError?.call('引擎无响应');
      return false;
    }

    // 使用FEN设置局面
    _sendCommand('position fen $fen');
    // 开始搜索
    _isSearching = true;
    _sendCommand('go depth $depth movetime $movetime');
    await _flush(); // 确保所有命令到达引擎
    _log('Search started: depth=$depth movetime=${movetime}ms');
    return true;
  }

  /// 停止搜索
  void stop() {
    if (_isSearching) {
      _sendCommand('stop');
      try {
        _process?.stdin.flush();
      } catch (_) {}
    }
  }

  /// 释放引擎
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    if (_process != null) {
      try {
        _sendCommand('quit');
        _process!.stdin.flush();
      } catch (_) {}
      try {
        _process!.kill();
      } catch (_) {}
      _process = null;
    }
    _isReady = false;
    _isSearching = false;
  }
}
