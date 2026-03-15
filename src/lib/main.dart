import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Simple File Logger
class FrontendLogger {
  static File? _logFile;

  static void init() {
    try {
      final exePath = Platform.resolvedExecutable;
      final dir = File(exePath).parent.path;
      _logFile = File('$dir\\frontend.log');
      log("Logger initialized. Exe: $exePath");
    } catch (e) {
      print("Logger init failed: $e");
    }
  }

  static void log(String message) {
    try {
      final timestamp = DateTime.now().toIso8601String();
      _logFile?.writeAsStringSync("$timestamp: $message\n", mode: FileMode.append);
    } catch (e) {
      print("Log failed: $e");
    }
  }
}

void main() async {
  FrontendLogger.init();
  FrontendLogger.log("App starting...");
  
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(600, 650),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: "スクショアプリ PRO",
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    FrontendLogger.log("Window shown");
  });

  runApp(const ScreenshotApp());
}

class ScreenshotApp extends StatelessWidget {
  const ScreenshotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E2E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurpleAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF28283E),
        ),
        useMaterial3: true,
        fontFamily: 'Segoe UI',
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}


class _HomePageState extends State<HomePage> with WindowListener {
  String baseName = "";
  int quality = 85;
  bool isWorking = false;
  String statusMessage = "準備完了";
  int _activeTab = 0; // 0: 撮影, 1: ギャラリー

  // 保存設定
  String? _baseSaveDir;
  List<String> _groups = ["default"];
  String _currentGroup = "default";
  bool _isAlwaysOnTop = false;
  bool _enableShortcuts = false;
  int _imageQuality = 85;
  int _namePattern = 1;

  // Window bounds & Presets
  Rect _mainMenuBounds = const Rect.fromLTWH(0, 0, 600, 650);
  Rect? _lastFrameBounds; // Stores frame position during this session
  List<Map<String, dynamic>> _presets = [];
  String? _selectedPresetName;

  // プレフィックス用コントローラー
  final TextEditingController _baseNameController = TextEditingController();

  // フレーム用コントローラー
  final TextEditingController _xController = TextEditingController();
  final TextEditingController _yController = TextEditingController();
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  Offset _windowPos = Offset.zero;

  final FocusNode _xFocus = FocusNode();
  final FocusNode _yFocus = FocusNode();
  final FocusNode _widthFocus = FocusNode();
  final FocusNode _heightFocus = FocusNode();

