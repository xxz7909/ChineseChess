import 'package:flutter/material.dart';
import '../models/piece.dart';
import '../models/move.dart';

/// 棋盘绘制器
class ChessBoardPainter extends CustomPainter {
  final List<List<ChessPiece?>> grid;
  final int? selectedRow;
  final int? selectedCol;
  final List<ChessMove> validMoves;
  final ChessMove? lastMove;
  final bool flipBoard; // 是否翻转棋盘

  ChessBoardPainter({
    required this.grid,
    this.selectedRow,
    this.selectedCol,
    this.validMoves = const [],
    this.lastMove,
    this.flipBoard = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / 10;
    final cellHeight = size.height / 11;
    final offsetX = cellWidth; // 左侧留白
    final offsetY = cellHeight * 0.5; // 顶部留白

    final gridWidth = cellWidth * 8;
    final gridHeight = cellHeight * 9;

    // 绘制背景
    final bgPaint = Paint()..color = const Color(0xFFF5D6A8);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 绘制棋盘线
    final linePaint = Paint()
      ..color = const Color(0xFF5C3A1E)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 横线 (10条)
    for (int r = 0; r < 10; r++) {
      final y = offsetY + r * cellHeight;
      canvas.drawLine(Offset(offsetX, y), Offset(offsetX + gridWidth, y), linePaint);
    }

    // 竖线
    for (int c = 0; c < 9; c++) {
      final x = offsetX + c * cellWidth;
      if (c == 0 || c == 8) {
        // 边线贯穿全局
        canvas.drawLine(
            Offset(x, offsetY), Offset(x, offsetY + gridHeight), linePaint);
      } else {
        // 中间线在河界断开
        canvas.drawLine(
            Offset(x, offsetY), Offset(x, offsetY + 4 * cellHeight), linePaint);
        canvas.drawLine(Offset(x, offsetY + 5 * cellHeight),
            Offset(x, offsetY + gridHeight), linePaint);
      }
    }

    // 九宫格斜线
    _drawPalace(canvas, linePaint, offsetX, offsetY, cellWidth, cellHeight, 0); // 下方宫
    _drawPalace(canvas, linePaint, offsetX, offsetY, cellWidth, cellHeight, 7); // 上方宫

    // 绘制河界文字
    _drawRiverText(canvas, offsetX, offsetY, cellWidth, cellHeight, gridWidth);

    // 绘制星位标记
    _drawStarPoints(canvas, offsetX, offsetY, cellWidth, cellHeight);

    // 绘制高亮（最后走法）
    if (lastMove != null) {
      _drawMoveHighlight(canvas, lastMove!, offsetX, offsetY, cellWidth, cellHeight);
    }

    // 绘制选中高亮
    if (selectedRow != null && selectedCol != null) {
      _drawSelection(canvas, selectedRow!, selectedCol!, offsetX, offsetY,
          cellWidth, cellHeight);
    }

    // 绘制可走位置提示
    for (final move in validMoves) {
      _drawValidMoveHint(canvas, move, offsetX, offsetY, cellWidth, cellHeight);
    }

    // 绘制棋子
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 9; c++) {
        final piece = grid[r][c];
        if (piece != null) {
          final displayRow = flipBoard ? 9 - r : r;
          _drawPiece(canvas, piece, _getX(c, offsetX, cellWidth),
              _getY(displayRow, offsetY, cellHeight), cellWidth * 0.44);
        }
      }
    }
  }

  void _drawPalace(Canvas canvas, Paint paint, double offsetX, double offsetY,
      double cellWidth, double cellHeight, int startRow) {
    final x1 = offsetX + 3 * cellWidth;
    final x2 = offsetX + 5 * cellWidth;
    final y1 = offsetY + startRow * cellHeight;
    final y2 = offsetY + (startRow + 2) * cellHeight;
    canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    canvas.drawLine(Offset(x2, y1), Offset(x1, y2), paint);
  }

  void _drawRiverText(Canvas canvas, double offsetX, double offsetY,
      double cellWidth, double cellHeight, double gridWidth) {
    final textStyle = TextStyle(
      fontSize: cellHeight * 0.45,
      color: const Color(0xFF5C3A1E),
      fontWeight: FontWeight.bold,
    );

    // 楚河
    _drawText(canvas, '楚  河', offsetX + gridWidth * 0.15,
        offsetY + 4.5 * cellHeight, textStyle);

    // 汉界
    _drawText(canvas, '漢  界', offsetX + gridWidth * 0.62,
        offsetY + 4.5 * cellHeight, textStyle);
  }

  void _drawText(
      Canvas canvas, String text, double x, double y, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  void _drawStarPoints(Canvas canvas, double offsetX, double offsetY,
      double cellWidth, double cellHeight) {
    final positions = [
      // 兵/卒位置
      [3, 0], [3, 2], [3, 4], [3, 6], [3, 8],
      [6, 0], [6, 2], [6, 4], [6, 6], [6, 8],
      // 炮位置
      [2, 1], [2, 7], [7, 1], [7, 7],
    ];

    for (final pos in positions) {
      final r = pos[0];
      final c = pos[1];
      final displayRow = flipBoard ? 9 - r : r;
      _drawStarPoint(canvas, _getX(c, offsetX, cellWidth),
          _getY(displayRow, offsetY, cellHeight), cellWidth * 0.1);
    }
  }

  void _drawStarPoint(Canvas canvas, double x, double y, double size) {
    final paint = Paint()
      ..color = const Color(0xFF5C3A1E)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final gap = size * 0.3;
    // 四个角各画一个小标记
    final dirs = [
      [-1, -1],
      [1, -1],
      [-1, 1],
      [1, 1]
    ];
    for (final d in dirs) {
      final dx = d[0].toDouble();
      final dy = d[1].toDouble();
      canvas.drawLine(
          Offset(x + dx * gap, y + dy * gap),
          Offset(x + dx * (gap + size), y + dy * gap),
          paint);
      canvas.drawLine(
          Offset(x + dx * gap, y + dy * gap),
          Offset(x + dx * gap, y + dy * (gap + size)),
          paint);
    }
  }

  void _drawSelection(Canvas canvas, int row, int col, double offsetX,
      double offsetY, double cellWidth, double cellHeight) {
    final displayRow = flipBoard ? 9 - row : row;
    final x = _getX(col, offsetX, cellWidth);
    final y = _getY(displayRow, offsetY, cellHeight);
    final radius = cellWidth * 0.46;
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), radius, paint);

    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(x, y), radius, borderPaint);
  }

  void _drawMoveHighlight(Canvas canvas, ChessMove move, double offsetX,
      double offsetY, double cellWidth, double cellHeight) {
    final paint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    for (final pos in [
      [move.fromRow, move.fromCol],
      [move.toRow, move.toCol]
    ]) {
      final displayRow = flipBoard ? 9 - pos[0] : pos[0];
      final x = _getX(pos[1], offsetX, cellWidth);
      final y = _getY(displayRow, offsetY, cellHeight);
      canvas.drawCircle(Offset(x, y), cellWidth * 0.44, paint);
    }
  }

  void _drawValidMoveHint(Canvas canvas, ChessMove move, double offsetX,
      double offsetY, double cellWidth, double cellHeight) {
    final displayRow = flipBoard ? 9 - move.toRow : move.toRow;
    final x = _getX(move.toCol, offsetX, cellWidth);
    final y = _getY(displayRow, offsetY, cellHeight);

    final target = grid[move.toRow][move.toCol];
    if (target != null) {
      // 可以吃子 - 画红圈
      final paint = Paint()
        ..color = Colors.red.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(Offset(x, y), cellWidth * 0.44, paint);
    } else {
      // 空位 - 画小绿点
      final paint = Paint()
        ..color = Colors.green.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), cellWidth * 0.12, paint);
    }
  }

  void _drawPiece(
      Canvas canvas, ChessPiece piece, double x, double y, double radius) {
    // 棋子底色
    final bgPaint = Paint()
      ..color = const Color(0xFFF8E8C8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), radius, bgPaint);

    // 棋子边框
    final borderPaint = Paint()
      ..color = piece.color == PieceColor.red
          ? const Color(0xFFC0392B)
          : const Color(0xFF2C3E50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(Offset(x, y), radius, borderPaint);

    // 内圈
    canvas.drawCircle(Offset(x, y), radius * 0.85, borderPaint);

    // 棋子文字
    final textStyle = TextStyle(
      fontSize: radius * 1.1,
      fontWeight: FontWeight.bold,
      color: piece.color == PieceColor.red
          ? const Color(0xFFC0392B)
          : const Color(0xFF2C3E50),
      height: 1.0,
    );

    final tp = TextPainter(
      text: TextSpan(text: piece.name, style: textStyle),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  double _getX(int col, double offsetX, double cellWidth) {
    return offsetX + col * cellWidth;
  }

  double _getY(int row, double offsetY, double cellHeight) {
    // row 0 在底部（红方），row 9 在顶部（黑方）
    // 显示时 row 9 在最上面
    return offsetY + (9 - row) * cellHeight;
  }

  @override
  bool shouldRepaint(covariant ChessBoardPainter oldDelegate) {
    return true; // 简化处理，每次都重绘
  }
}
