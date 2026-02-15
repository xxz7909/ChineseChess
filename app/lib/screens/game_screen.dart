import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game/game_controller.dart';
import '../models/board.dart';
import '../widgets/board_widget.dart';

/// 游戏主页面
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameController _controller;

  @override
  void initState() {
    super.initState();
    _controller = GameController();
    _controller.addListener(_onGameUpdate);
    _controller.init();
  }

  void _onGameUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onGameUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C3E50),
      appBar: AppBar(
        title: const Text('中国象棋',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF34495E),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: _onMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'new', child: Text('新游戏')),
              const PopupMenuItem(value: 'undo', child: Text('悔棋')),
              const PopupMenuItem(value: 'switch', child: Text('换先')),
              const PopupMenuItem(value: 'debug', child: Text('引擎日志')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部信息区 - AI(黑方)
            _buildPlayerInfo(isTop: true),
            // 棋盘
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ChessBoardWidget(controller: _controller),
              ),
            ),
            // 底部信息区 - 玩家(红方)
            _buildPlayerInfo(isTop: false),
            // 状态栏
            _buildStatusBar(),
            // 操作按钮
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerInfo({required bool isTop}) {
    final isAI = isTop;
    final icon = isAI ? Icons.computer : Icons.person;
    final isCurrentTurn = isAI
        ? _controller.board.currentPlayer != _controller.playerColor
        : _controller.board.currentPlayer == _controller.playerColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isCurrentTurn
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCurrentTurn
                    ? Colors.green
                    : Colors.grey.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAI ? 'AI (引擎)' : '玩家',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isAI && _controller.engineReady)
                  Text(
                    _controller.engineInfo,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (isAI && !_controller.engineReady)
                  const Text(
                    '引擎未加载',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10),
                  ),
              ],
            ),
          ),
          if (isAI && _controller.isThinking) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _controller.thinkingInfo,
                style: const TextStyle(color: Colors.orange, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    Color statusColor = Colors.white;
    if (_controller.gamePhase == GamePhase.redWin) {
      statusColor = Colors.redAccent;
    } else if (_controller.gamePhase == GamePhase.blackWin) {
      statusColor = Colors.blueGrey;
    } else if (_controller.isThinking) {
      statusColor = Colors.orange;
    } else if (!_controller.engineReady) {
      statusColor = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        _controller.statusMessage,
        style: TextStyle(
          color: statusColor,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(Icons.replay, '新游戏', () => _onMenuAction('new')),
          _buildActionButton(Icons.undo, '悔棋', () => _onMenuAction('undo')),
          _buildActionButton(
              Icons.swap_horiz, '换先', () => _onMenuAction('switch')),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, String label, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF34495E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'new':
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('新游戏'),
            content: const Text('确定要开始新游戏吗？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _controller.newGame();
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
        break;
      case 'undo':
        _controller.undoMove();
        break;
      case 'switch':
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('换先'),
            content: const Text('切换先后手并开始新游戏？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _controller.switchSide();
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
        break;
      case 'debug':
        _showDebugLog();
        break;
    }
  }

  /// 显示引擎调试日志
  void _showDebugLog() {
    final logs = _controller.getEngineDebugLog();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('引擎日志', style: TextStyle(fontSize: 16)),
            const Spacer(),
            Text('${logs.length}条',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: logs.isEmpty
              ? const Center(child: Text('暂无日志'))
              : ListView.builder(
                  itemCount: logs.length,
                  reverse: true,
                  itemBuilder: (ctx, i) {
                    final log = logs[logs.length - 1 - i];
                    Color color = Colors.white70;
                    if (log.contains('ERROR')) {
                      color = Colors.redAccent;
                    } else if (log.contains('WARN')) {
                      color = Colors.orange;
                    } else if (log.contains('>>')) {
                      color = Colors.lightGreenAccent;
                    } else if (log.contains('<<')) {
                      color = Colors.lightBlueAccent;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        log,
                        style: TextStyle(fontSize: 9, color: color),
                      ),
                    );
                  },
                ),
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          TextButton(
            onPressed: () {
              final text = logs.join('\n');
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('日志已复制到剪贴板'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('复制日志'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
