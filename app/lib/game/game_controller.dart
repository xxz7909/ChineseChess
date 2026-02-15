import 'dart:async';
import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/piece.dart';
import '../models/move.dart';
import '../engine/pikafish_engine.dart';

/// 游戏控制器，管理整个游戏流程
class GameController extends ChangeNotifier {
  final Board board = Board();
  final PikafishEngine engine = PikafishEngine();

  /// 玩家颜色（默认执红先行）
  PieceColor playerColor = PieceColor.red;

  /// 当前选中的棋子位置
  int? selectedRow;
  int? selectedCol;

  /// 当前可走的位置
  List<ChessMove> validMoves = [];

  /// 最后一步走法（高亮显示）
  ChessMove? lastMove;

  /// 游戏状态
  GamePhase gamePhase = GamePhase.playing;

  /// AI是否正在思考
  bool isThinking = false;

  /// 引擎是否就绪
  bool engineReady = false;

  /// 状态信息
  String statusMessage = '正在初始化引擎...';

  /// 思考深度信息
  String thinkingInfo = '';

  /// 引擎详细信息（调试用）
  String engineInfo = '';

  /// 搜索超时定时器
  Timer? _searchTimer;

  /// 初始化
  Future<void> init() async {
    // 设置回调（init之前就设置，以便捕获所有输出）
    engine.onBestMove = _onEngineBestMove;
    engine.onInfo = _onEngineInfo;
    engine.onError = _onEngineError;
    engine.onEngineExit = _onEngineExit;

    engineReady = await engine.init();
    if (engineReady) {
      await engine.configureMaxStrength();
      await engine.syncNewGame();

      // *** 关键：立即测试NNUE是否真正加载成功 ***
      final nnueOk = await engine.testNnueLoading();
      if (!nnueOk) {
        // NNUE 加载失败！尝试使用基础引擎变体
        engine.dispose();
        if (!engine.forceBasicVariant) {
          engine.forceBasicVariant = true;
          engineReady = await engine.init();
          if (engineReady) {
            await engine.configureMaxStrength();
            await engine.syncNewGame();
            final retryOk = await engine.testNnueLoading();
            if (retryOk) {
              engineInfo = '引擎: Pikafish (${engine.engineVariant}) [回退]';
              statusMessage = '红方先行';
            } else {
              engineReady = false;
              statusMessage = '引擎NNUE加载失败（两种变体均失败）';
              engineInfo = statusMessage;
            }
          } else {
            statusMessage = '基础引擎加载失败';
            engineInfo = statusMessage;
          }
        } else {
          engineReady = false;
          statusMessage = '引擎NNUE加载失败';
          engineInfo = statusMessage;
        }
      } else {
        engineInfo = '引擎: Pikafish (${engine.engineVariant})';
        statusMessage = '红方先行';
      }
    } else {
      statusMessage = '引擎加载失败';
      engineInfo = '引擎加载失败，请检查日志';
    }
    notifyListeners();
  }

  /// 处理棋盘点击
  void onTap(int row, int col) {
    if (gamePhase != GamePhase.playing) return;
    if (isThinking) return;

    // 如果不是当前玩家的回合
    if (board.currentPlayer != playerColor) return;

    final piece = board.pieceAt(row, col);

    // 如果已选中棋子，尝试移动
    if (selectedRow != null && selectedCol != null) {
      final move = ChessMove(
        fromRow: selectedRow!,
        fromCol: selectedCol!,
        toRow: row,
        toCol: col,
      );

      // 检查是否是合法走法
      if (validMoves.any((m) => m.toRow == row && m.toCol == col)) {
        _makePlayerMove(move);
        return;
      }

      // 如果点击了自己的另一个棋子，重新选择
      if (piece != null && piece.color == playerColor) {
        _selectPiece(row, col);
        return;
      }

      // 其他情况取消选择
      _clearSelection();
      return;
    }

    // 选择己方棋子
    if (piece != null && piece.color == playerColor) {
      _selectPiece(row, col);
    }
  }

