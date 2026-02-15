import 'piece.dart';
import 'move.dart';

/// 游戏阶段
enum GamePhase { playing, redWin, blackWin, draw }

/// 棋盘逻辑，管理棋子位置和走法规则
class Board {
  /// 10行9列棋盘，board[row][col]存棋子，null表示空
  List<List<ChessPiece?>> grid =
      List.generate(10, (_) => List.filled(9, null));

  /// 当前走棋方
  PieceColor currentPlayer = PieceColor.red;

  /// 走法历史 (UCI格式)
  List<String> moveHistory = [];

  /// 被吃掉的棋子历史（用于悔棋）
  List<ChessPiece?> capturedHistory = [];

  Board() {
    _initBoard();
  }

  /// 初始化棋盘
  void _initBoard() {
    grid = List.generate(10, (_) => List.filled(9, null));
    moveHistory.clear();
    capturedHistory.clear();
    currentPlayer = PieceColor.red;

    // 红方 (底部, row 0-4)
    // 车
    _place(PieceType.rook, PieceColor.red, 0, 0);
    _place(PieceType.rook, PieceColor.red, 0, 8);
    // 马
    _place(PieceType.knight, PieceColor.red, 0, 1);
    _place(PieceType.knight, PieceColor.red, 0, 7);
    // 相
    _place(PieceType.bishop, PieceColor.red, 0, 2);
    _place(PieceType.bishop, PieceColor.red, 0, 6);
    // 仕
    _place(PieceType.advisor, PieceColor.red, 0, 3);
    _place(PieceType.advisor, PieceColor.red, 0, 5);
    // 帅
    _place(PieceType.king, PieceColor.red, 0, 4);
    // 炮
    _place(PieceType.cannon, PieceColor.red, 2, 1);
    _place(PieceType.cannon, PieceColor.red, 2, 7);
    // 兵
    for (int c = 0; c < 9; c += 2) {
      _place(PieceType.pawn, PieceColor.red, 3, c);
    }

    // 黑方 (顶部, row 5-9)
    // 车
    _place(PieceType.rook, PieceColor.black, 9, 0);
    _place(PieceType.rook, PieceColor.black, 9, 8);
    // 马
    _place(PieceType.knight, PieceColor.black, 9, 1);
    _place(PieceType.knight, PieceColor.black, 9, 7);
    // 象
    _place(PieceType.bishop, PieceColor.black, 9, 2);
    _place(PieceType.bishop, PieceColor.black, 9, 6);
    // 士
    _place(PieceType.advisor, PieceColor.black, 9, 3);
    _place(PieceType.advisor, PieceColor.black, 9, 5);
    // 将
    _place(PieceType.king, PieceColor.black, 9, 4);
    // 砲
    _place(PieceType.cannon, PieceColor.black, 7, 1);
    _place(PieceType.cannon, PieceColor.black, 7, 7);
    // 卒
    for (int c = 0; c < 9; c += 2) {
      _place(PieceType.pawn, PieceColor.black, 6, c);
    }
  }

  void _place(PieceType type, PieceColor color, int row, int col) {
    grid[row][col] = ChessPiece(type: type, color: color, row: row, col: col);
  }

  /// 获取指定位置的棋子
  ChessPiece? pieceAt(int row, int col) {
    if (row < 0 || row > 9 || col < 0 || col > 8) return null;
    return grid[row][col];
  }

