import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class TavernSettingsPage extends StatefulWidget {
  const TavernSettingsPage({super.key});

  @override
  State<TavernSettingsPage> createState() => _TavernSettingsPageState();
}

class _TavernSettingsPageState extends State<TavernSettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _configPath = '/sdcard/Download/st/tavern_config.json';
  
  List<String> _scanDirectories = [
    '/sdcard/Download',
    '/sdcard/Download/st',
    '/sdcard/Download/Browser',
  ];
  
  List<FileSystemEntity> _bookFiles = [];
  Map<String, dynamic>? _currentBook;
  String? _currentBookPath;
  
  // 自导入与硬锁设置
  int _maxEntries = 4;
  int _maxChars = 2500;
  bool _enableAutoImport = true;

  // 正则预设列表
  List<Map<String, dynamic>> _regexPresets = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
    _scanWorldBooks();
  }

  void _loadConfig() {
    try {
      final f = File(_configPath);
      if (f.existsSync()) {
        final data = json.decode(f.readAsStringSync());
        setState(() {
          _maxEntries = data['max_entries'] ?? 4;
          _maxChars = data['max_chars'] ?? 2500;
          _enableAutoImport = data['enable_auto_import'] ?? true;
          if (data['regex_presets'] is List) {
            _regexPresets = List<Map<String, dynamic>>.from(data['regex_presets']);
          }
        });
      }
    } catch (_) {}
  }

  void _saveConfig() {
    try {
      final f = File(_configPath);
      final data = {
        'max_entries': _maxEntries,
        'max_chars': _maxChars,
        'enable_auto_import': _enableAutoImport,
        'regex_presets': _regexPresets,
      };
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存！')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存配置失败: $e')));
    }
  }

  void _scanWorldBooks() {
    final List<FileSystemEntity> found = [];
    for (final dirPath in _scanDirectories) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        try {
          final list = dir.listSync();
          for (final f in list) {
            if (f.path.endsWith('.json') && !f.path.endsWith('tavern_config.json')) {
              if (!found.any((item) => item.path == f.path)) {
                found.add(f);
              }
            }
          }
        } catch (_) {}
      }
    }
    setState(() {
      _bookFiles = found;
    });
  }

  Future<void> _pickAndImportFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'png', 'webp'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        _openBook(filePath);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
    }
  }

  void _openBook(String path) {
    try {
      final f = File(path);
      final raw = f.readAsStringSync();
      final decoded = json.decode(raw);

      // 支持提取酒馆角色卡内嵌的 character_book 或独立世界书
      Map<String, dynamic>? bookData;
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('data') && decoded['data'] is Map && decoded['data'].containsKey('character_book')) {
          bookData = Map<String, dynamic>.from(decoded['data']['character_book']);
        } else if (decoded.containsKey('character_book') && decoded['character_book'] is Map) {
          bookData = Map<String, dynamic>.from(decoded['character_book']);
        } else if (decoded.containsKey('entries')) {
          bookData = decoded;
        }
      }

      if (bookData != null) {
        setState(() {
          _currentBookPath = path;
          _currentBook = bookData;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未识别到有效的世界书或角色卡设定格式')));
      }
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
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.file_open),
                label: const Text('选择外部文件导入 (.json)'),
                onPressed: _pickAndImportFile,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新本地扫描',
              onPressed: _scanWorldBooks,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('手机本地扫描到的世界书与设定集：', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_bookFiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('未发现世界书文件，请点击上方按钮直接选择导入')),
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
                const Text('开启后，每轮根据输入词在毫秒级内仅抽取前 N 条最相关的词条，杜绝 300 条世界书全量注入撑爆网关。'),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('启用按需自导入'),
                  value: _enableAutoImport,
                  onChanged: (v) {
                    setState(() => _enableAutoImport = v);
                    _saveConfig();
                  },
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
                      onChanged: (v) {
                        setState(() => _maxEntries = v.toInt());
                        _saveConfig();
                      },
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('单轮最大注入字符数'),
                  subtitle: Text('$_maxChars 字 (硬锁杜绝超额)'),
                  trailing: SizedBox(
                    width: 120,
                    child: Slider(
                      min: 1000,
                      max: 8000,
                      divisions: 14,
                      value: _maxChars.toDouble(),
                      onChanged: (v) {
                        setState(() => _maxChars = v.toInt());
                        _saveConfig();
                      },
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
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新建预设正则'),
                onPressed: _addNewRegexDialog,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.file_upload),
              tooltip: '从文件导入正则预设',
              onPressed: _importRegexFromFile,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_regexPresets.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('当前暂无正则预设规则')),
          )
        else
          ..._regexPresets.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final bool enabled = item['enabled'] ?? true;

            return Card(
              child: ListTile(
                title: Text(item['name'] ?? '未命名规则', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('匹配: ${item['pattern']} -> 替换: "${item['replacement'] ?? ''}"'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: enabled,
                      onChanged: (val) {
                        setState(() {
                          item['enabled'] = val;
                        });
                        _saveConfig();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          _regexPresets.removeAt(idx);
                        });
                        _saveConfig();
                      },
                    ),
                  ],
                ),
                onTap: () => _editRegexDialog(item),
              ),
            );
          }),
      ],
    );
  }

  void _addNewRegexDialog() {
    _editRegexDialog({
      'name': '',
      'pattern': '',
      'replacement': '',
      'enabled': true,
    }, isNew: true);
  }

  void _editRegexDialog(Map<String, dynamic> item, {bool isNew = false}) {
    final nameCtrl = TextEditingController(text: item['name'] ?? '');
    final patternCtrl = TextEditingController(text: item['pattern'] ?? '');
    final replaceCtrl = TextEditingController(text: item['replacement'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNew ? '新建预设正则' : '编辑预设正则'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '规则名称 (如去除思考标签)')),
            TextField(controller: patternCtrl, decoration: const InputDecoration(labelText: '正则表达式 (Regex Pattern)')),
            TextField(controller: replaceCtrl, decoration: const InputDecoration(labelText: '替换为 (留空则代表删除)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() {
                item['name'] = nameCtrl.text;
                item['pattern'] = patternCtrl.text;
                item['replacement'] = replaceCtrl.text;
                if (isNew) {
                  _regexPresets.add(item);
                }
              });
              _saveConfig();
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _importRegexFromFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final content = File(result.files.single.path!).readAsStringSync();
        final decoded = json.decode(content);
        if (decoded is List) {
          setState(() {
            _regexPresets.addAll(List<Map<String, dynamic>>.from(decoded));
          });
          _saveConfig();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${decoded.length} 条正则预设！')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入正则失败: $e')));
    }
  }
}