  /// 选择棋子
  void _selectPiece(int row, int col) {
    selectedRow = row;
    selectedCol = col;

    // 计算所有合法走法
    validMoves = [];
    for (int tr = 0; tr < 10; tr++) {
      for (int tc = 0; tc < 9; tc++) {
        final move = ChessMove(fromRow: row, fromCol: col, toRow: tr, toCol: tc);
        if (board.isValidMove(move)) {
          validMoves.add(move);
        }
      }
    }

    notifyListeners();
  }

  /// 清除选择
  void _clearSelection() {
    selectedRow = null;
    selectedCol = null;
    validMoves = [];
    notifyListeners();
  }

  /// 玩家走棋
  void _makePlayerMove(ChessMove move) {
    final success = board.makeMove(move);
    if (!success) return;

    lastMove = move;
    _clearSelection();

    // 检查游戏状态
    gamePhase = board.checkGamePhase();
    if (gamePhase != GamePhase.playing) {
      _onGameEnd();
      notifyListeners();
      return;
    }

    // 检查对方是否无子可走（被将死）
    final opponentMoves = board.generateAllMoves(board.currentPlayer);
    if (opponentMoves.isEmpty) {
      gamePhase = board.currentPlayer == PieceColor.red
          ? GamePhase.blackWin
          : GamePhase.redWin;
      _onGameEnd();
      notifyListeners();
      return;
    }

    statusMessage = '引擎思考中...';
    notifyListeners();

    // 让AI思考（异步）
    _startAISearch();
  }

