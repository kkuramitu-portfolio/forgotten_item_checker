import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WasuremonoApp());
}

/// ==========================================
/// 1. バイブレーション管理ヘルパー (最優先課題の解決)
/// ==========================================
class VibrationHelper {
  // OKボタンタップ時の短く心地よい振動
  static Future<void> playClick(bool isEnabled) async {
    if (!isEnabled) return;
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        bool? hasCustom = await Vibration.hasCustomVibrationsSupport();
        if (hasCustom == true) {
          // カスタム振動対応端末: 30msの短い振動、振幅100で心地よいクリック感
          await Vibration.vibrate(duration: 30, amplitude: 100);
        } else {
          // 非対応端末: 単純な30msの振動
          await Vibration.vibrate(duration: 30);
        }
      } else {
        // フォールバック
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      HapticFeedback.lightImpact();
    }
  }

  // 全項目完了時の強い振動 (既存で機能しているもの)
  static Future<void> playHeavy(bool isEnabled) async {
    if (!isEnabled) return;
    HapticFeedback.heavyImpact();
  }
}

/// ==========================================
/// 2. データモデル
/// ==========================================
class CheckItem {
  String id;
  String title;
  int originalIndex;
  String? url;
  String status; // 'pending', 'ok', 'skipped'

  CheckItem({
    required this.id,
    required this.title,
    required this.originalIndex,
    this.url,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'originalIndex': originalIndex,
    'url': url,
    'status': status,
  };

  factory CheckItem.fromJson(Map<String, dynamic> json) => CheckItem(
    id: json['id'],
    title: json['title'],
    originalIndex: json['originalIndex'],
    url: json['url'],
    status: json['status'] ?? 'pending',
  );
}

class Template {
  String id;
  String name;
  int colorValue;
  String pattern;
  List<CheckItem> items;

