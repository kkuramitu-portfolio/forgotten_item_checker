import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ForgottenItemCheckerApp());
}

class ForgottenItemCheckerApp extends StatelessWidget {
  const ForgottenItemCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '忘れ物チェッカー Pro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainCheckPage(),
    );
  }
}

enum ItemStatus { pending, done, skipped }

// --- モデルクラス ---
class CheckItem {
  String name;
  ItemStatus status;
  String? linkUrl;
  int originalIndex;

  CheckItem({
    required this.name,
    this.status = ItemStatus.pending,
    this.linkUrl,
    this.originalIndex = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'status': status.index,
      'linkUrl': linkUrl,
      'originalIndex': originalIndex,
    };
  }

  factory CheckItem.fromMap(Map<String, dynamic> map) {
    return CheckItem(
      name: map['name'],
      status: ItemStatus.values[map['status']],
      linkUrl: map['linkUrl'],
      originalIndex: map['originalIndex'] ?? 0,
    );
  }
}

class ItemTemplate {
  String title;
  List<CheckItem> items;
  Color color;
  String pattern;

  ItemTemplate({
    required this.title,
    required this.items,
    this.color = Colors.blue,
    this.pattern = 'none',
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'items': items.map((i) => i.toMap()).toList(),
      'color': color.toARGB32(),
      'pattern': pattern,
    };
  }

  factory ItemTemplate.fromMap(Map<String, dynamic> map) {
    return ItemTemplate(
      title: map['title'],
      items: (map['items'] as List).map((i) => CheckItem.fromMap(i)).toList(),
      color: Color(map['color'] ?? Colors.blue.toARGB32()),
      pattern: map['pattern'] ?? 'none',
    );
  }
}

// --- 柄を描画するウィジェット ---
class PatternOverlay extends StatelessWidget {
  final String pattern;
  final Color color;
  final double opacity;

  const PatternOverlay({
    super.key,
    required this.pattern,
    required this.color,
    this.opacity = 0.2,
  });