  /// 获取所有某颜色的棋子
  List<ChessPiece> getPieces(PieceColor color) {
    List<ChessPiece> pieces = [];
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 9; c++) {
        if (grid[r][c] != null && grid[r][c]!.color == color) {
          pieces.add(grid[r][c]!);
        }
      }
    }
    return pieces;
  }

  /// 执行走法
  bool makeMove(ChessMove move) {
    final piece = grid[move.fromRow][move.fromCol];
    if (piece == null) return false;
    if (piece.color != currentPlayer) return false;
    if (!isValidMove(move)) return false;

    final captured = grid[move.toRow][move.toCol];
    capturedHistory.add(captured);

    // 移动棋子
    grid[move.toRow][move.toCol] = piece;
    grid[move.fromRow][move.fromCol] = null;
    piece.row = move.toRow;
    piece.col = move.toCol;

    moveHistory.add(move.toUci());

    // 切换走棋方
    currentPlayer =
        currentPlayer == PieceColor.red ? PieceColor.black : PieceColor.red;

    return true;
  }

  /// 强制执行走法（引擎返回的走法，跳过部分验证）
  bool makeMoveForced(ChessMove move) {
    final piece = grid[move.fromRow][move.fromCol];
    if (piece == null) return false;

    final captured = grid[move.toRow][move.toCol];
    capturedHistory.add(captured);

    grid[move.toRow][move.toCol] = piece;
    grid[move.fromRow][move.fromCol] = null;
    piece.row = move.toRow;
    piece.col = move.toCol;

    moveHistory.add(move.toUci());
    currentPlayer =
        currentPlayer == PieceColor.red ? PieceColor.black : PieceColor.red;

    return true;
  }

  /// 悔棋
  bool undoMove() {
    if (moveHistory.isEmpty) return false;

    final lastUci = moveHistory.removeLast();
    final lastMove = ChessMove.fromUci(lastUci);
    final captured = capturedHistory.removeLast();

    final piece = grid[lastMove.toRow][lastMove.toCol];
    if (piece == null) return false;

    // 恢复棋子位置
    grid[lastMove.fromRow][lastMove.fromCol] = piece;
    piece.row = lastMove.fromRow;
    piece.col = lastMove.fromCol;

    // 恢复被吃的棋子
    grid[lastMove.toRow][lastMove.toCol] = captured;

    // 切换回上一方
    currentPlayer =
        currentPlayer == PieceColor.red ? PieceColor.black : PieceColor.red;

    return true;
  }

  /// 重置棋盘
  void reset() {
    _initBoard();
  }

  /// 生成FEN字符串
  String toFen() {
    StringBuffer fen = StringBuffer();
    // FEN从row 9（黑方底线）到 row 0（红方底线）
    for (int r = 9; r >= 0; r--) {
      int empty = 0;
      for (int c = 0; c < 9; c++) {
        if (grid[r][c] == null) {
          empty++;
        } else {
          if (empty > 0) {
            fen.write(empty);
            empty = 0;
          }
          fen.write(grid[r][c]!.fenChar);
        }
      }
      if (empty > 0) fen.write(empty);
      if (r > 0) fen.write('/');
    }
    fen.write(currentPlayer == PieceColor.red ? ' w - - 0 1' : ' b - - 0 1');
    return fen.toString();
  }

  /// 检查游戏是否结束
  GamePhase checkGamePhase() {
    bool redKingAlive = false;
    bool blackKingAlive = false;
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 9; c++) {
        final p = grid[r][c];
        if (p != null && p.type == PieceType.king) {
          if (p.color == PieceColor.red) redKingAlive = true;
          if (p.color == PieceColor.black) blackKingAlive = true;
        }
      }
    }
    if (!redKingAlive) return GamePhase.blackWin;
    if (!blackKingAlive) return GamePhase.redWin;
    return GamePhase.playing;
  }

  // ===================== 走法验证 =====================

  /// 验证走法是否合法
  bool isValidMove(ChessMove move) {
    final piece = grid[move.fromRow][move.fromCol];
    if (piece == null) return false;

    // 不能吃自己的子
    final target = grid[move.toRow][move.toCol];
    if (target != null && target.color == piece.color) return false;

    // 目标位置要在棋盘内
    if (move.toRow < 0 || move.toRow > 9) return false;
    if (move.toCol < 0 || move.toCol > 8) return false;

    bool basicValid = false;
    switch (piece.type) {
      case PieceType.king:
        basicValid = _isValidKingMove(piece, move);
        break;
      case PieceType.advisor:
        basicValid = _isValidAdvisorMove(piece, move);
        break;
      case PieceType.bishop:
        basicValid = _isValidBishopMove(piece, move);
        break;
      case PieceType.knight:
        basicValid = _isValidKnightMove(piece, move);
        break;
      case PieceType.rook:
        basicValid = _isValidRookMove(piece, move);
        break;
      case PieceType.cannon:
        basicValid = _isValidCannonMove(piece, move);
        break;
      case PieceType.pawn:
        basicValid = _isValidPawnMove(piece, move);
        break;
    }

    if (!basicValid) return false;

    // 检查走完后是否被将军（自杀走法）
    // 临时走法
    final captured = grid[move.toRow][move.toCol];
    grid[move.toRow][move.toCol] = piece;
    grid[move.fromRow][move.fromCol] = null;
    final origRow = piece.row;
    final origCol = piece.col;
    piece.row = move.toRow;
    piece.col = move.toCol;

    final inCheck = isKingInCheck(piece.color);
    final flyingGeneral = _isFlyingGeneral();

    // 恢复
    grid[move.fromRow][move.fromCol] = piece;
    grid[move.toRow][move.toCol] = captured;
    piece.row = origRow;
    piece.col = origCol;

    return !inCheck && !flyingGeneral;
  }

  /// 帅/将走法
  bool _isValidKingMove(ChessPiece piece, ChessMove move) {
    final dr = (move.toRow - move.fromRow).abs();
    final dc = (move.toCol - move.fromCol).abs();

    // 只能走一步，上下左右
    if (!((dr == 1 && dc == 0) || (dr == 0 && dc == 1))) return false;

    // 帅在宫内 (row 0-2, col 3-5)，将在宫内 (row 7-9, col 3-5)
    if (piece.color == PieceColor.red) {
      return move.toRow >= 0 && move.toRow <= 2 && move.toCol >= 3 && move.toCol <= 5;
    } else {
      return move.toRow >= 7 && move.toRow <= 9 && move.toCol >= 3 && move.toCol <= 5;
    }
  }

  /// 仕/士走法
  bool _isValidAdvisorMove(ChessPiece piece, ChessMove move) {
    final dr = (move.toRow - move.fromRow).abs();
    final dc = (move.toCol - move.fromCol).abs();

    // 斜走一步
    if (dr != 1 || dc != 1) return false;

    // 在宫内
    if (piece.color == PieceColor.red) {
      return move.toRow >= 0 && move.toRow <= 2 && move.toCol >= 3 && move.toCol <= 5;
    } else {
      return move.toRow >= 7 && move.toRow <= 9 && move.toCol >= 3 && move.toCol <= 5;
    }
  }

  /// 相/象走法
  bool _isValidBishopMove(ChessPiece piece, ChessMove move) {
    final dr = (move.toRow - move.fromRow).abs();
    final dc = (move.toCol - move.fromCol).abs();

    // 走田字
    if (dr != 2 || dc != 2) return false;

    // 不能过河
    if (piece.color == PieceColor.red) {
      if (move.toRow > 4) return false;
    } else {
      if (move.toRow < 5) return false;
    }

    // 象眼不能被堵
    final eyeRow = (move.fromRow + move.toRow) ~/ 2;
    final eyeCol = (move.fromCol + move.toCol) ~/ 2;
    if (grid[eyeRow][eyeCol] != null) return false;

    return true;
  }

  /// 马走法
  bool _isValidKnightMove(ChessPiece piece, ChessMove move) {
    final dr = (move.toRow - move.fromRow).abs();
    final dc = (move.toCol - move.fromCol).abs();

    // 走日字
    if (!((dr == 2 && dc == 1) || (dr == 1 && dc == 2))) return false;

    // 蹩脚检查
    if (dr == 2) {
      // 竖向走2格，检查竖向中间点
      final legRow = move.fromRow + (move.toRow > move.fromRow ? 1 : -1);
      if (grid[legRow][move.fromCol] != null) return false;
    } else {
      // 横向走2格，检查横向中间点
      final legCol = move.fromCol + (move.toCol > move.fromCol ? 1 : -1);
      if (grid[move.fromRow][legCol] != null) return false;
    }

    return true;
  }

  /// 车走法
  bool _isValidRookMove(ChessPiece piece, ChessMove move) {
    // 直线移动
    if (move.fromRow != move.toRow && move.fromCol != move.toCol) return false;

    // 路径上不能有棋子
    return _isPathClear(move.fromRow, move.fromCol, move.toRow, move.toCol);
  }

  /// 炮走法
  bool _isValidCannonMove(ChessPiece piece, ChessMove move) {
    // 直线移动
    if (move.fromRow != move.toRow && move.fromCol != move.toCol) return false;

    final target = grid[move.toRow][move.toCol];
    final count = _countBetween(move.fromRow, move.fromCol, move.toRow, move.toCol);

    if (target == null) {
      // 不吃子，路径要空
      return count == 0;
    } else {
      // 吃子，中间恰好一个棋子（炮架）
      return count == 1;
    }
  }

  /// 兵/卒走法
  bool _isValidPawnMove(ChessPiece piece, ChessMove move) {
    final dr = move.toRow - move.fromRow;
    final dc = (move.toCol - move.fromCol).abs();

    if (piece.color == PieceColor.red) {
      // 红兵向上走（row增大）
      if (piece.row <= 4) {
        // 未过河，只能前进
        return dr == 1 && dc == 0;
      } else {
        // 已过河，可以前进或横走
        if (dr == 1 && dc == 0) return true;
        if (dr == 0 && dc == 1) return true;
        return false;
      }
    } else {
      // 黑卒向下走（row减小）
      if (piece.row >= 5) {
        // 未过河，只能前进
        return dr == -1 && dc == 0;
      } else {
        // 已过河
        if (dr == -1 && dc == 0) return true;
        if (dr == 0 && dc == 1) return true;
        return false;
      }
    }
  }

  /// 检查路径是否畅通（不包括起点和终点）
  bool _isPathClear(int fromRow, int fromCol, int toRow, int toCol) {
    return _countBetween(fromRow, fromCol, toRow, toCol) == 0;
  }

  /// 统计两点之间的棋子数（不包括起点和终点）
  int _countBetween(int fromRow, int fromCol, int toRow, int toCol) {
    int count = 0;
    if (fromRow == toRow) {
      final minC = fromCol < toCol ? fromCol : toCol;
      final maxC = fromCol > toCol ? fromCol : toCol;
      for (int c = minC + 1; c < maxC; c++) {
        if (grid[fromRow][c] != null) count++;
      }
    } else if (fromCol == toCol) {
      final minR = fromRow < toRow ? fromRow : toRow;
      final maxR = fromRow > toRow ? fromRow : toRow;
      for (int r = minR + 1; r < maxR; r++) {
        if (grid[r][fromCol] != null) count++;
      }
    }
    return count;
  }

  /// 检查指定颜色的帅/将是否被将军
  bool isKingInCheck(PieceColor color) {
    // 找到帅/将位置
    int kingRow = -1, kingCol = -1;
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 9; c++) {
        final p = grid[r][c];
        if (p != null && p.type == PieceType.king && p.color == color) {
          kingRow = r;
          kingCol = c;
        }
      }
    }
    if (kingRow == -1) return true; // 帅没了，算被将

    // 检查对方所有棋子是否能吃到帅
    final opponent = color == PieceColor.red ? PieceColor.black : PieceColor.red;
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 9; c++) {
        final p = grid[r][c];
        if (p != null && p.color == opponent) {
          final attackMove = ChessMove(
              fromRow: r, fromCol: c, toRow: kingRow, toCol: kingCol);
          bool canAttack = false;
          switch (p.type) {
            case PieceType.rook:
              canAttack = _isValidRookMove(p, attackMove);
              break;
            case PieceType.cannon:
              canAttack = _isValidCannonMove(p, attackMove);
              break;
            case PieceType.knight:
              canAttack = _isValidKnightMove(p, attackMove);
              break;
            case PieceType.pawn:
              canAttack = _isValidPawnMove(p, attackMove);
              break;
            case PieceType.king:
              canAttack = _isValidKingMove(p, attackMove);
              break;
            case PieceType.advisor:
              canAttack = _isValidAdvisorMove(p, attackMove);
              break;
            case PieceType.bishop:
              canAttack = _isValidBishopMove(p, attackMove);
              break;
          }
          if (canAttack) return true;
        }
      }
    }
    return false;
  }

  /// 检查将帅是否对面（飞将规则）
  bool _isFlyingGeneral() {
    int redKingRow = -1, redKingCol = -1;
    int blackKingRow = -1, blackKingCol = -1;

    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 9; c++) {
        final p = grid[r][c];
        if (p != null && p.type == PieceType.king) {
          if (p.color == PieceColor.red) {
            redKingRow = r;
            redKingCol = c;
          } else {
            blackKingRow = r;
            blackKingCol = c;
          }
        }
      }
    }

    if (redKingCol != blackKingCol) return false;

    // 检查两将之间是否有棋子
    for (int r = redKingRow + 1; r < blackKingRow; r++) {
      if (grid[r][redKingCol] != null) return false;
    }
    return true; // 对面且中间无子
  }

  /// 生成某颜色所有合法走法
  List<ChessMove> generateAllMoves(PieceColor color) {
    List<ChessMove> moves = [];
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 9; c++) {
        final p = grid[r][c];
        if (p != null && p.color == color) {
          for (int tr = 0; tr < 10; tr++) {
            for (int tc = 0; tc < 9; tc++) {
              final m = ChessMove(fromRow: r, fromCol: c, toRow: tr, toCol: tc);
              if (isValidMove(m)) {
                moves.add(m);
              }
            }
          }
        }
      }
    }
    return moves;
  }
}