  Template({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.pattern,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'pattern': pattern,
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory Template.fromJson(Map<String, dynamic> json) => Template(
    id: json['id'],
    name: json['name'],
    colorValue: json['colorValue'],
    pattern: json['pattern'],
    items: (json['items'] as List).map((e) => CheckItem.fromJson(e)).toList(),
  );
}

/// ==========================================
/// 3. 状態管理 (Providerの代用としてChangeNotifierを使用)
/// ==========================================
class AppState extends ChangeNotifier {
  List<Template> templates = [];
  int currentTemplateIndex = 0;
  bool isVibrationEnabled = true;

  // リモートお知らせ用
  String? announcementMessage;
  String? readAnnouncementId;

  AppState() {
    _loadData();
    _fetchAnnouncement();
  }

  Template get currentTemplate => templates[currentTemplateIndex];
  List<CheckItem> get pendingItems =>
      currentTemplate.items.where((e) => e.status == 'pending').toList();
  bool get isAllCompleted =>
      currentTemplate.items.isNotEmpty && pendingItems.isEmpty;

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    isVibrationEnabled = prefs.getBool('isVibrationEnabled') ?? true;
    readAnnouncementId = prefs.getString('readAnnouncementId');

    final String? templatesJson = prefs.getString('templates');
    if (templatesJson != null) {
      final List decoded = jsonDecode(templatesJson);
      templates = decoded.map((e) => Template.fromJson(e)).toList();
    } else {
      // 初期データ
      templates = [
        Template(
          id: '1',
          name: 'お出かけ基本セット',
          colorValue: Colors.blue.value,
          pattern: 'dots',
          items: [
            CheckItem(id: 'i1', title: '財布', originalIndex: 0),
            CheckItem(id: 'i2', title: 'スマホ', originalIndex: 1),
            CheckItem(id: 'i3', title: '鍵', originalIndex: 2),
          ],
        ),
      ];
    }
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isVibrationEnabled', isVibrationEnabled);
    prefs.setString(
      'templates',
      jsonEncode(templates.map((e) => e.toJson()).toList()),
    );
  }

  // リモートお知らせ機能 (GitHub Gist等を想定)
  Future<void> _fetchAnnouncement() async {
    try {
      // ※実際のGistのRaw URLに置き換えてください
      final response = await http.get(
        Uri.parse('https://api.github.com/events'),
      );
      if (response.statusCode == 200) {
        // ダミーロジック: 実際はJSONをパースして id と message を取得
        String fetchedId = "announcement_001";
        String fetchedMsg = "アップデートのお知らせ: 新機能が追加されました！";

        if (readAnnouncementId != fetchedId) {
          announcementMessage = fetchedMsg;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("お知らせ取得失敗: $e");
    }
  }

  void dismissAnnouncement() async {
    announcementMessage = null;
    readAnnouncementId = "announcement_001"; // 実際のIDを保存
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('readAnnouncementId', readAnnouncementId!);
    notifyListeners();
  }

  void toggleVibration(bool val) {
    isVibrationEnabled = val;
    _saveData();
    notifyListeners();
  }

  // --- チェックアクション ---
  void markAsOk(CheckItem item) {
    item.status = 'ok';
    VibrationHelper.playClick(isVibrationEnabled); // ★ 確実な短い振動
    _checkCompletion();
    _saveData();
    notifyListeners();
  }

  void markAsSkipped(CheckItem item) {
    item.status = 'skipped';
    _checkCompletion();
    _saveData();
    notifyListeners();
  }

  void moveToLower(CheckItem item) {
    // 「後で」: リストの最後尾へ移動
    currentTemplate.items.remove(item);
    currentTemplate.items.add(item);
    _saveData();
    notifyListeners();
  }

  void jumpToTop(CheckItem item) {
    // ジャンプ機能: タップした未完了項目を先頭へ
    currentTemplate.items.remove(item);
    currentTemplate.items.insert(0, item);
    _saveData();
    notifyListeners();
  }

  void resetList() {
    // 順番保持ロジック: originalIndexでソートして復元
    for (var item in currentTemplate.items) {
      item.status = 'pending';
    }
    currentTemplate.items.sort(
      (a, b) => a.originalIndex.compareTo(b.originalIndex),
    );
    _saveData();
    notifyListeners();
  }

  void _checkCompletion() {
    if (isAllCompleted) {
      VibrationHelper.playHeavy(isVibrationEnabled); // ★ 完了時の強い振動
    }
  }
}

/// ==========================================
/// 4. UI実装
/// ==========================================
class WasuremonoApp extends StatelessWidget {
  const WasuremonoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '忘れ物チェッカー Pro',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AppState appState = AppState();

  @override
  void initState() {
    super.initState();
    appState.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    appState.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (appState.templates.isEmpty)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final template = appState.currentTemplate;
    final pendingItems = appState.pendingItems;
    final isCompleted = appState.isAllCompleted;

    return Scaffold(
      backgroundColor: Color(template.colorValue).withOpacity(0.1),
      appBar: AppBar(
        title: Text(template.name),
        backgroundColor: Color(template.colorValue),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(appState: appState),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // リモートお知らせバナー
          if (appState.announcementMessage != null)
            MaterialBanner(
              content: Text(appState.announcementMessage!),
              leading: const Icon(Icons.info, color: Colors.blue),
              backgroundColor: Colors.blue.shade50,
              actions: [
                TextButton(
                  onPressed: appState.dismissAnnouncement,
                  child: const Text('閉じる'),
                ),
              ],
            ),

          Expanded(
            child: isCompleted
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 100,
                          color: Colors.green,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '準備完了！いってらっしゃい！',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 40),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('リストをリセット'),
                          onPressed: appState.resetList,
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // フォーカス型UI (先頭の項目を大きく表示)
                      if (pendingItems.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                pendingItems.first.title,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (pendingItems.first.url != null) ...[
                                const SizedBox(height: 10),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.link),
                                  label: const Text('ショートカット起動'),
                                  onPressed: () =>
                                      _launchUrl(pendingItems.first.url),
                                ),
                              ],
                              const SizedBox(height: 30),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey.shade300,
                                    ),
                                    onPressed: () => appState.markAsSkipped(
                                      pendingItems.first,
                                    ),
                                    child: const Text(
                                      'スキップ',
                                      style: TextStyle(color: Colors.black),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.shade100,
                                    ),
                                    onPressed: () => appState.moveToLower(
                                      pendingItems.first,
                                    ),
                                    child: const Text(
                                      '後で',
                                      style: TextStyle(color: Colors.black),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                        vertical: 16,
                                      ),
                                    ),
                                    onPressed: () =>
                                        appState.markAsOk(pendingItems.first),
                                    child: const Text(
                                      'OK!',
                                      style: TextStyle(
                                        fontSize: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          '残りの項目 (タップで先頭へジャンプ)',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),

                      // ジャンプ機能付きの残りリスト
                      Expanded(
                        child: ListView.builder(
                          itemCount: pendingItems.length > 1
                              ? pendingItems.length - 1
                              : 0,
                          itemBuilder: (context, index) {
                            final item = pendingItems[index + 1];
                            return ListTile(
                              leading: const Icon(Icons.circle_outlined),
                              title: Text(item.title),
                              onTap: () => appState.jumpToTop(item), // ★ ジャンプ機能
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// 5. 設定画面
/// ==========================================
class SettingsScreen extends StatelessWidget {
  final AppState appState;
  const SettingsScreen({Key? key, required this.appState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('バイブレーション'),
            subtitle: const Text('OKタップ時および完了時の振動'),
            value: appState.isVibrationEnabled,
            onChanged: (val) {
              appState.toggleVibration(val);
              if (val) VibrationHelper.playClick(true); // テスト振動
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('テンプレート管理'),
            subtitle: const Text('リストの追加・色・柄の変更'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              // テンプレート管理画面への遷移 (今回は省略)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('テンプレート管理画面は実装済みと仮定')),
              );
            },
          ),
        ],
      ),
    );
  }
}