  bool isFrameMode = false;
  List<String> _cachedFiles = [];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initGlobalHotKey();
    _initWindowPosition();
    _loadInitialConfig();
    _loadPresets();
    _updateDimensions();
  }

  Future<void> _initGlobalHotKey() async {
    HotKey _hotKey = HotKey(
      key: LogicalKeyboardKey.keyS,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      _hotKey,
      keyDownHandler: (hotKey) async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? presetsJson = prefs.getString('size_presets');
    final int? savedPattern = prefs.getInt('name_pattern');
    if (savedPattern != null) {
      setState(() => _namePattern = savedPattern);
    }
    if (presetsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(presetsJson);
        setState(() {
          _presets = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
          if (_presets.isNotEmpty) {
            _selectedPresetName = _presets.first['name'];
          }
        });
      } catch (e) {
        FrontendLogger.log("Preset decode error: $e");
      }
    }
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('size_presets', jsonEncode(_presets));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _xController.dispose();
    _yController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _xFocus.dispose();
    _yFocus.dispose();
    _widthFocus.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  Future<void> _initWindowPosition() async {
    // Left empty as user requested to remove the warp effect
    // Window will now use 'center: true' in WindowOptions by default.
  }

  Future<void> _loadInitialConfig() async {
    // まずローカルの設定から前回の保存先をロード
    final prefs = await SharedPreferences.getInstance();
    final String? savedDir = prefs.getString('base_save_dir');
    
    if (savedDir != null && savedDir.isNotEmpty) {
      if (mounted) setState(() => _baseSaveDir = savedDir);
    }

    bool backendReady = false;
    while (!backendReady && mounted) {
      try {
        if (savedDir != null && savedDir.isNotEmpty) {
          await http.post(
            Uri.parse('http://127.0.0.1:8000/config'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'base_save_dir': savedDir}),
          );
        }

        final response = await http.get(Uri.parse('http://127.0.0.1:8000/groups'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (mounted) {
            setState(() {
              _groups = List<String>.from(data['groups']);
              
              String backendDir = data['base_dir'];
              if (backendDir == "screenshots" || !backendDir.contains(r"\")) {
                // 強制的にバックエンドの絶対パスに書き換える (ユーザーの環境ズレ対策)
                backendDir = r"C:\Users\TCB-user016\Documents\sk\backend\screenshots";
              }
              _baseSaveDir = backendDir;
              
              if (_groups.isEmpty) _groups = ["default"];
              if (!_groups.contains(_currentGroup)) _currentGroup = _groups.first;
            });
          }
          backendReady = true;
          _refreshGallery(); // バックエンド起動完了後にギャラリーを取得
        }
      } catch (e) {
        FrontendLogger.log("Waiting for backend... $e");
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _pickBaseDir() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'base_save_dir': result}),
      );
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('base_save_dir', result);
        
        setState(() => _baseSaveDir = result);
        _loadInitialConfig();
      }
    }
  }

  Future<void> _showQualityDialog() async {
    int tempQuality = _imageQuality;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("画像サイズ(画質)の変更"),
        content: TextField(
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: "画質 (1〜100, 例: 85)"),
          onChanged: (v) => tempQuality = int.tryParse(v) ?? _imageQuality,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          TextButton(
            onPressed: () {
              setState(() => _imageQuality = tempQuality.clamp(1, 100));
              Navigator.pop(ctx);
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  Future<void> _createNewGroup() async {
    String? newName;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("新しいグループ作成"),
        content: TextField(onChanged: (v) => newName = v, decoration: const InputDecoration(hintText: "グループ名")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("作成")),
        ],
      ),
    );

    if (newName != null && newName!.isNotEmpty) {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/groups'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': newName}),
      );
      if (response.statusCode == 200) {
        await _loadInitialConfig();
        setState(() => _currentGroup = newName!);
      }
    }
  }

  @override
  void onWindowMove() => _updateDimensions();
  @override
  void onWindowResize() => _updateDimensions();

  Future<void> _updateDimensions() async {
    final bounds = await windowManager.getBounds();
    if (mounted) {
      setState(() {
        _windowPos = bounds.topLeft;
        if (!_xFocus.hasFocus) _xController.text = bounds.left.toInt().toString();
        if (!_yFocus.hasFocus) _yController.text = bounds.top.toInt().toString();
        if (!_widthFocus.hasFocus) _widthController.text = bounds.width.toInt().toString();
        if (!_heightFocus.hasFocus) _heightController.text = bounds.height.toInt().toString();
      });
    }
  }

  Future<void> _applyWindowFromInputs() async {
    final x = double.tryParse(_xController.text) ?? _windowPos.dx;
    final y = double.tryParse(_yController.text) ?? _windowPos.dy;
    final w = double.tryParse(_widthController.text) ?? 100;
    final h = double.tryParse(_heightController.text) ?? 100;
    await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
  }

  Future<void> captureFrame() async {
    setState(() => isWorking = true);
    try {
      Rect bounds = await windowManager.getBounds();
      await windowManager.setOpacity(0.0);
      await Future.delayed(const Duration(milliseconds: 200));

      final effectiveName = baseName.trim().isEmpty ? "screenshot" : baseName.trim();
      final response = await http.post(Uri.parse('http://127.0.0.1:8000/capture'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'monitor_index': 1,
          'region': [bounds.left.toInt() + 8, bounds.top.toInt() + 8, bounds.width.toInt() - 16, bounds.height.toInt() - 16],
          'base_name': effectiveName,
          'naming_pattern': _namePattern,
          'sub_dir': _currentGroup,
          'quality': _imageQuality,
        }),
      );
      await windowManager.setOpacity(0.6);
      if (response.statusCode == 200) {
        setState(() => statusMessage = "保存成功");
        if (_activeTab == 1) _refreshGallery();
      }
    } catch (e) {
      await windowManager.setOpacity(0.6);
    } finally {
      setState(() => isWorking = false);
    }
  }

  Future<void> _refreshGallery() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/files/$_currentGroup'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _cachedFiles = List<String>.from(data['files']));
      }
    } catch (e) {
      FrontendLogger.log("Gallery refresh error: $e");
    }
  }

  Future<void> _copyToClipboard(String filename) async {
    final url = "http://127.0.0.1:8000/images/$_currentGroup/$filename";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final item = DataWriterItem();
        item.add(Formats.jpeg(response.bodyBytes));
        await SystemClipboard.instance?.write([item]);
        setState(() => statusMessage = "画像をクリップボードにコピーしました");
      }
    } catch (e) {
      FrontendLogger.log("Clipboard error: $e");
      setState(() => statusMessage = "コピーに失敗しました");
    }
  }

  Future<void> _deleteImage(String filename) async {
    final response = await http.delete(Uri.parse('http://127.0.0.1:8000/files/$_currentGroup/$filename'));
    if (response.statusCode == 200) _refreshGallery();
  }

  void toggleFrameMode() async {
    if (!isFrameMode) {
      _mainMenuBounds = await windowManager.getBounds();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setOpacity(0.6);
      setState(() => isFrameMode = !isFrameMode);

      if (_lastFrameBounds != null) {
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.setBounds(_lastFrameBounds!);
      }
      await _updateDimensions();
    } else {
      _lastFrameBounds = await windowManager.getBounds();
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setOpacity(1.0);
      await windowManager.setBounds(_mainMenuBounds);
      setState(() => isFrameMode = !isFrameMode);
    }
  }

  Future<void> _applyPresetThenCapture(String presetName) async {
    final defaultPreset = {'name': '標準プリセット', 'x': 700.0, 'y': 500.0, 'w': 800.0, 'h': 500.0};
    final preset = presetName == '標準プリセット' 
      ? defaultPreset 
      : _presets.firstWhere((p) => p['name'] == presetName, orElse: () => {});
    if (preset.isEmpty) return;
    
    if (!isFrameMode) {
      _mainMenuBounds = await windowManager.getBounds();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setOpacity(0.6);
      setState(() => isFrameMode = true);
      // Let UI rebuild
      await Future.delayed(const Duration(milliseconds: 100));
      await windowManager.setBounds(Rect.fromLTWH(
        (preset['x'] as num).toDouble(),
        (preset['y'] as num).toDouble(),
        (preset['w'] as num).toDouble(),
        (preset['h'] as num).toDouble(),
      ));
      await _updateDimensions();
    }
  }

  Future<void> _promptSavePreset() async {
    String? name;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("サイズプリセットの保存"),
        content: TextField(
          decoration: const InputDecoration(hintText: "プリセット名"),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("保存")),
        ],
      ),
    );
    if (name != null && name!.isNotEmpty) {
      if (name == "標準プリセット") {
        setState(() => statusMessage = "その名前は予約されているため保存できません");
        return;
      }
      final newPreset = {
        'name': name,
        'x': double.tryParse(_xController.text) ?? _windowPos.dx,
        'y': double.tryParse(_yController.text) ?? _windowPos.dy,
        'w': double.tryParse(_widthController.text) ?? 100,
        'h': double.tryParse(_heightController.text) ?? 100,
      };
      setState(() {
        final idx = _presets.indexWhere((p) => p['name'] == name);
        if (idx >= 0) {
          _presets[idx] = newPreset;
        } else {
          _presets.add(newPreset);
        }
        _selectedPresetName = name;
      });
      await _savePresets();
      setState(() => statusMessage = "プリセット '$name' を保存しました");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isFrameMode) return buildFrameUI();
    return Scaffold(
      appBar: AppBar(
        title: const Text("スクショアプリ", style: TextStyle(fontSize: 14)),
        actions: [
          DropdownButton<String>(
            value: _currentGroup,
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _currentGroup = v;
                  _baseNameController.clear();
                  baseName = "";
                });
                if (_activeTab == 1) _refreshGallery();
              }
            },
            items: _groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
          ),
          IconButton(onPressed: _createNewGroup, icon: const Icon(Icons.create_new_folder_outlined)),
          PopupMenuButton<int>(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onSelected: (int result) async {
              switch (result) {
                case 0:
                  await _pickBaseDir();
                  break;
                case 1:
                  bool next = !_isAlwaysOnTop;
                  await windowManager.setAlwaysOnTop(next);
                  setState(() => _isAlwaysOnTop = next);
                  break;
                case 2:
                  await _showQualityDialog();
                  break;
                case 3:
                  setState(() => _enableShortcuts = !_enableShortcuts);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
              const PopupMenuItem<int>(
                value: 0,
                child: Text('保存先フォルダの選択'),
              ),
              PopupMenuItem<int>(
                value: 1,
                child: Text(_isAlwaysOnTop ? '常に最前面を解除' : '常に最前面に出す'),
              ),
              const PopupMenuItem<int>(
                value: 2,
                child: Text('画像サイズの変更'),
              ),
              CheckedPopupMenuItem<int>(
                value: 3,
                checked: _enableShortcuts,
                child: const Text('ショートカットキーの有効'),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Row(
            children: [
              _tabItem(0, "撮影", Icons.camera_alt_outlined),
              _tabItem(1, "ギャラリー", Icons.photo_library_outlined),
            ],
          ),
        ),
      ),
      body: _activeTab == 0 ? buildMainUI() : buildGalleryUI(),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.grey[100],
        child: Text(statusMessage, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _tabItem(int index, String label, IconData icon) {
    bool active = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _activeTab = index);
          if (index == 1) _refreshGallery();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? Colors.blue : Colors.transparent, width: 2))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, size: 16, color: active ? Colors.blue : Colors.grey), const SizedBox(width: 8), Text(label, style: TextStyle(color: active ? Colors.blue : Colors.grey, fontWeight: active ? FontWeight.bold : FontWeight.normal))],
          ),
        ),
      ),
    );
  }

  Widget buildFrameUI() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyA) {
            if (!isWorking) captureFrame();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.yellowAccent, width: 4)),
          child: Stack(
            children: [
              Positioned(
                top: 10, left: 10,
              child: Row(
                children: [
                  _frameInput("X", _xController, _xFocus),
                  const SizedBox(width: 4),
                  _frameInput("Y", _yController, _yFocus),
                ],
              ),
            ),
            Positioned(
              bottom: 12, left: 12, right: 12,
              child: Row(
                children: [
                  _frameInput("W", _widthController, _widthFocus),
                  const SizedBox(width: 4),
                  _frameInput("H", _heightController, _heightFocus),
                  const Spacer(),
                  IconButton.filled(onPressed: _promptSavePreset, icon: const Icon(Icons.save), style: IconButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white), tooltip: "現在のサイズをプリセットに保存"),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: toggleFrameMode, icon: const Icon(Icons.close), style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black)),
                  const SizedBox(width: 8),
                  SizedBox(width: 56, height: 56, child: IconButton.filled(onPressed: isWorking ? null : captureFrame, icon: const Icon(Icons.camera_alt), style: IconButton.styleFrom(backgroundColor: Colors.redAccent))),
                ],
              ),
            ),
            Positioned.fill(child: GestureDetector(onPanStart: (d) => windowManager.startDragging(), behavior: HitTestBehavior.translucent, child: Container())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _frameInput(String label, TextEditingController ctrl, FocusNode fn) {
    return Container(
      width: 60, height: 32,
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), border: Border.all(color: Colors.white24)),
      child: Row(children: [
        Padding(padding: const EdgeInsets.only(left: 4), child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10))),
        Expanded(child: TextField(controller: ctrl, focusNode: fn, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 4)), onChanged: (_) => _applyWindowFromInputs())),
      ]),
    );
  }

  Widget buildMainUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Group Section Card
              Card(
                elevation: 4,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Column(
                    children: [
                      const Text("現在のグループ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text("$_currentGroup", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Settings Card
              Card(
                elevation: 2,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("保存ファイル設定", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      const Divider(height: 24, color: Colors.white12),
                      TextField(
                        controller: _baseNameController,
                        decoration: InputDecoration(
                          labelText: "接頭辞", 
                          hintText: "screenshot",
                          filled: true,
                          fillColor: Colors.black12,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        onChanged: (v) => baseName = v,
                      ),
                      const SizedBox(height: 20),
                      const Text("命名パターン:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _namePattern,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(value: 1, child: Text("接頭辞+連番 (_01)")),
                              DropdownMenuItem(value: 2, child: Text("日時のみ (YYYYMMDD_HHMMSS)")),
                              DropdownMenuItem(value: 3, child: Text("日時+連番 (YYYYMMDD_HHMMSS_01)")),
                              DropdownMenuItem(value: 4, child: Text("接頭辞+日時 (screenshot_YYYYMMDD_HHMMSS)")),
                              DropdownMenuItem(value: 5, child: Text("接頭辞+日時+連番")),
                            ],
                            onChanged: (v) async {
                              if (v != null) {
                                setState(() => _namePattern = v);
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setInt('name_pattern', v);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Open Frame Button
              ElevatedButton.icon(
                onPressed: toggleFrameMode,
                icon: const Icon(Icons.crop_free, size: 24),
                label: const Text("新しい撮影フレームを開く", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 6,
                ),
              ),
              const SizedBox(height: 32),
              // Preset Section
              Card(
                elevation: 2,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Text("サイズプリセットから撮影", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPresetName ?? '標準プリセット',
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String>(value: '標準プリセット', child: Text('標準プリセット (X:700, Y:500)')),
                              ..._presets.map((p) => DropdownMenuItem<String>(
                                value: p['name'] as String,
                                child: Text(p['name'] as String),
                              ))
                            ],
                            onChanged: (v) {
                              setState(() => _selectedPresetName = v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _applyPresetThenCapture(_selectedPresetName ?? '標準プリセット'),
                          icon: const Icon(Icons.aspect_ratio),
                          label: const Text("適用して開く"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurpleAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildGalleryUI() {
    if (_cachedFiles.isEmpty) return const Center(child: Text("画像がありません"));
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: _cachedFiles.length,
      itemBuilder: (ctx, idx) {
        final filename = _cachedFiles[idx];
        final url = "http://127.0.0.1:8000/images/$_currentGroup/$filename";
        
        return DragItemWidget(
          dragItemProvider: (request) async {
            final item = DragItem();
            try {
              // Fetch image from URL and write to a temporary file to guarantee absolute path validity
              final response = await http.get(Uri.parse(url));
              if (response.statusCode == 200) {
                final tempDir = await getTemporaryDirectory();
                final tempFile = File(p.join(tempDir.path, filename));
                await tempFile.writeAsBytes(response.bodyBytes);
                
                final fileUri = Uri.file(tempFile.absolute.path);
                item.add(Formats.fileUri(fileUri));
                item.add(Formats.jpeg(response.bodyBytes));
              }
            } catch (e) {
              FrontendLogger.log("Drag error: $e");
            }
            return item;
          },
          allowedOperations: () => [DropOperation.copy],
          child: GestureDetector(
            onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition, filename),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(url, fit: BoxFit.cover)
                  )
                ),
                const SizedBox(height: 4),
                Text(filename, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showContextMenu(Offset pos, String filename) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(
          child: const Text("クリップボードにコピー"), 
          onTap: () => _copyToClipboard(filename),
        ),
        PopupMenuItem(
          child: const Text("保存フォルダを開く"), 
          onTap: () async {
            final String safeBaseDir = _baseSaveDir ?? r"C:\Users\TCB-user016\Documents\sk\backend\screenshots";
            final String targetDir = p.join(safeBaseDir, _currentGroup);
            final String absoluteDir = File(targetDir).absolute.path;
            try {
              // Windows-specific robust folder opening
              await Process.run('cmd', ['/c', 'start', '""', absoluteDir]);
            } catch (e) {
              FrontendLogger.log("Explorer open error: $e");
            }
          },
        ),
        PopupMenuItem(
          child: const Text("削除", style: TextStyle(color: Colors.redAccent)), 
          onTap: () => _deleteImage(filename),
        ),
      ],
    );
  }
}
