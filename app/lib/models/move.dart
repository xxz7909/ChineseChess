/// 走法模型
class ChessMove {
  final int fromRow;
  final int fromCol;
  final int toRow;
  final int toCol;

  const ChessMove({
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
  });

  /// 转换为UCI坐标格式 (如 a0a1, b0c2)
  /// Pikafish使用 列(a-i) + 行(0-9)
  String toUci() {
    final fromFile = String.fromCharCode('a'.codeUnitAt(0) + fromCol);
    final fromRank = fromRow.toString();
    final toFile = String.fromCharCode('a'.codeUnitAt(0) + toCol);
    final toRank = toRow.toString();
    return '$fromFile$fromRank$toFile$toRank';
  }

  /// 从UCI格式解析
  static ChessMove fromUci(String uci) {
    final fromCol = uci.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final fromRow = int.parse(uci[1]);
    final toCol = uci.codeUnitAt(2) - 'a'.codeUnitAt(0);
    final toRow = int.parse(uci[3]);
    return ChessMove(
      fromRow: fromRow,
      fromCol: fromCol,
      toRow: toRow,
      toCol: toCol,
    );
  }

  @override
  String toString() => toUci();

  @override
  bool operator ==(Object other) =>
      other is ChessMove &&
      fromRow == other.fromRow &&
      fromCol == other.fromCol &&
      toRow == other.toRow &&
      toCol == other.toCol;

  @override
  int get hashCode =>
      fromRow.hashCode ^ fromCol.hashCode ^ toRow.hashCode ^ toCol.hashCode;
}
