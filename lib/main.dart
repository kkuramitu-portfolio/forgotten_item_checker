import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // 真っ白画面対策
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
      'color': color.value,
    };
  }

  factory ItemTemplate.fromMap(Map<String, dynamic> map) {
    return ItemTemplate(
      title: map['title'],
      items: (map['items'] as List).map((i) => CheckItem.fromMap(i)).toList(),
      color: Color(map['color'] ?? Colors.blue.value),
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    String encoded = jsonEncode(_templates.map((t) => t.toMap()).toList());
    await prefs.setString('all_templates', encoded);
    await prefs.setInt('current_index', _currentIndex);
    await prefs.setStringList('sc_history', _scHistory);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString('all_templates');
    final int? savedIndex = prefs.getInt('current_index');
    final List<String>? savedHistory = prefs.getStringList('sc_history');

    setState(() {
      if (encoded != null) {
        Iterable l = jsonDecode(encoded);
        _templates = List<ItemTemplate>.from(
          l.map((model) => ItemTemplate.fromMap(model)),
        );
        _currentIndex = (savedIndex != null && savedIndex < _templates.length)
            ? savedIndex
            : 0;
        _scHistory = savedHistory ?? [];
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
    if (_isLoading || _templates.isEmpty)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final currentTemplate = _templates[_currentIndex];
    final pendingItems = currentTemplate.items
        .where((i) => i.status == ItemStatus.pending)
        .toList();
    final isAllDone = pendingItems.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentTemplate.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: currentTemplate.color.withOpacity(0.8),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.swap_horiz),
            onSelected: (index) => setState(() {
              _currentIndex = index;
              _saveData();
            }),
            itemBuilder: (context) => _templates
                .asMap()
                .entries
                .map(
                  (e) =>
                      PopupMenuItem(value: e.key, child: Text(e.value.title)),
                )
                .toList(),
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
              setState(() {});
              _saveData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
                  backgroundColor: themeColor.withOpacity(0.1),
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
                  _saveData();
                }),
                _actionButton('後で', Icons.replay, Colors.orange, () {
                  setState(() {
                    final items = _templates[_currentIndex].items;
                    items.remove(item);
                    items.add(item);
                  });
                  _saveData();
                }),
                _actionButton('OK!', Icons.check, themeColor, () {
                  setState(() => item.status = ItemStatus.done);
                  _saveData();
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
    VoidCallback onPressed,
  ) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
            backgroundColor: color.withOpacity(0.1),
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
        ? themeColor.withOpacity(0.05)
        : (item.status == ItemStatus.skipped
              ? Colors.grey.withOpacity(0.05)
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
                    : themeColor.withOpacity(0.5)),
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
                  setState(() => item.status = ItemStatus.pending);
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
            color: currentTemplate.color.withOpacity(0.1),
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
                        items: widget.templates
                            .asMap()
                            .entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value.title),
                              ),
                            )
                            .toList(),
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
                        decoration: const InputDecoration(labelText: 'セットの名前'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.save),
                      onPressed: () => setState(
                        () => currentTemplate.title = _titleController.text,
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
                              title: '新しいセット',
                              items: [CheckItem(name: '新しい項目')],
                              color: Colors.blue,
                            ),
                          );
                          _editingTemplateIndex = widget.templates.length - 1;
                          _titleController.text = '新しいセット';
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      onPressed: () {
                        if (widget.templates.length > 1) {
                          setState(() {
                            widget.templates.removeAt(_editingTemplateIndex);
                            _editingTemplateIndex = 0;
                            _titleController.text = widget.templates[0].title;
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
                    decoration: const InputDecoration(hintText: '新しい項目名'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle),
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
          Expanded(
            child: ReorderableListView.builder(
              itemCount: currentTemplate.items.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) newIndex -= 1;
                  final item = currentTemplate.items.removeAt(oldIndex);
                  currentTemplate.items.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final item = currentTemplate.items[index];
                // 各タイルを個別のStatefulWidgetとして切り出し、コントローラを管理
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

// --- 各項目の編集用タイル（コントローラ管理のため分離） ---

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
                          // キーボードの完了を押した時に履歴に保存
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
                                    (name) => ActionChip(
                                      label: Text(
                                        name,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      padding: EdgeInsets.zero,
                                      // タップで反映
                                      onPressed: () {
                                        setState(() {
                                          _linkController.text = name;
                                          widget.item.linkUrl =
                                              'shortcuts://run-shortcut?name=$name';
                                        });
                                      },
                                      // 長押しで削除
                                      onLongPress: () {
                                        setState(
                                          () => widget.scHistory.remove(name),
                                        );
                                        widget.onHistoryChanged();
                                      },
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
