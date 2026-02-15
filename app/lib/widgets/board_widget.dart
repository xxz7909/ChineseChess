import 'package:flutter/material.dart';
import '../game/game_controller.dart';
import 'board_painter.dart';

/// 棋盘组件
class ChessBoardWidget extends StatelessWidget {
  final GameController controller;

  const ChessBoardWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 棋盘宽高比 9:10 (9列8间隔 + 边距 : 10行9间隔 + 边距)
        final aspectRatio = 10 / 11;
        double width = constraints.maxWidth;
        double height = width / aspectRatio;

        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * aspectRatio;
        }

        return Center(
          child: GestureDetector(
            onTapUp: (details) => _handleTap(details, width, height),
            child: CustomPaint(
              size: Size(width, height),
              painter: ChessBoardPainter(
                grid: controller.board.grid,
                selectedRow: controller.selectedRow,
                selectedCol: controller.selectedCol,
                validMoves: controller.validMoves,
                lastMove: controller.lastMove,
                flipBoard: false,
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(TapUpDetails details, double width, double height) {
    final cellWidth = width / 10;
    final cellHeight = height / 11;
    final offsetX = cellWidth;
    final offsetY = cellHeight * 0.5;

    final tapX = details.localPosition.dx;
    final tapY = details.localPosition.dy;

    // 将点击坐标转换为棋盘行列
    // Y轴: offsetY + (9 - row) * cellHeight = tapY
    // => row = 9 - (tapY - offsetY) / cellHeight
    final displayRow = 9 - ((tapY - offsetY) / cellHeight).round();
    final col = ((tapX - offsetX) / cellWidth).round();

    // 范围检查
    if (displayRow < 0 || displayRow > 9 || col < 0 || col > 8) return;

    controller.onTap(displayRow, col);
  }
}
