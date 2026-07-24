import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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

class CheckItem {
  String name;
  ItemStatus status;
  String? linkUrl;

  CheckItem({
    required this.name,
    this.status = ItemStatus.pending,
    this.linkUrl,
  });

  Map<String, dynamic> toMap() {
    return {'name': name, 'status': status.index, 'linkUrl': linkUrl};
  }

  factory CheckItem.fromMap(Map<String, dynamic> map) {
    return CheckItem(
      name: map['name'],
      status: ItemStatus.values[map['status']],
      linkUrl: map['linkUrl'],
    );
  }
}

class ItemTemplate {
  String title;
  List<CheckItem> items;
  Color color;

  ItemTemplate({
    required this.title,
    required this.items,
    this.color = Colors.blue,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'items': items.map((i) => i.toMap()).toList(),
      'color': color.toARGB32(),
    };
  }

  factory ItemTemplate.fromMap(Map<String, dynamic> map) {
    return ItemTemplate(
      title: map['title'],
      items: (map['items'] as List).map((i) => CheckItem.fromMap(i)).toList(),
      color: Color(map['color'] ?? Colors.blue.toARGB32()),
    );
  }
}

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
  bool _isVibrationEnabled = true;
  String _announcement = "";
  String _lastDismissedAnnouncement = "";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _checkUpdates() {
    const currentMsg = "【お知らせ】最新版 v1.0.2 が公開されました！Googleドライブから更新してね。";
    if (currentMsg != _lastDismissedAnnouncement) {
      setState(() {
        _announcement = currentMsg;
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    String encoded = jsonEncode(_templates.map((t) => t.toMap()).toList());
    await prefs.setString('all_templates', encoded);
    await prefs.setInt('current_index', _currentIndex);
    await prefs.setStringList('sc_history', _scHistory);
    await prefs.setBool('vibration_enabled', _isVibrationEnabled);
    await prefs.setString(
      'last_dismissed_announcement',
      _lastDismissedAnnouncement,
    );
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString('all_templates');
    final int? savedIndex = prefs.getInt('current_index');
    final List<String>? savedHistory = prefs.getStringList('sc_history');
    final bool? savedVib = prefs.getBool('vibration_enabled');
    final String? savedDismissed = prefs.getString(
      'last_dismissed_announcement',
    );

    setState(() {
      if (encoded != null) {
        Iterable l = jsonDecode(encoded);
        _templates = List<ItemTemplate>.from(
          l.map((model) => ItemTemplate.fromMap(model)),
        );
        _currentIndex = savedIndex ?? 0;
        if (_currentIndex >= _templates.length) {
          _currentIndex = 0;
        }
        _scHistory = savedHistory ?? [];
        _isVibrationEnabled = savedVib ?? true;
        _lastDismissedAnnouncement = savedDismissed ?? "";
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
      _checkUpdates();
    });
  }

  // 振動ロジック：awaitできるようにFutureを返す
  Future<void> _vibrate(HapticFeedbackType type) async {
    if (!_isVibrationEnabled) {
      return;
    }
    if (type == HapticFeedbackType.light) {
      // OKボタン：ご要望の「カチッ」という感触
      await HapticFeedback.mediumImpact();
    } else {
      // 完了時：しっかりとした「ブルッ」
      await HapticFeedback.vibrate();
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
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.swap_horiz),
            onSelected: (index) {
              if (index == 999) {
                _launchURL('https://forms.gle/your_google_form_url');
              } else if (index == 888) {
                _showSettingsDialog();
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
              });
              _saveData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_announcement.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.yellow[100],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _announcement,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      setState(() {
                        _lastDismissedAnnouncement = _announcement;
                        _announcement = "";
                      });
                      _saveData();
                    },
                  ),
                ],
              ),
            ),
          if (!isAllDone)
            _buildFocusCard(pendingItems.first, currentTemplate.color),
          if (isAllDone) _buildCompleteMessage(),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: currentTemplate.items.length,
              itemBuilder: (context, index) => _buildListTile(
                currentTemplate.items[index],
                currentTemplate.color,
              ),
            ),
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

  Widget _buildFocusCard(CheckItem item, Color themeColor) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
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
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
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
                _actionButton('スキップ', Icons.close, Colors.grey, () async {
                  // 振動を待ってから更新
                  final pending = _templates[_currentIndex].items
                      .where((i) => i.status == ItemStatus.pending)
                      .toList();
                  if (pending.length <= 1) {
                    await _vibrate(HapticFeedbackType.heavy);
                  }

                  setState(() {
                    item.status = ItemStatus.skipped;
                    _sortItems();
                  });
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
                _actionButton('OK!', Icons.check, themeColor, () async {
                  // 1. 振動命令を出し、完了を待つ（画面更新の直前）
                  final pending = _templates[_currentIndex].items
                      .where((i) => i.status == ItemStatus.pending)
                      .toList();
                  if (pending.length <= 1) {
                    await _vibrate(HapticFeedbackType.heavy);
                  } else {
                    await _vibrate(HapticFeedbackType.light);
                  }

                  // 2. 振動の後に画面を更新
                  if (mounted) {
                    setState(() {
                      item.status = ItemStatus.done;
                      _sortItems();
                    });
                    _saveData();
                  }
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    Color color,
    Future<void> Function() onPressed,
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

  Widget _buildListTile(CheckItem item, Color themeColor) {
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
      child: ListTile(
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
                item.linkUrl!.startsWith('shortcuts') ? '🔗 ショートカット' : '🔗 URL',
                style: const TextStyle(fontSize: 10),
              )
            : null,
        trailing: item.status != ItemStatus.pending
            ? TextButton(
                onPressed: () {
                  setState(() {
                    item.status = ItemStatus.pending;
                    _sortItems();
                  });
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
    );
  }

  Widget _buildCompleteMessage() {
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
    Colors.pink,
    Colors.teal,
    Colors.brown,
  ];

  @override
  void initState() {
    super.initState();
    _editingTemplateIndex = widget.initialIndex;
    _titleController.text = widget.templates[_editingTemplateIndex].title;
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _colorPalette
                        .map(
                          (color) => GestureDetector(
                            onTap: () =>
                                setState(() => currentTemplate.color = color),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: currentTemplate.color == color
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
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
                        onChanged: (val) =>
                            setState(() => currentTemplate.title = val),
                        decoration: const InputDecoration(
                          labelText: 'セットの名前',
                          hintText: '例：出張の日',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_to_photos,
                        color: Colors.green,
                      ),
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
