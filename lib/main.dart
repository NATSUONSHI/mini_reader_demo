import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 window_manager（桌面）
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
  }

  runApp(const MiniViewerApp());
}

/// 自定义滚动物理：每次用户滚动 ≈ 固定若干行（跟当前行高联动）
class GentleScrollPhysics extends ClampingScrollPhysics {
  final double lineHeight;

  const GentleScrollPhysics({required this.lineHeight, super.parent});

  @override
  GentleScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return GentleScrollPhysics(
      lineHeight: lineHeight,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // 想要每次滚轮 ≈ 2 行
    const double linesPerTick = 2.0;
    final double step = lineHeight * linesPerTick;

    if (offset == 0) return 0;

    // 无论系统给多大 offset，都量化成固定步长
    return offset.sign * step;
  }
}

/// 整个应用
class MiniViewerApp extends StatelessWidget {
  const MiniViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF1F2020);
    const textColor = Color(0xFFBCBEC4);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mini Text Viewer',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bgColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
          background: bgColor,
          surface: bgColor,
          onBackground: textColor,
          onSurface: textColor,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 13, color: textColor),
        ),
        // 让 Scrollbar 保持可交互，但完全透明
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: MaterialStateProperty.all(true),
          trackVisibility: MaterialStateProperty.all(true),
          thickness: MaterialStateProperty.all(10),
          radius: const Radius.circular(4),
          thumbColor: MaterialStateProperty.all(Colors.transparent),
          trackColor: MaterialStateProperty.all(Colors.transparent),
          trackBorderColor: MaterialStateProperty.all(Colors.transparent),
        ),
      ),
      home: const MiniViewerPage(),
    );
  }
}

/// 迷你文本查看页面
class MiniViewerPage extends StatefulWidget {
  const MiniViewerPage({super.key});

  @override
  State<MiniViewerPage> createState() => _MiniViewerPageState();
}

class _MiniViewerPageState extends State<MiniViewerPage> {
  /// 默认的初始文件路径（需要的话可以自己改）
  static const String defaultFilePath =
      r'D:\1.資料\6.雑貨\HANLI\Flutter開発_part41_801_820.txt';

  /// 当前正在看的文件路径（可以被文件选择器修改）
  String? _currentPath = defaultFilePath;

  String _content = '加载中……';

  // 当前字号（支持 Ctrl + 滚轮缩放）
  double _fontSize = 13.0;

  // 键盘监听使用的 FocusNode
  final FocusNode _focusNode = FocusNode();

  // 防止 Ctrl+Shift 被长按多次触发
  bool _shortcutTriggered = false;

  // 滚动控制器，用于 Scrollbar / 恢复位置
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _offsetKeyForPath(String path) => 'scrollOffset_${path.hashCode}';

  /// 从本地持久化中读取某个文件的上次滚动位置
  Future<double> _loadSavedOffset(String path) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_offsetKeyForPath(path)) ?? 0.0;
  }

  /// 保存当前文件的滚动位置
  Future<void> _saveCurrentOffset() async {
    final path = _currentPath;
    if (path == null) return;
    if (!_scrollController.hasClients) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_offsetKeyForPath(path), _scrollController.offset);
  }

  /// 读取当前路径的文件内容，并尝试恢复滚动位置
  Future<void> _loadFile() async {
    final path = _currentPath;

    if (path == null || path.isEmpty) {
      setState(() {
        _content = '尚未选择要读取的文件。\n\n请点击左上角的小点“O”，选择一个 .txt 文件。';
      });
      return;
    }

    try {
      final file = File(path);
      final exists = await file.exists();
      if (!exists) {
        setState(() {
          _content = '文件不存在：\n$path\n\n请点击左上角的小点“O”重新选择文件。';
        });
        return;
      }

      final text = await file.readAsString();
      setState(() {
        _content = text;
      });

      // 读取保存的 offset，并在下一帧恢复位置
      final savedOffset = await _loadSavedOffset(path);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scrollController.hasClients) return;

        final max = _scrollController.position.maxScrollExtent;
        final target = savedOffset.clamp(0.0, max);
        _scrollController.jumpTo(target);
      });
    } catch (e) {
      setState(() {
        _content = '读取文件失败：\n$path\n\n错误：$e';
      });
    }
  }

  /// 打开文件选择器，选择文件并读取内容
  Future<void> _pickFileAndLoad() async {
    try {
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'Text',
        extensions: <String>['txt'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );

      if (file == null) {
        return;
      }

      setState(() {
        _currentPath = file.path;
        _content = '加载中……';
      });

      await _loadFile();
    } catch (e) {
      setState(() {
        _content = '打开文件选择器失败：\n$e';
      });
    }
  }

  /// 处理键盘事件：
  /// - Ctrl + Shift => 最小化窗口（老板键）
  void _handleKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      final isCtrl = event.isControlPressed;
      final isShift = event.isShiftPressed;

      if (isCtrl && isShift && !_shortcutTriggered) {
        _shortcutTriggered = true;

        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          windowManager.minimize();
        }
      }
    } else if (event is RawKeyUpEvent) {
      _shortcutTriggered = false;
    }
  }

  /// 检测 Ctrl + 鼠标滚轮，调整字号
  void _handlePointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;

    // 是否按着 Ctrl
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final isCtrlPressed =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.control);

    if (!isCtrlPressed) return;

    // 滚轮向上（dy < 0）放大，向下（dy > 0）缩小
    final dy = signal.scrollDelta.dy;

    setState(() {
      if (dy < 0) {
        _fontSize += 1.0;
      } else if (dy > 0) {
        _fontSize -= 1.0;
      }
      // 限制字号范围
      _fontSize = _fontSize.clamp(8.0, 30.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF1F2020);
    const textColor = Color(0xFFBCBEC4);

    final double lineHeight = _fontSize * 1.4;

    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: _handleKey,
      child: Scaffold(
        body: Container(
          color: bgColor,
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              // 捕获鼠标滚轮（包括 Ctrl + 滚轮 放大缩小）
              Listener(
                onPointerSignal: _handlePointerSignal,
                child: NotificationListener<ScrollNotification>(
                  // 监听滚动结束，保存 offset
                  onNotification: (notification) {
                    if (notification is ScrollEndNotification) {
                      _saveCurrentOffset();
                    }
                    return false; // 不拦截
                  },
                  child: Scrollbar(
                    controller: _scrollController,
                    interactive: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: GentleScrollPhysics(lineHeight: lineHeight),
                      child: SelectableText(
                        _content,
                        style: TextStyle(
                          fontSize: _fontSize,
                          color: textColor,
                          height: 1.4,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 左上角的小点按钮（打开文件）
              Positioned(
                top: 0,
                left: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _pickFileAndLoad,
                    behavior: HitTestBehavior.translucent,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      color: Colors.transparent,
                      child: const Text(
                        'O',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0x80BCBEC4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