  @override
  Widget build(BuildContext context) {
    if (pattern == 'none') return const SizedBox.shrink();

    IconData iconData;
    double size = 24;
    switch (pattern) {
      case 'dots':
        iconData = Icons.circle;
        size = 8;
        break;
      case 'stars':
        iconData = Icons.star;
        size = 16;
        break;
      case 'stripes':
        iconData = Icons.reorder;
        size = 24;
        break;
      case 'check':
        iconData = Icons.grid_4x4;
        size = 24;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Opacity(
      opacity: opacity,
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color],
        ).createShader(bounds),
        child: Wrap(
          children: List.generate(
            100,
            (index) => Icon(iconData, size: size, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// --- メイン画面 ---
class MainCheckPage extends StatefulWidget {
  const MainCheckPage({super.key});

  @override
  State<MainCheckPage> createState() => _MainCheckPageState();
}

class _MainCheckPageState extends State<MainCheckPage> {
  List<ItemTemplate> _templates = [];
  List<String> _scHistory = [];
  int _currentIndex = 0;
  bool _isLoading = true;

  String _announcementMessage = "";
  String _announcementId = "";
  String _lastReadId = "";
  bool _showBanner = false;

  final String _feedbackUrl =
      "https://docs.google.com/forms/d/e/1FAIpQLSfwPKdGwoEvtr3VvRbvYGuMjd6Gb0_VHIs83OCQo_Cvltv5-A/viewform?usp=pp_url&entry.1476558753=%E5%BF%98%E3%82%8C%E7%89%A9%E3%83%81%E3%82%A7%E3%83%83%E3%82%AB%E3%83%BC+Pro";
  final String _gistUrl =
      "https://gist.githubusercontent.com/kkuramitu-portfolio/db7b4736727b15c24b3bcd4975474235/raw/announcement.json";

  bool _isVibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadData();
    await _fetchRemoteAnnouncement();
  }

  Future<void> _fetchRemoteAnnouncement() async {
    if (_gistUrl.contains("docs.google.com")) return;
    try {
      final urlWithTimestamp =
          "$_gistUrl?t=${DateTime.now().millisecondsSinceEpoch}";
      final response = await http.get(Uri.parse(urlWithTimestamp));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final String newId = data['id'] ?? "";
        final String newMessage = data['message'] ?? "";

        setState(() {
          _announcementId = newId;
          _announcementMessage = newMessage;
          if (_announcementId != _lastReadId &&
              _announcementMessage.isNotEmpty) {
            _showBanner = true;
          }
        });
      }
    } catch (e) {
      debugPrint("お知らせ取得失敗: $e");
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    String encoded = jsonEncode(_templates.map((t) => t.toMap()).toList());
    await prefs.setString('all_templates', encoded);
    await prefs.setInt('current_index', _currentIndex);
    await prefs.setStringList('sc_history', _scHistory);
    await prefs.setBool('vibration_enabled', _isVibrationEnabled);
    await prefs.setString('last_read_announcement_id', _lastReadId);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString('all_templates');
    final int? savedIndex = prefs.getInt('current_index');
    final List<String>? savedHistory = prefs.getStringList('sc_history');
    final bool? savedVib = prefs.getBool('vibration_enabled');
    final String? savedLastReadId = prefs.getString(
      'last_read_announcement_id',
    );

    setState(() {
      if (encoded != null) {
        Iterable l = jsonDecode(encoded);
        _templates = List<ItemTemplate>.from(
          l.map((model) => ItemTemplate.fromMap(model)),
        );

        // 背番号の初期化（互換性対応）
        for (var template in _templates) {
          bool needsInit = template.items.every(
            (item) => item.originalIndex == 0,
          );
          if (needsInit) {
            for (int i = 0; i < template.items.length; i++) {
              template.items[i].originalIndex = i;
            }
          }
        }

        _currentIndex = savedIndex ?? 0;
        if (_currentIndex >= _templates.length) {
          _currentIndex = 0;
        }
        _scHistory = savedHistory ?? [];
        _isVibrationEnabled = savedVib ?? true;
        _lastReadId = savedLastReadId ?? "";
      } else {
        _templates = [
          ItemTemplate(
            title: '仕事の日',
            color: Colors.blue,
            items: [
              CheckItem(name: '携帯・財布・鍵'),
              CheckItem(
                name: '電車遅延確認',
                linkUrl: 'shortcuts://run-shortcut?name=電車確認',
              ),
            ],
          ),
        ];
      }
      _isLoading = false;
    });
  }

  // ★ 修正箇所：バイブレーションを動いていた元の設定に戻しました
  void _vibrate(HapticFeedbackType type) {
    if (_isVibrationEnabled) {
      if (type == HapticFeedbackType.light) {
        HapticFeedback.lightImpact(); // OK時の短い振動
      } else {
        HapticFeedback.vibrate(); // 完了時のしっかりした振動
      }
    }
  }

  void _sortItems() {
    setState(() {
      final items = _templates[_currentIndex].items;
      items.sort((a, b) => a.status.index.compareTo(b.status.index));
    });
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('開けませんでした: $urlString')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _templates.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_currentIndex >= _templates.length) {
      _currentIndex = 0;
    }

    final currentTemplate = _templates[_currentIndex];
    final pendingItems = currentTemplate.items
        .where((i) => i.status == ItemStatus.pending)
        .toList();
    final isAllDone = pendingItems.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentTemplate.title.isEmpty ? '（名前未設定）' : currentTemplate.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: currentTemplate.color.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        flexibleSpace: ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: PatternOverlay(
              pattern: currentTemplate.pattern,
              color: Colors.white,
              opacity: 0.1,
            ),
          ),
        ),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.swap_horiz),
            onSelected: (index) {
              if (index == 999) {
                _launchURL(_feedbackUrl);
              } else if (index == 888) {
                _showSettingsDialog();
              } else if (index == 777) {
                _showAnnouncementDialog();
              } else {
                setState(() {
                  _currentIndex = index;
                  _saveData();
                });
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
              for (int i = 0; i < _templates.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  child: Text(
                    _templates[i].title.isEmpty
                        ? '（名前未設定）'
                        : _templates[i].title,
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem<int>(
                value: 777,
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text('最新のお知らせ'),
                  ],
                ),
              ),
              const PopupMenuItem<int>(
                value: 888,
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.grey, size: 20),
                    SizedBox(width: 8),
                    Text('アプリ設定'),
                  ],
                ),
              ),
              const PopupMenuItem<int>(
                value: 999,
                child: Row(
                  children: [
                    Icon(Icons.feedback_outlined, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('フィードバックを送る'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditTemplatesPage(
                    templates: _templates,
                    initialIndex: _currentIndex,
                    scHistory: _scHistory,
                  ),
                ),
              );
              setState(() {
                if (_currentIndex >= _templates.length) {
                  _currentIndex = 0;
                }
                // 編集画面から戻った際に、本来の順番を背番号として振り直す
                for (var template in _templates) {
                  for (int i = 0; i < template.items.length; i++) {
                    template.items[i].originalIndex = i;
                  }
                }
              });
              _saveData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showBanner && _announcementMessage.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.yellow[100],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.campaign, size: 20, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _announcementMessage,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _showBanner = false;
                        _lastReadId = _announcementId;
                      });
                      _saveData();
                    },
                  ),
                ],
              ),
            ),
          if (!isAllDone)
            _buildFocusCard(
              pendingItems.first,
              currentTemplate.color,
              currentTemplate.pattern,
            ),
          if (isAllDone) _buildCompleteMessage(),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: currentTemplate.items.length,
              itemBuilder: (context, index) => _buildListTile(
                currentTemplate.items[index],
                currentTemplate.color,
                currentTemplate.pattern,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAnnouncementDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('最新のお知らせ'),
          ],
        ),
        content: Text(
          _announcementMessage.isEmpty
              ? "現在、新しいお知らせはありません。"
              : _announcementMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('アプリ設定'),
          content: SwitchListTile(
            title: const Text('バイブレーション'),
            subtitle: const Text('チェック時や完了時に振動します'),
            value: _isVibrationEnabled,
            onChanged: (val) {
              setDialogState(() => _isVibrationEnabled = val);
              setState(() => _isVibrationEnabled = val);
              _saveData();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusCard(CheckItem item, Color themeColor, String pattern) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: PatternOverlay(
              pattern: pattern,
              color: themeColor,
              opacity: 0.05,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                const Text(
                  '確認してください',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (item.linkUrl != null && item.linkUrl!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _launchURL(item.linkUrl!),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      item.linkUrl!.startsWith('shortcuts')
                          ? 'ショートカットを実行'
                          : 'リンクを開く',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor.withValues(alpha: 0.1),
                      foregroundColor: themeColor,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _actionButton('スキップ', Icons.close, Colors.grey, () {
                      setState(() => item.status = ItemStatus.skipped);
                      _sortItems();
                      _saveData();
                    }),
                    _actionButton('後で', Icons.replay, Colors.orange, () {
                      setState(() {
                        final items = _templates[_currentIndex].items;
                        items.remove(item);
                        int lastPendingIndex = items.lastIndexWhere(
                          (i) => i.status == ItemStatus.pending,
                        );
                        items.insert(lastPendingIndex + 1, item);
                      });
                      _saveData();
                    }),
                    _actionButton('OK!', Icons.check, themeColor, () {
                      _vibrate(HapticFeedbackType.light);
                      setState(() => item.status = ItemStatus.done);
                      _sortItems();
                      _saveData();
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
            backgroundColor: color.withValues(alpha: 0.1),
            foregroundColor: color,
            elevation: 0,
          ),
          child: Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildListTile(CheckItem item, Color themeColor, String pattern) {
    Color textColor = item.status == ItemStatus.pending
        ? Colors.black
        : Colors.grey;
    Color bgColor = item.status == ItemStatus.done
        ? themeColor.withValues(alpha: 0.05)
        : (item.status == ItemStatus.skipped
              ? Colors.grey.withValues(alpha: 0.05)
              : Colors.transparent);

    return Container(
      color: bgColor,
      child: Stack(
        children: [
          if (item.status == ItemStatus.done)
            Positioned.fill(
              child: ClipRect(
                child: PatternOverlay(
                  pattern: pattern,
                  color: themeColor,
                  opacity: 0.03,
                ),
              ),
            ),
          ListTile(
            leading: Icon(
              item.status == ItemStatus.done
                  ? Icons.check_circle
                  : (item.status == ItemStatus.skipped
                        ? Icons.block
                        : Icons.circle_outlined),
              color: item.status == ItemStatus.done
                  ? themeColor
                  : (item.status == ItemStatus.skipped
                        ? Colors.grey
                        : themeColor.withValues(alpha: 0.5)),
            ),
            title: Text(
              item.name,
              style: TextStyle(
                color: textColor,
                fontWeight: item.status == ItemStatus.pending
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            subtitle: (item.linkUrl != null && item.linkUrl!.isNotEmpty)
                ? Text(
                    item.linkUrl!.startsWith('shortcuts')
                        ? '🔗 ショートカット'
                        : '🔗 URL',
                    style: const TextStyle(fontSize: 10),
                  )
                : null,
            trailing: item.status != ItemStatus.pending
                ? TextButton(
                    onPressed: () {
                      setState(() => item.status = ItemStatus.pending);
                      _sortItems();
                      _saveData();
                    },
                    child: const Text('戻す'),
                  )
                : null,
            onTap: () {
              setState(() {
                if (item.status == ItemStatus.pending) {
                  final items = _templates[_currentIndex].items;
                  items.remove(item);
                  items.insert(0, item);
                } else {
                  item.status = ItemStatus.pending;
                  _sortItems();
                }
              });
              _saveData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteMessage() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _vibrate(HapticFeedbackType.heavy),
    );
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          const Icon(Icons.celebration, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          const Text(
            'すべての確認が完了しました！',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                for (var item in _templates[_currentIndex].items) {
                  item.status = ItemStatus.pending;
                }
                // リセット時に「本来の順番」に並び直す
                _templates[_currentIndex].items.sort(
                  (a, b) => a.originalIndex.compareTo(b.originalIndex),
                );
              });
              _saveData();
            },
            child: const Text('リストをリセット'),
          ),
        ],
      ),
    );
  }
}

enum HapticFeedbackType { light, heavy }

// --- テンプレート編集画面 ---
class EditTemplatesPage extends StatefulWidget {
  final List<ItemTemplate> templates;
  final int initialIndex;
  final List<String> scHistory;

  const EditTemplatesPage({
    super.key,
    required this.templates,
    required this.initialIndex,
    required this.scHistory,
  });

  @override
  State<EditTemplatesPage> createState() => _EditTemplatesPageState();
}

class _EditTemplatesPageState extends State<EditTemplatesPage> {
  late int _editingTemplateIndex;
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  final List<Color> _colorPalette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    const Color(0xFFFFC0CB),
    const Color(0xFFA7FFEB),
    const Color(0xFFE1BEE7),
    const Color(0xFFFFF9C4),
    const Color(0xFFFFCCBC),
    const Color(0xFF90A4AE),
    const Color(0xFFAED581),
    const Color(0xFFFFD54F),
    const Color(0xFF4DB6AC),
    const Color(0xFFBA68C8),
    Colors.pinkAccent,
    Colors.teal,
    Colors.brown,
    Colors.indigo,
    Colors.blueGrey,
  ];

  final Map<String, IconData> _patterns = {
    'none': Icons.not_interested,
    'dots': Icons.circle,
    'stars': Icons.star,
    'stripes': Icons.reorder,
    'check': Icons.grid_4x4,
  };

  @override
  void initState() {
    super.initState();
    _editingTemplateIndex = widget.initialIndex;
    _titleController.text = widget.templates[_editingTemplateIndex].title;
  }

  void _duplicateCurrentTemplate() {
    final original = widget.templates[_editingTemplateIndex];
    final duplicatedItems = original.items
        .map(
          (item) => CheckItem(
            name: item.name,
            linkUrl: item.linkUrl,
            status: ItemStatus.pending,
            originalIndex: item.originalIndex, // コピー時も引き継ぐ
          ),
        )
        .toList();

    final newTemplate = ItemTemplate(
      title: "${original.title}（コピー）",
      items: duplicatedItems,
      color: original.color,
      pattern: original.pattern,
    );

    setState(() {
      widget.templates.add(newTemplate);
      _editingTemplateIndex = widget.templates.length - 1;
      _titleController.text = newTemplate.title;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTemplate = widget.templates[_editingTemplateIndex];

    return Scaffold(
      appBar: AppBar(title: const Text('テンプレートの編集')),
      body: Column(
        children: [
          Container(
            color: currentTemplate.color.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      '編集中のセット: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _editingTemplateIndex,
                        items: widget.templates.asMap().entries.map((e) {
                          final displayName = e.value.title.isEmpty
                              ? '（名前未設定）'
                              : e.value.title;
                          return DropdownMenuItem(
                            value: e.key,
                            child: Text(displayName),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() {
                          _editingTemplateIndex = val!;
                          _titleController.text = widget.templates[val].title;
                        }),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _colorPalette
                        .map(
                          (color) => GestureDetector(
                            onTap: () =>
                                setState(() => currentTemplate.color = color),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      currentTemplate.color.toARGB32() ==
                                          color.toARGB32()
                                      ? Colors.black
                                      : Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Text(
                  '柄を選択',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _patterns.entries
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: ChoiceChip(
                              label: Icon(
                                e.value,
                                size: 18,
                                color: currentTemplate.pattern == e.key
                                    ? Colors.white
                                    : Colors.grey,
                              ),
                              selected: currentTemplate.pattern == e.key,
                              selectedColor: currentTemplate.color,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(
                                    () => currentTemplate.pattern = e.key,
                                  );
                                }
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        onChanged: (val) {
                          setState(() {
                            currentTemplate.title = val;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'セットの名前',
                          hintText: '例：出張の日',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.content_copy,
                        color: Colors.orange,
                      ),
                      tooltip: '現在のセットを複製',
                      onPressed: _duplicateCurrentTemplate,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_to_photos,
                        color: Colors.green,
                      ),
                      tooltip: '新規セット追加',
                      onPressed: () {
                        setState(() {
                          widget.templates.add(
                            ItemTemplate(
                              title: '',
                              items: [],
                              color: Colors.blue,
                            ),
                          );
                          _editingTemplateIndex = widget.templates.length - 1;
                          _titleController.clear();
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      tooltip: '現在のセットを削除',
                      onPressed: () {
                        if (widget.templates.length > 1) {
                          setState(() {
                            widget.templates.removeAt(_editingTemplateIndex);
                            if (_editingTemplateIndex >=
                                widget.templates.length) {
                              _editingTemplateIndex =
                                  widget.templates.length - 1;
                            }
                            _titleController.text =
                                widget.templates[_editingTemplateIndex].title;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemController,
                    decoration: const InputDecoration(
                      hintText: '新しい項目名を入力（決定で追加）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (val) {
                      if (val.isNotEmpty) {
                        setState(() {
                          currentTemplate.items.add(CheckItem(name: val));
                          _itemController.clear();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle,
                    color: Colors.blue,
                    size: 36,
                  ),
                  onPressed: () {
                    if (_itemController.text.isNotEmpty) {
                      setState(() {
                        currentTemplate.items.add(
                          CheckItem(name: _itemController.text),
                        );
                        _itemController.clear();
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          if (currentTemplate.items.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  '項目がまだありません。\n上の入力欄から項目を追加してください。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            )
          else
            Expanded(
              child: ReorderableListView.builder(
                itemCount: currentTemplate.items.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = currentTemplate.items.removeAt(oldIndex);
                    currentTemplate.items.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final item = currentTemplate.items[index];
                  return EditItemTile(
                    key: ValueKey(item),
                    item: item,
                    index: index,
                    template: currentTemplate,
                    scHistory: widget.scHistory,
                    onDelete: () =>
                        setState(() => currentTemplate.items.removeAt(index)),
                    onHistoryChanged: () => setState(() {}),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// --- 各項目の編集用タイル ---
class EditItemTile extends StatefulWidget {
  final CheckItem item;
  final int index;
  final ItemTemplate template;
  final List<String> scHistory;
  final VoidCallback onDelete;
  final VoidCallback onHistoryChanged;

  const EditItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.template,
    required this.scHistory,
    required this.onDelete,
    required this.onHistoryChanged,
  });

  @override
  State<EditItemTile> createState() => _EditItemTileState();
}

class _EditItemTileState extends State<EditItemTile> {
  late TextEditingController _linkController;

  @override
  void initState() {
    super.initState();
    String displayValue = "";
    if (widget.item.linkUrl != null &&
        widget.item.linkUrl!.startsWith('shortcuts://run-shortcut?name=')) {
      displayValue = widget.item.linkUrl!.replaceFirst(
        'shortcuts://run-shortcut?name=',
        '',
      );
    } else {
      displayValue = widget.item.linkUrl ?? "";
    }
    _linkController = TextEditingController(text: displayValue);
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int linkTypeIndex = 0;
    if (widget.item.linkUrl != null && widget.item.linkUrl!.isNotEmpty) {
      linkTypeIndex =
          widget.item.linkUrl!.startsWith('shortcuts://run-shortcut?name=')
          ? 1
          : 2;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.drag_handle, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: widget.item.name,
                    onChanged: (val) => widget.item.name = val,
                    decoration: const InputDecoration(
                      hintText: '項目名',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 32),
                ToggleButtons(
                  isSelected: [
                    linkTypeIndex == 0,
                    linkTypeIndex == 1,
                    linkTypeIndex == 2,
                  ],
                  onPressed: (idx) {
                    setState(() {
                      if (idx == 0) {
                        widget.item.linkUrl = null;
                        _linkController.clear();
                      } else if (idx == 1) {
                        widget.item.linkUrl = 'shortcuts://run-shortcut?name=';
                        _linkController.clear();
                      } else {
                        widget.item.linkUrl = 'https://';
                        _linkController.text = 'https://';
                      }
                    });
                  },
                  constraints: const BoxConstraints(
                    minHeight: 30,
                    minWidth: 60,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  children: const [
                    Text('なし', style: TextStyle(fontSize: 10)),
                    Text('SC', style: TextStyle(fontSize: 10)),
                    Text('URL', style: TextStyle(fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 8),
                if (linkTypeIndex != 0)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _linkController,
                          onChanged: (val) {
                            if (linkTypeIndex == 1) {
                              widget.item.linkUrl =
                                  'shortcuts://run-shortcut?name=$val';
                            } else {
                              widget.item.linkUrl = val;
                            }
                          },
                          onFieldSubmitted: (val) {
                            if (linkTypeIndex == 1 && val.isNotEmpty) {
                              if (!widget.scHistory.contains(val)) {
                                setState(() => widget.scHistory.insert(0, val));
                                widget.onHistoryChanged();
                              }
                            }
                          },
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                          decoration: InputDecoration(
                            hintText: linkTypeIndex == 1
                                ? 'ショートカット名'
                                : 'https://...',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            suffixIcon: linkTypeIndex == 1
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 16,
                                    ),
                                    onPressed: () =>
                                        launchUrl(Uri.parse('shortcuts://')),
                                  )
                                : null,
                          ),
                        ),
                        if (linkTypeIndex == 1 && widget.scHistory.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Wrap(
                              spacing: 4,
                              children: widget.scHistory
                                  .map(
                                    (name) => GestureDetector(
                                      onLongPress: () {
                                        setState(
                                          () => widget.scHistory.remove(name),
                                        );
                                        widget.onHistoryChanged();
                                      },
                                      child: ActionChip(
                                        label: Text(
                                          name,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        padding: EdgeInsets.zero,
                                        onPressed: () {
                                          setState(() {
                                            _linkController.text = name;
                                            widget.item.linkUrl =
                                                'shortcuts://run-shortcut?name=$name';
                                          });
                                        },
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
