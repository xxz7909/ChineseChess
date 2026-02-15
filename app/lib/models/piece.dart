/// 棋子颜色
enum PieceColor { red, black }

/// 棋子类型
enum PieceType {
  king, // 帅/将
  advisor, // 仕/士
  bishop, // 相/象
  knight, // 马
  rook, // 车
  cannon, // 炮
  pawn, // 兵/卒
}

/// 棋子模型
class ChessPiece {
  final PieceType type;
  final PieceColor color;
  int row; // 0-9，0为红方底线
  int col; // 0-8，从左到右

  ChessPiece({
    required this.type,
    required this.color,
    required this.row,
    required this.col,
  });

  /// 获取棋子的中文名称
  String get name {
    if (color == PieceColor.red) {
      switch (type) {
        case PieceType.king:
          return '帅';
        case PieceType.advisor:
          return '仕';
        case PieceType.bishop:
          return '相';
        case PieceType.knight:
          return '马';
        case PieceType.rook:
          return '车';
        case PieceType.cannon:
          return '炮';
        case PieceType.pawn:
          return '兵';
      }
    } else {
      switch (type) {
        case PieceType.king:
          return '将';
        case PieceType.advisor:
          return '士';
        case PieceType.bishop:
          return '象';
        case PieceType.knight:
          return '馬';
        case PieceType.rook:
          return '車';
        case PieceType.cannon:
          return '砲';
        case PieceType.pawn:
          return '卒';
      }
    }
  }

  /// 获取FEN中的字符表示
  String get fenChar {
    String c;
    switch (type) {
      case PieceType.king:
        c = 'k';
        break;
      case PieceType.advisor:
        c = 'a';
        break;
      case PieceType.bishop:
        c = 'b';
        break;
      case PieceType.knight:
        c = 'n';
        break;
      case PieceType.rook:
        c = 'r';
        break;
      case PieceType.cannon:
        c = 'c';
        break;
      case PieceType.pawn:
        c = 'p';
        break;
    }
    return color == PieceColor.red ? c.toUpperCase() : c;
  }

  ChessPiece copy() {
    return ChessPiece(type: type, color: color, row: row, col: col);
  }
}
