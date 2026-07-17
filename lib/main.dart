import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
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

  CheckItem({required this.name, this.status = ItemStatus.pending, this.linkUrl});

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

  ItemTemplate({required this.title, required this.items});

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }

  factory ItemTemplate.fromMap(Map<String, dynamic> map) {
    return ItemTemplate(
      title: map['title'],
      items: (map['items'] as List).map((i) => CheckItem.fromMap(i)).toList(),
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
  List<String> _scHistory = []; // ショートカット名の履歴
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
        _templates = List<ItemTemplate>.from(l.map((model) => ItemTemplate.fromMap(model)));
        _currentIndex = (savedIndex != null && savedIndex < _templates.length) ? savedIndex : 0;
        _scHistory = savedHistory ?? [];
      } else {
        _templates = [
          ItemTemplate(title: '仕事の日', items: [
            CheckItem(name: '携帯・財布・鍵'),
            CheckItem(name: '電車遅延確認', linkUrl: 'shortcuts://run-shortcut?name=電車確認'),
          ]),
        ];
      }
      _isLoading = false;
    });
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('開けませんでした: $urlString')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _templates.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final currentTemplate = _templates[_currentIndex];
    final pendingItems = currentTemplate.items.where((i) => i.status == ItemStatus.pending).toList();
    final isAllDone = pendingItems.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentTemplate.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.swap_horiz),
            onSelected: (index) => setState(() { _currentIndex = index; _saveData(); }),
            itemBuilder: (context) => _templates.asMap().entries.map((e) => PopupMenuItem(value: e.key, child: Text(e.value.title))).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (context) => EditTemplatesPage(templates: _templates, initialIndex: _currentIndex, scHistory: _scHistory)));
              setState(() {});
              _saveData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isAllDone) _buildFocusCard(pendingItems.first),
          if (isAllDone) _buildCompleteMessage(),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: currentTemplate.items.length,
              itemBuilder: (context, index) => _buildListTile(currentTemplate.items[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusCard(CheckItem item) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            const Text('確認してください', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(item.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            
            if (item.linkUrl != null && item.linkUrl!.isNotEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _launchURL(item.linkUrl!),
                icon: const Icon(Icons.play_arrow),
                label: Text(item.linkUrl!.startsWith('shortcuts') ? 'ショートカットを実行' : 'リンクを開く'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[50], foregroundColor: Colors.blue),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton('スキップ', Icons.close, Colors.grey, () { setState(() => item.status = ItemStatus.skipped); _saveData(); }),
                _actionButton('後で', Icons.replay, Colors.orange, () {
                  setState(() {
                    final items = _templates[_currentIndex].items;
                    items.remove(item);
                    items.add(item);
                  });
                  _saveData();
                }),
                _actionButton('OK!', Icons.check, Colors.green, () { setState(() => item.status = ItemStatus.done); _saveData(); }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(16), backgroundColor: color.withOpacity(0.1), foregroundColor: color, elevation: 0),
          child: Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildListTile(CheckItem item) {
    Color textColor = item.status == ItemStatus.pending ? Colors.black : Colors.grey;
    Color bgColor = item.status == ItemStatus.done ? Colors.green.withOpacity(0.05) : (item.status == ItemStatus.skipped ? Colors.grey.withOpacity(0.05) : Colors.transparent);

    return Container(
      color: bgColor,
      child: ListTile(
        leading: Icon(item.status == ItemStatus.done ? Icons.check_circle : (item.status == ItemStatus.skipped ? Icons.block : Icons.circle_outlined), color: item.status == ItemStatus.done ? Colors.green : (item.status == ItemStatus.skipped ? Colors.grey : Colors.blue)),
        title: Text(item.name, style: TextStyle(color: textColor, fontWeight: item.status == ItemStatus.pending ? FontWeight.bold : FontWeight.normal)),
        subtitle: (item.linkUrl != null && item.linkUrl!.isNotEmpty) 
          ? Text(item.linkUrl!.startsWith('shortcuts') ? '🔗 ショートカット' : '🔗 URL', style: const TextStyle(fontSize: 10)) 
          : null,
        trailing: item.status != ItemStatus.pending ? TextButton(onPressed: () { setState(() => item.status = ItemStatus.pending); _saveData(); }, child: const Text('戻す')) : null,
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
          const Text('すべての確認が完了しました！', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () { setState(() { for (var item in _templates[_currentIndex].items) { item.status = ItemStatus.pending; } }); _saveData(); }, child: const Text('リストをリセット')),
        ],
      ),
    );
  }
}

// --- テンプレート編集画面 ---

class EditTemplatesPage extends StatefulWidget {
  final List<ItemTemplate> templates;
  final int initialIndex;
  final List<String> scHistory; // 追加
  const EditTemplatesPage({super.key, required this.templates, required this.initialIndex, required this.scHistory});

  @override
  State<EditTemplatesPage> createState() => _EditTemplatesPageState();
}

class _EditTemplatesPageState extends State<EditTemplatesPage> {
  late int _editingTemplateIndex;
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

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
            color: Colors.blue.withOpacity(0.1),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('編集中のセット: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _editingTemplateIndex,
                        items: widget.templates.asMap().entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.title))).toList(),
                        onChanged: (val) => setState(() { _editingTemplateIndex = val!; _titleController.text = widget.templates[val].title; }),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'セットの名前'))),
                    IconButton(icon: const Icon(Icons.save), onPressed: () => setState(() => currentTemplate.title = _titleController.text)),
                    IconButton(icon: const Icon(Icons.add_to_photos, color: Colors.green), onPressed: () {
                      setState(() {
                        widget.templates.add(ItemTemplate(title: '新しいセット', items: [CheckItem(name: '新しい項目')]));
                        _editingTemplateIndex = widget.templates.length - 1;
                        _titleController.text = '新しいセット';
                      });
                    }),
                    IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), onPressed: () {
                      if (widget.templates.length > 1) {
                        setState(() { widget.templates.removeAt(_editingTemplateIndex); _editingTemplateIndex = 0; _titleController.text = widget.templates[0].title; });
                      }
                    }),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _itemController, decoration: const InputDecoration(hintText: '新しい項目名'))),
                IconButton(icon: const Icon(Icons.add_circle), onPressed: () {
                  if (_itemController.text.isNotEmpty) {
                    setState(() { currentTemplate.items.add(CheckItem(name: _itemController.text)); _itemController.clear(); });
                  }
                }),
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
                return _buildEditTile(item, index, currentTemplate);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditTile(CheckItem item, int index, ItemTemplate template) {
    String displayLinkValue = "";
    int linkTypeIndex = 0;

    if (item.linkUrl != null && item.linkUrl!.isNotEmpty) {
      if (item.linkUrl!.startsWith('shortcuts://run-shortcut?name=')) {
        linkTypeIndex = 1;
        displayLinkValue = item.linkUrl!.replaceFirst('shortcuts://run-shortcut?name=', '');
      } else {
        linkTypeIndex = 2;
        displayLinkValue = item.linkUrl!;
      }
    }

    return Card(
      key: ValueKey(item),
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
                    initialValue: item.name,
                    onChanged: (val) => item.name = val,
                    decoration: const InputDecoration(hintText: '項目名', isDense: true, border: InputBorder.none),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => template.items.removeAt(index))),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 32),
                ToggleButtons(
                  isSelected: [linkTypeIndex == 0, linkTypeIndex == 1, linkTypeIndex == 2],
                  onPressed: (idx) {
                    setState(() {
                      if (idx == 0) item.linkUrl = null;
                      else if (idx == 1) item.linkUrl = 'shortcuts://run-shortcut?name=';
                      else if (idx == 2) item.linkUrl = 'https://';
                    });
                  },
                  constraints: const BoxConstraints(minHeight: 30, minWidth: 60),
                  borderRadius: BorderRadius.circular(8),
                  children: const [Text('なし', style: TextStyle(fontSize: 10)), Text('SC', style: TextStyle(fontSize: 10)), Text('URL', style: TextStyle(fontSize: 10))],
                ),
                const SizedBox(width: 8),
                if (linkTypeIndex != 0)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          key: ValueKey("${item.name}_link_$linkTypeIndex"),
                          initialValue: displayLinkValue,
                          onChanged: (val) {
                            if (linkTypeIndex == 1) {
                              item.linkUrl = 'shortcuts://run-shortcut?name=$val';
                              // 履歴に追加（重複なし）
                              if (val.isNotEmpty && !widget.scHistory.contains(val)) {
                                widget.scHistory.add(val);
                              }
                            } else {
                              item.linkUrl = val;
                            }
                          },
                          style: const TextStyle(fontSize: 12, color: Colors.blue),
                          decoration: InputDecoration(
                            hintText: linkTypeIndex == 1 ? 'ショートカット名' : 'https://...',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            suffixIcon: linkTypeIndex == 1 ? IconButton(
                              icon: const Icon(Icons.open_in_new, size: 16),
                              onPressed: () => launchUrl(Uri.parse('shortcuts://')),
                              tooltip: 'ショートカットアプリを開く',
                            ) : null,
                          ),
                        ),
                        // ショートカット履歴の表示
                        if (linkTypeIndex == 1 && widget.scHistory.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Wrap(
                              spacing: 4,
                              children: widget.scHistory.map((name) => ActionChip(
                                label: Text(name, style: const TextStyle(fontSize: 10)),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  setState(() {
                                    item.linkUrl = 'shortcuts://run-shortcut?name=$name';
                                  });
                                },
                              )).toList(),
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