  /// 异步启动AI搜索
  Future<void> _startAISearch() async {
    if (!engineReady) {
      statusMessage = '引擎未就绪';
      notifyListeners();
      return;
    }

    isThinking = true;
    thinkingInfo = '';
    notifyListeners();

    // *** 关键：使用FEN设置局面（比move history更可靠）***
    final fen = board.toFen();
    final ok = await engine.startSearch(fen, depth: 40, movetime: 10000);

    if (!ok) {
      // 引擎搜索启动失败
      isThinking = false;
      statusMessage = '引擎搜索失败，请重试';
      notifyListeners();
      return;
    }

    // 设置搜索超时（30秒安全网）
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(seconds: 30), () {
      if (isThinking) {
        engine.stop();
        // 再等2秒看引擎是否响应stop
        Future.delayed(const Duration(seconds: 2), () {
          if (isThinking) {
            isThinking = false;
            statusMessage = '引擎超时，请重试';
            notifyListeners();
          }
        });
      }
    });
  }

  /// 引擎返回最佳走法
  void _onEngineBestMove(String bestMove, String? ponder) {
    _searchTimer?.cancel();

    if (bestMove.isEmpty || bestMove == '(none)') {
      // 引擎认输
      gamePhase = playerColor == PieceColor.red
          ? GamePhase.redWin
          : GamePhase.blackWin;
      _onGameEnd();
      isThinking = false;
      notifyListeners();
      return;
    }

    final move = ChessMove.fromUci(bestMove);
    final success = board.makeMoveForced(move);
    if (success) {
      lastMove = move;
    }

    // 检查游戏状态
    gamePhase = board.checkGamePhase();
    if (gamePhase != GamePhase.playing) {
      _onGameEnd();
    } else {
      // 检查玩家是否有合法走法
      final playerMoves = board.generateAllMoves(playerColor);
      if (playerMoves.isEmpty) {
        gamePhase = playerColor == PieceColor.red
            ? GamePhase.blackWin
            : GamePhase.redWin;
        _onGameEnd();
      } else {
        statusMessage = _isPlayerInCheck() ? '将军！请应将' : '轮到你走';
      }
    }

    isThinking = false;
    thinkingInfo = '';
    notifyListeners();
  }

  /// 引擎搜索信息
  void _onEngineInfo(String info) {
    // 解析 depth 和 score
    final depthMatch = RegExp(r'depth (\d+)').firstMatch(info);
    final scoreMatch = RegExp(r'score cp (-?\d+)').firstMatch(info);
    final mateMatch = RegExp(r'score mate (-?\d+)').firstMatch(info);

    if (depthMatch != null) {
      final depth = depthMatch.group(1);
      String scoreStr = '';
      if (mateMatch != null) {
        final mate = int.parse(mateMatch.group(1)!);
        scoreStr = mate > 0 ? '将杀 $mate步' : '被杀 ${-mate}步';
      } else if (scoreMatch != null) {
        final score = int.parse(scoreMatch.group(1)!);
        scoreStr = '评估: ${(score / 100).toStringAsFixed(1)}';
      }
      thinkingInfo = '深度: $depth $scoreStr';
      notifyListeners();
    }
  }

  /// 引擎错误处理
  void _onEngineError(String error) {
    isThinking = false;
    _searchTimer?.cancel();
    statusMessage = error;
    notifyListeners();
  }

  /// 引擎意外退出
  void _onEngineExit() {
    engineReady = false;
    isThinking = false;
    _searchTimer?.cancel();
    // 尝试重启引擎
    _tryRestartEngine();
  }

  /// 尝试重启引擎
  Future<void> _tryRestartEngine() async {
    statusMessage = '引擎异常退出，正在重启...';
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));
    engine.dispose();

    engineReady = await engine.init();
    if (engineReady) {
      await engine.configureMaxStrength();
      await engine.syncNewGame();
      final nnueOk = await engine.testNnueLoading();
      if (nnueOk) {
        statusMessage = '引擎已重启，轮到你走';
        engineInfo = '引擎: Pikafish (${engine.engineVariant}) [已重启]';
      } else {
        engineReady = false;
        statusMessage = '引擎NNUE加载失败（重启后仍然有问题）';
        engineInfo = statusMessage;
      }
    } else {
      statusMessage = '引擎重启失败';
      engineInfo = '引擎重启失败';
    }
    notifyListeners();
  }

  /// 检查玩家是否被将军
  bool _isPlayerInCheck() {
    return board.isKingInCheck(playerColor);
  }

  /// 游戏结束处理
  void _onGameEnd() {
    switch (gamePhase) {
      case GamePhase.redWin:
        statusMessage = '红方获胜！';
        break;
      case GamePhase.blackWin:
        statusMessage = '黑方获胜！';
        break;
      case GamePhase.draw:
        statusMessage = '和棋！';
        break;
      default:
        break;
    }
  }

  /// 悔棋（撤销自己和AI的最后一步）
  void undoMove() {
    if (isThinking) return;
    if (board.moveHistory.length < 2) return;

    // 撤销AI的走法
    board.undoMove();
    // 撤销玩家的走法
    board.undoMove();

    lastMove = null;
    if (board.moveHistory.isNotEmpty) {
      lastMove = ChessMove.fromUci(board.moveHistory.last);
    }

    gamePhase = GamePhase.playing;
    statusMessage = '轮到你走';
    _clearSelection();
    notifyListeners();
  }

  /// 新游戏
  Future<void> newGame() async {
    if (isThinking) {
      engine.stop();
      _searchTimer?.cancel();
    }
    board.reset();
    selectedRow = null;
    selectedCol = null;
    validMoves = [];
    lastMove = null;
    gamePhase = GamePhase.playing;
    isThinking = false;
    thinkingInfo = '';
    statusMessage = '红方先行';

    if (engineReady) {
      await engine.syncNewGame();
    }

    notifyListeners();
  }

  /// 切换先后手
  Future<void> switchSide() async {
    playerColor =
        playerColor == PieceColor.red ? PieceColor.black : PieceColor.red;
    await newGame();

    // 如果AI先走（玩家执黑）
    if (playerColor == PieceColor.black && engineReady) {
      statusMessage = '引擎思考中...';
      notifyListeners();
      _startAISearch();
    }
  }

  /// 获取引擎调试日志
  List<String> getEngineDebugLog() {
    return engine.debugLog;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    engine.dispose();
    super.dispose();
  }
}
