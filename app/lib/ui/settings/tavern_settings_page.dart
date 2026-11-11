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
  final String _configPath = '/sdcard/Download/st/tavern_config.json';
  
  final List<String> _scanDirectories = [
    '/sdcard/Download',
    '/sdcard/Download/st',
    '/sdcard/Download/Browser',
    '/sdcard/Documents',
  ];
  
  List<FileSystemEntity> _bookFiles = [];
  Map<String, dynamic>? _currentBook;
  String? _currentBookPath;
  String? _activeBookPath; // 当前激活生效的世界书路径
  
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
          _activeBookPath = data['active_book_path'];
          if (data['regex_presets'] is List) {
            _regexPresets = List<Map<String, dynamic>>.from(data['regex_presets']);
          }
        });
      }
    } catch (_) {}
  }

  void _saveConfig({bool notify = true}) {
    try {
      final f = File(_configPath);
      final data = {
        'max_entries': _maxEntries,
        'max_chars': _maxChars,
        'enable_auto_import': _enableAutoImport,
        'active_book_path': _activeBookPath,
        'regex_presets': _regexPresets,
      };
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
      if (notify && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存生效！')));
      }
    } catch (e) {
      if (notify && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存配置失败: $e')));
      }
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

  void _openCustomPathDialog() {
    final ctrl = TextEditingController(text: '/sdcard/Download/');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入文件绝对路径导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('可输入手机内任意 JSON 世界书或酒馆角色卡路径：', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '/sdcard/Download/xxx.json',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final p = ctrl.text.trim();
              if (p.isNotEmpty) {
                _openBook(p);
              }
            },
            child: const Text('导入读取'),
          ),
        ],
      ),
    );
  }

  void _openBook(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('文件不存在: $path')));
        return;
      }
      final raw = f.readAsStringSync();
      final decoded = json.decode(raw);

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

  void _toggleActiveBook(String path) {
    setState(() {
      if (_activeBookPath == path) {
        _activeBookPath = null; // 取消激活
      } else {
        _activeBookPath = path; // 设为当前激活
      }
    });
    _saveConfig();
  }

  void _deleteBookFile(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除文件？'),
        content: Text('即将从本地存储彻底删除：\n$path'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              try {
                final f = File(path);
                if (f.existsSync()) {
                  f.deleteSync();
                }
                if (_activeBookPath == path) {
                  _activeBookPath = null;
                  _saveConfig(notify: false);
                }
                _scanWorldBooks();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件已删除')));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
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

      final isBookActive = _activeBookPath == _currentBookPath;

      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _currentBook = null),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_currentBookPath?.split('/').last}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '共 ${entries.length} 条条目 | 状态: ${isBookActive ? "【当前已装载生效】" : "【未装载】"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isBookActive ? Colors.green : Colors.grey,
                          fontWeight: isBookActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => _toggleActiveBook(_currentBookPath!),
                  child: Text(isBookActive ? '卸载' : '装载生效'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('保存'),
                  onPressed: _saveCurrentBook,
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
            child: const Text(
              '说明：右侧开关开启 = 【常驻注入】（每轮强制塞入Prompt）；关闭 = 【触发词动态注入】（当对话命中关键词时才载入，不命中则不载入）。若整条不需要，可清空触发词。',
              style: TextStyle(fontSize: 12, color: Colors.black87),
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
                  title: Row(
                    children: [
                      Expanded(child: Text(e['comment']?.toString() ?? '未命名条目', style: const TextStyle(fontWeight: FontWeight.bold))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isConstant ? Colors.blue.withOpacity(0.15) : Colors.grey.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isConstant ? '常驻注入' : '关键词触发',
                          style: TextStyle(fontSize: 11, color: isConstant ? Colors.blue[800] : Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text('触发词: ${keys.isEmpty ? "(无)" : keys}\n$content', maxLines: 2, overflow: TextOverflow.ellipsis),
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
        // 顶部展示当前装载的世界书状态
        Card(
          color: _activeBookPath != null ? Colors.green.withOpacity(0.08) : null,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: _activeBookPath != null ? Colors.green : Colors.transparent, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  _activeBookPath != null ? Icons.check_circle : Icons.info_outline,
                  color: _activeBookPath != null ? Colors.green : Colors.grey,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeBookPath != null ? '当前装载生效中：' : '当前未装载任何世界书',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _activeBookPath != null ? _activeBookPath!.split('/').last : '请在下方列表中选择一本点击「装载」，或点击路径导入',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                if (_activeBookPath != null)
                  FilledButton.tonal(
                    onPressed: () => _toggleActiveBook(_activeBookPath!),
                    child: const Text('卸载'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.input),
                label: const Text('自定义路径导入'),
                onPressed: _openCustomPathDialog,
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
        const Text('手机扫描到的世界书与角色卡列表：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (_bookFiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('未扫描到世界书，可点击上方「自定义路径导入」直接加载')),
          )
        else
          ..._bookFiles.map((f) {
            final isActive = _activeBookPath == f.path;
            return Card(
              elevation: isActive ? 2 : 1,
              child: ListTile(
                leading: Icon(Icons.menu_book, color: isActive ? Colors.green : null),
                title: Text(
                  f.path.split('/').last,
                  style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
                ),
                subtitle: Text(isActive ? '【当前使用中】' : f.path),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: isActive ? Colors.green.withOpacity(0.15) : null,
                        foregroundColor: isActive ? Colors.green[800] : null,
                      ),
                      onPressed: () => _toggleActiveBook(f.path),
                      child: Text(isActive ? '使用中' : '装载'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: '删除此文件',
                      onPressed: () => _deleteBookFile(f.path),
                    ),
                  ],
                ),
                onTap: () => _openBook(f.path),
              ),
            );
          }),
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
                  subtitle: Text('$_maxChars 字 (硬锁杜绝网关413超额)'),
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
                label: const Text('新建规则'),
                onPressed: _addNewRegexDialog,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.document_scanner),
              tooltip: '自动扫描手机正则文件导入',
              onPressed: _scanAndImportRegexFiles,
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              icon: const Icon(Icons.paste),
              tooltip: '粘贴JSON文本导入',
              onPressed: _importRegexFromTextDialog,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_regexPresets.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('当前暂无正则预设规则，可点击上方「扫描导入」或「新建」')),
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

  void _scanAndImportRegexFiles() {
    final List<File> candidates = [];
    for (final dirPath in _scanDirectories) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        try {
          final list = dir.listSync();
          for (final f in list) {
            if (f is File && f.path.endsWith('.json')) {
              final lower = f.path.toLowerCase();
              if (lower.contains('regex') || lower.contains('rule') || lower.contains('filter')) {
                candidates.add(f);
              }
            }
          }
        } catch (_) {}
      }
    }

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未在常用目录扫描到含 regex 命名的 JSON 规则文件')));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择扫描到的正则文件导入'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (c, i) {
              final file = candidates[i];
              return ListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text(file.path.split('/').last),
                subtitle: Text(file.path),
                onTap: () {
                  Navigator.pop(ctx);
                  _importRegexFromFile(file.path);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  void _importRegexFromFile(String path) {
    try {
      final f = File(path);
      final raw = f.readAsStringSync();
      final decoded = json.decode(raw);
      List<dynamic> list = [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded.containsKey('regex_presets')) {
        list = decoded['regex_presets'];
      } else if (decoded is Map && decoded.containsKey('rules')) {
        list = decoded['rules'];
      }

      int count = 0;
      for (final it in list) {
        if (it is Map) {
          final name = it['name'] ?? it['comment'] ?? '导入规则';
          final pattern = it['pattern'] ?? it['regex'] ?? it['findRegex'];
          final replacement = it['replacement'] ?? it['replaceString'] ?? '';
          if (pattern != null && pattern.toString().isNotEmpty) {
            _regexPresets.add({
              'name': name.toString(),
              'pattern': pattern.toString(),
              'replacement': replacement.toString(),
              'enabled': true,
            });
            count++;
          }
        }
      }

      if (count > 0) {
        _saveConfig();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功从文件导入 $count 条正则规则！')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件中未找到有效的正则格式 (需含 pattern 或 regex 字段)')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('解析文件失败: $e')));
    }
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

  void _importRegexFromTextDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴正则配置导入'),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '[{"name": "...", "pattern": "...", "replacement": ""}]',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              try {
                final decoded = json.decode(ctrl.text.trim());
                if (decoded is List) {
                  setState(() {
                    _regexPresets.addAll(List<Map<String, dynamic>>.from(decoded));
                  });
                  _saveConfig();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已成功导入 ${decoded.length} 条正则规则！')));
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('解析JSON失败: $e')));
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }
}
