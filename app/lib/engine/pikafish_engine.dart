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
  String? _nnuePath; // NNUE文件的绝对路径
  String? _debugLogPath; // 引擎调试日志路径
  String? _cacheDir; // 缓存目录路径

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

  /// 强制使用基础引擎变体（当 dotprod 变体失败时）
  bool forceBasicVariant = false;

  /// 抑制回调（用于 NNUE 测试搜索期间）
  bool _suppressCallbacks = false;

  /// _waitFor 使用前缀匹配（而非精确匹配）
  bool _waitPrefix = false;

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
          _nnuePath = nnuePath;

          // *** 从Dart侧验证文件可读且完整 ***
          try {
            final raf = await nnueFile.open(mode: FileMode.read);
            final header = await raf.read(16);
            await raf.close();
            final headerHex = header.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
            _log('NNUE header (16 bytes): $headerHex');

            // 验证 NNUE raw header:
            // 前4字节 = Version (0x7AF32F20 little-endian = 20 2F F3 7A)
            // 后4字节 = Hash (0x6E24D34A little-endian = 4A D3 24 6E)
            if (header.length >= 8 &&
                header[0] == 0x20 && header[1] == 0x2F &&
                header[2] == 0xF3 && header[3] == 0x7A &&
                header[4] == 0x4A && header[5] == 0xD3 &&
                header[6] == 0x24 && header[7] == 0x6E) {
              _log('NNUE raw header verified (version=0x7AF32F20, hash=0x6E24D34A)');
            } else if (header.length >= 4 &&
                header[0] == 0x28 && header[1] == 0xB5 &&
                header[2] == 0x2F && header[3] == 0xFD) {
              _log('WARNING: NNUE file is zstd compressed! Engine may not support zstd.');
            } else {
              _log('ERROR: NNUE file has unknown header format!');
              return false;
            }
          } catch (e) {
            _log('ERROR: Cannot read NNUE file from Dart: $e');
            return false;
          }

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
    _log('CPU features: ${cpuFeatures.join(' ')}');

    // 优先: dotprod变体（现代ARM处理器性能更好）
    if (!forceBasicVariant &&
        (cpuFeatures.contains('asimddp') || cpuFeatures.contains('dotprod'))) {
      final dotprodPath = '$nativeDir/libpikafish_dotprod.so';
      if (await File(dotprodPath).exists()) {
        engineVariant = 'armv8-dotprod';
        _log('Selected: dotprod variant (best for this CPU)');
        return dotprodPath;
      }
    } else if (forceBasicVariant) {
      _log('Dotprod variant skipped (forceBasicVariant=true)');
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
        _cacheDir = workDir;
        _log('Working dir: $workDir');
      } catch (e) {
        _log('getCacheDir failed: $e');
      }

      _log('Starting engine process...');

      // 验证 NNUE 文件在工作目录中存在
      if (workDir != null && _nnuePath != null) {
        final nnueInWorkDir = File('$workDir/pikafish.nnue');
        final existsInWD = await nnueInWorkDir.exists();
        _log('NNUE in workDir ($workDir): ${existsInWD ? "EXISTS" : "MISSING"}');
        if (existsInWD) {
          _log('  size: ${await nnueInWorkDir.length()} bytes');
        }
      }

      // *** 关键诊断：测试子进程能否读取 NNUE 文件 ***
      // 引擎也是子进程，如果子进程无法读取，引擎也无法读取
      if (_nnuePath != null) {
        await _testSubprocessFileAccess(_nnuePath!, workDir);
      }

      // *** 关键修复：通过 shell cd + exec 保证 CWD ***
      // Process.start 的 workingDirectory 在某些 Android 设备上不生效
      // 使用 sh -c 'cd <dir> && exec <engine>' 保证 CWD 正确设置
      if (workDir != null) {
        _process = await Process.start(
          '/system/bin/sh',
          ['-c', 'cd "$workDir" && exec "$_enginePath"'],
          mode: ProcessStartMode.normal,
        );
      } else {
        _process = await Process.start(
          _enginePath!,
          [],
          mode: ProcessStartMode.normal,
        );
      }
      _log('Engine PID: ${_process!.pid}');

      // *** 关键：监控进程退出 ***
      _process!.exitCode.then((code) {
        _log('*** ENGINE EXITED with code: $code ***');
        // 读取引擎调试日志（fire-and-forget）
        _readEngineDebugLog();
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
      final trimmed = line.trim();
      final match = _waitPrefix
          ? trimmed.startsWith(_waitToken!)
          : trimmed == _waitToken;
      if (match) {
        _waitCompleter!.complete(true);
        _waitToken = null;
        _waitPrefix = false;
      }
    }

    // bestmove 处理
    if (line.startsWith('bestmove')) {
      _isSearching = false;
      if (!_suppressCallbacks) {
        final parts = line.split(' ');
        final bestMove = parts.length > 1 ? parts[1] : '';
        final ponder =
            parts.length > 3 && parts[2] == 'ponder' ? parts[3] : null;
        onBestMove?.call(bestMove, ponder);
      }
    }
    // 搜索信息
    else if (line.startsWith('info')) {
      if (!_suppressCallbacks) {
        onInfo?.call(line);
      }
    }
  }

  /// 等待引擎输出特定token
  /// prefix=true 时使用 startsWith 匹配（如等待 'bestmove' 前缀）
  Future<bool> _waitFor(String token,
      {Duration timeout = const Duration(seconds: 5),
       bool prefix = false}) async {
    _waitToken = token;
    _waitPrefix = prefix;
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

  /// 配置引擎参数
  Future<void> configureMaxStrength() async {
    // 启用引擎调试日志文件（记录所有 UCI 通信和内部消息）
    if (_cacheDir != null) {
      _debugLogPath = '$_cacheDir/engine_debug.log';
      try {
        final oldLog = File(_debugLogPath!);
        if (await oldLog.exists()) await oldLog.delete();
      } catch (_) {}
      _sendCommand('setoption name Debug Log File value $_debugLogPath');
      await _flush();
      _log('Debug Log File: $_debugLogPath');
    }

    // *** 策略：依赖 CWD 自动加载（shell cd 已保证 CWD = cache dir）***
    // 引擎构造函数会自动从 CWD 加载 "pikafish.nnue"
    // EvalFile 默认值就是 "pikafish.nnue"，verify() 会对比这个值
    // 如果构造函数已成功加载，evalFile.current = "pikafish.nnue"，verify 通过
    //
    // 同时也尝试绝对路径作为后备
    if (_nnuePath != null) {
      _log('NNUE at: $_nnuePath (engine should auto-load via CWD)');
      // 先 isready 确认引擎初始化完成（构造函数中会尝试加载 NNUE）
      _sendCommand('isready');
      await _flush();
      final initReady = await _waitFor('readyok',
          timeout: const Duration(seconds: 30));
      if (initReady) {
        _log('Engine init readyok (NNUE may have loaded from CWD)');
      } else {
        _log('WARNING: Engine not responding after init');
      }
    }

    final cores = Platform.numberOfProcessors;
    // 线程数：留1个核给系统，最多4个确保稳定
    final threads = (cores > 1 ? cores - 1 : 1).clamp(1, 4);
    _sendCommand('setoption name Threads value $threads');
    // Hash: 64MB，对手机友好
    _sendCommand('setoption name Hash value 64');
    // 注意：Pikafish没有"Skill Level"选项，不要发送
    await _flush();
    _log('Config: Threads=$threads, Hash=64MB');
  }

  /// *** 关键：初始化后立即测试 NNUE 是否真正加载成功 ***
  /// 发送 depth 1 搜索，如果 NNUE 未加载，引擎会在 verify() 时 exit(1)
  /// 必须在 syncNewGame() 之后调用
  Future<bool> testNnueLoading() async {
    if (!_isReady || _process == null) {
      _log('Cannot test NNUE: engine not ready');
      return false;
    }

    _log('=== NNUE Loading Test: depth 1 search ===');
    _suppressCallbacks = true;

    try {
      // 用初始局面测试
      _sendCommand('position startpos');
      _isSearching = true;
      _sendCommand('go depth 1 movetime 3000');
      await _flush();

      // 等待 bestmove（表示 NNUE 加载成功并能正常搜索）
      final gotBestMove = await _waitFor('bestmove',
          timeout: const Duration(seconds: 10), prefix: true);

      _isSearching = false;

      if (gotBestMove) {
        _log('=== NNUE TEST PASSED: Engine can search ===');
        // 重置引擎状态
        _sendCommand('ucinewgame');
        _sendCommand('isready');
        await _flush();
        await _waitFor('readyok', timeout: const Duration(seconds: 5));
        return true;
      } else {
        _log('=== NNUE TEST FAILED: No bestmove (NNUE not loaded or engine crashed) ===');
        return false;
      }
    } finally {
      _suppressCallbacks = false;
    }
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

  /// 测试子进程能否读取文件（与引擎子进程具有相同的权限上下文）
  Future<void> _testSubprocessFileAccess(String filePath, String? workDir) async {
    _log('--- Subprocess file access test ---');
    // Test 1: ls -la
    try {
      final ls = await Process.run('ls', ['-la', filePath]);
      _log('ls: ${ls.stdout.toString().trim()}');
      if (ls.exitCode != 0) _log('ls stderr: ${ls.stderr}');
    } catch (e) {
      _log('ls failed: $e');
    }
    // Test 2: wc -c（验证文件可完整读取）
    try {
      final wc = await Process.run('wc', ['-c', filePath]);
      _log('wc -c: ${wc.stdout.toString().trim()}');
      if (wc.exitCode != 0) _log('wc stderr: ${wc.stderr}');
    } catch (e) {
      _log('wc failed: $e');
    }
    // Test 3: sha256sum（验证文件完整性）
    try {
      final sha = await Process.run('sha256sum', [filePath]);
      _log('sha256sum: ${sha.stdout.toString().trim()}');
      if (sha.exitCode != 0) _log('sha256sum stderr: ${sha.stderr}');
    } catch (e) {
      _log('sha256sum N/A: $e');
    }
    // Test 4: od 前16字节（从子进程验证文件头内容）
    try {
      final od = await Process.run('od', ['-A', 'x', '-t', 'x1', '-N', '16', filePath]);
      _log('od header: ${od.stdout.toString().trim()}');
    } catch (e) {
      _log('od failed: $e');
    }
    // Test 5: 从工作目录测试相对路径访问
    if (workDir != null) {
      try {
        final ls2 = await Process.run('ls', ['-la', 'pikafish.nnue'],
            workingDirectory: workDir);
        _log('ls (CWD relative): ${ls2.stdout.toString().trim()}');
        if (ls2.exitCode != 0) _log('ls relative stderr: ${ls2.stderr}');
      } catch (e) {
        _log('ls relative failed: $e');
      }
    }
    _log('--- End subprocess test ---');
  }

  /// 读取引擎调试日志（引擎崩溃后调用）
  Future<void> _readEngineDebugLog() async {
    if (_debugLogPath == null) return;
    try {
      final f = File(_debugLogPath!);
      if (await f.exists()) {
        final content = await f.readAsString();
        final lines = content.split('\n');
        _log('=== ENGINE DEBUG LOG (${lines.length} lines) ===');
        for (final line in lines.take(100)) {
          _log('DBG: $line');
        }
        _log('=== END ENGINE DEBUG LOG ===');
      } else {
        _log('Engine debug log not created at: $_debugLogPath');
      }
    } catch (e) {
      _log('Cannot read engine debug log: $e');
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
