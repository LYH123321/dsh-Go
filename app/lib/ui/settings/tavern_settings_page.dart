import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class TavernSettingsPage extends StatefulWidget {
  const TavernSettingsPage({super.key});

  @override
  State<TavernSettingsPage> createState() => _TavernSettingsPageState();
}

class _TavernSettingsPageState extends State<TavernSettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _stDir = '/sdcard/Download/st';
  
  List<FileSystemEntity> _bookFiles = [];
  Map<String, dynamic>? _currentBook;
  String? _currentBookPath;
  
  // 自导入硬锁设置
  int _maxEntries = 4;
  int _maxChars = 2500;
  bool _enableAutoImport = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBooks();
  }

  void _loadBooks() {
    final dir = Directory(_stDir);
    if (dir.existsSync()) {
      setState(() {
        _bookFiles = dir.listSync().where((f) => f.path.endsWith('.json')).toList();
      });
    }
  }

  void _openBook(String path) {
    try {
      final f = File(path);
      final content = f.readAsStringSync();
      setState(() {
        _currentBookPath = path;
        _currentBook = json.decode(content);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('读取失败: $e')));
    }
  }

  void _saveCurrentBook() {
    if (_currentBookPath != null && _currentBook != null) {
      try {
        final f = File(_currentBookPath!);
        f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_currentBook));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('世界书保存成功！')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('酒馆设定与自导入'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '世界书管理'),
            Tab(text: '自导入硬锁'),
            Tab(text: '预设正则'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWorldBookTab(),
          _buildAutoImportTab(),
          _buildRegexTab(),
        ],
      ),
    );
  }

  Widget _buildWorldBookTab() {
    if (_currentBook != null) {
      final entriesRaw = _currentBook!['entries'];
      List<dynamic> entries = [];
      if (entriesRaw is List) {
        entries = entriesRaw;
      } else if (entriesRaw is Map) {
        entries = entriesRaw.values.toList();
      }

      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _currentBook = null),
                ),
                Expanded(
                  child: Text(
                    '${_currentBookPath?.split('/').last} (${entries.length} 条)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('保存'),
                  onPressed: _saveCurrentBook,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final e = entries[idx];
                final bool isConstant = e['constant'] == true;
                final keys = (e['key'] is List) ? (e['key'] as List).join(', ') : (e['key']?.toString() ?? '');
                final content = e['content']?.toString() ?? '';

                return ListTile(
                  title: Text(e['comment']?.toString() ?? '未命名条目', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('触发词: $keys | $content', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Switch(
                    value: isConstant,
                    onChanged: (val) {
                      setState(() {
                        e['constant'] = val;
                      });
                    },
                  ),
                  onTap: () => _editEntryDialog(e),
                );
              },
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('选择本地世界书文件 (/sdcard/Download/st)：', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_bookFiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('目录中未发现 .json 世界书文件')),
          )
        else
          ..._bookFiles.map((f) => Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: Text(f.path.split('/').last),
                  subtitle: Text(f.path),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openBook(f.path),
                ),
              )),
      ],
    );
  }

  void _editEntryDialog(Map<String, dynamic> entry) {
    final titleCtrl = TextEditingController(text: entry['comment']?.toString() ?? '');
    final keysCtrl = TextEditingController(text: (entry['key'] is List) ? (entry['key'] as List).join(', ') : (entry['key']?.toString() ?? ''));
    final contentCtrl = TextEditingController(text: entry['content']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑条目'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '条目标题')),
              TextField(controller: keysCtrl, decoration: const InputDecoration(labelText: '触发关键词 (英文逗号分隔)')),
              TextField(controller: contentCtrl, maxLines: 5, decoration: const InputDecoration(labelText: '设定内容')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() {
                entry['comment'] = titleCtrl.text;
                entry['key'] = keysCtrl.text.split(',').map((s) => s.trim()).toList();
                entry['content'] = contentCtrl.text;
              });
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoImportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('自导入网关防爆硬锁', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('300条世界书全量载入必然超出网关 Token 限制。开启后，每轮仅按输入触发词毫秒级检索并载入极少量设定。'),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('启用按需自导入'),
                  value: _enableAutoImport,
                  onChanged: (v) => setState(() => _enableAutoImport = v),
                ),
                ListTile(
                  title: const Text('单轮最多导入条目数'),
                  subtitle: Text('$_maxEntries 条 (推荐 3~5 条)'),
                  trailing: SizedBox(
                    width: 120,
                    child: Slider(
                      min: 1,
                      max: 10,
                      divisions: 9,
                      value: _maxEntries.toDouble(),
                      onChanged: (v) => setState(() => _maxEntries = v.toInt()),
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('单轮最大注入字符数'),
                  subtitle: Text('$_maxChars 字 (硬锁杜绝网关413超额)'),
                  trailing: SizedBox(
                    width: 120,
                    child: Slider(
                      min: 1000,
                      max: 8000,
                      divisions: 14,
                      value: _maxChars.toDouble(),
                      onChanged: (v) => setState(() => _maxChars = v.toInt()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegexTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('预设正则过滤器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('对输入和输出文本执行酒馆预设清洗（如去除思考标签、排版美化等）。'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
