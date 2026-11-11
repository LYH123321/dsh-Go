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
    '/sdcard/Download/st/cards',
    '/sdcard/Download/Browser',
    '/sdcard/Documents',
  ];
  
  List<FileSystemEntity> _bookFiles = [];
  List<FileSystemEntity> _cardFiles = [];

  // 当前激活生效的配置
  String? _activeCardPath;
  String? _activeCardName;
  String? _activeBookPath;
  String? _activeBookName;

  // 世界书查看与编辑
  Map<String, dynamic>? _editingBook;
  String? _editingBookPath;

  // 角色卡查看与绑定详情
  Map<String, dynamic>? _viewingCard;
  String? _viewingCardPath;

  // 自导入与硬锁设置
  int _maxEntries = 4;
  int _maxChars = 2500;
  bool _enableAutoImport = true;

  // 正则预设列表
  List<Map<String, dynamic>> _regexPresets = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadConfig();
    _scanFiles();
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
          _activeCardPath = data['active_card_path'];
          _activeCardName = data['active_card_name'];
          _activeBookPath = data['active_book_path'];
          _activeBookName = data['active_book_name'];
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
        'active_card_path': _activeCardPath,
        'active_card_name': _activeCardName,
        'active_book_path': _activeBookPath,
        'active_book_name': _activeBookName,
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

  void _scanFiles() {
    final List<FileSystemEntity> books = [];
    final List<FileSystemEntity> cards = [];

    for (final dirPath in _scanDirectories) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        try {
          final list = dir.listSync();
          for (final f in list) {
            if (f is File && f.path.endsWith('.json') && !f.path.endsWith('tavern_config.json')) {
              try {
                final content = f.readAsStringSync();
                final d = json.decode(content);
                if (d is Map) {
                  // 判断是否是角色卡 (含 spec_v2 或 data.name 或 name+first_mes)
                  if ((d.containsKey('data') && d['data'] is Map && (d['data'] as Map).containsKey('name')) ||
                      (d.containsKey('name') && (d.containsKey('personality') || d.containsKey('first_mes')))) {
                    if (!cards.any((c) => c.path == f.path)) {
                      cards.add(f);
                    }
                  } else if (d.containsKey('entries') || (d.containsKey('character_book') && d['character_book'] is Map)) {
                    // 独立世界书
                    if (!books.any((b) => b.path == f.path)) {
                      books.add(f);
                    }
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    }

    setState(() {
      _bookFiles = books;
      _cardFiles = cards;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('酒馆设定与自导入'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '角色卡装配'),
            Tab(text: '世界书管理'),
            Tab(text: '自导入硬锁'),
            Tab(text: '预设正则'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCharacterCardsTab(),
          _buildWorldBookTab(),
          _buildAutoImportTab(),
          _buildRegexTab(),
        ],
      ),
    );
  }

  // ================= 1. 角色卡装配与世界书绑定 =================
  Widget _buildCharacterCardsTab() {
    if (_viewingCard != null) {
      return _buildCardDetailView();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 新建角色卡（酒馆式编辑表单）
        Card(
          color: Colors.green.withOpacity(0.06),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.green.withOpacity(0.5), width: 1.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: const Icon(Icons.person_add_alt_1, color: Colors.green, size: 30),
            title: const Text('新建角色卡', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('像酒馆一样自己填人设、性格、场景、开场白，保存为标准 spec_v2 卡'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _openCardEditor(null),
          ),
        ),
        const SizedBox(height: 8),
        // 顶部当前装配生效卡片
        Card(
          color: _activeCardPath != null ? Colors.blue.withOpacity(0.08) : null,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: _activeCardPath != null ? Colors.blue : Colors.transparent, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _activeCardPath != null ? Icons.account_circle : Icons.person_off_outlined,
                      color: _activeCardPath != null ? Colors.blue : Colors.grey,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeCardPath != null ? '当前装配角色：${_activeCardName ?? ""}' : '当前未装配任何角色卡',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _activeCardPath != null ? '文件：${_activeCardPath!.split('/').last}' : '装配角色卡后，将自动加载其人设及绑定的专属世界书',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                    if (_activeCardPath != null)
                      FilledButton.tonal(
                        onPressed: () {
                          setState(() {
                            _activeCardPath = null;
                            _activeCardName = null;
                          });
                          _saveConfig();
                        },
                        child: const Text('卸下'),
                      ),
                  ],
                ),
                if (_activeBookPath != null) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.link, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前生效绑定的世界书：${_activeBookName ?? _activeBookPath!.split("/").last}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_link),
                label: const Text('路径导入角色卡'),
                onPressed: () => _openPathImportDialog(isCard: true),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新本地扫描',
              onPressed: _scanFiles,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('手机扫描到的角色卡：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (_cardFiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('未在常用目录扫描到角色卡，可点击上方「路径导入角色卡」')),
          )
        else
          ..._cardFiles.map((f) {
            final isActive = _activeCardPath == f.path;
            String cardName = f.path.split('/').last;
            bool hasEmbeddedBook = false;
            try {
              final d = json.decode(File(f.path).readAsStringSync());
              if (d is Map) {
                if (d.containsKey('data') && d['data'] is Map) {
                  cardName = d['data']['name'] ?? cardName;
                  hasEmbeddedBook = d['data'].containsKey('character_book');
                } else if (d.containsKey('name')) {
                  cardName = d['name'] ?? cardName;
                  hasEmbeddedBook = d.containsKey('character_book');
                }
              }
            } catch (_) {}

            return Card(
              elevation: isActive ? 2 : 1,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isActive ? Colors.blue : Colors.grey[200],
                  child: Icon(Icons.person, color: isActive ? Colors.white : Colors.black54),
                ),
                title: Text(cardName, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(
                  '${f.path.split("/").last} | ${hasEmbeddedBook ? "内嵌角色专属世界书" : "无内嵌世界书"}',
                  style: TextStyle(fontSize: 12, color: hasEmbeddedBook ? Colors.indigo : Colors.grey[600]),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: isActive ? Colors.blue.withOpacity(0.15) : null,
                        foregroundColor: isActive ? Colors.blue[800] : null,
                      ),
                      onPressed: () => _equipCard(f.path, cardName, hasEmbeddedBook),
                      child: Text(isActive ? '装配中' : '装配'),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      onPressed: () => _openCardDetail(f.path),
                    ),
                  ],
                ),
                onTap: () => _openCardDetail(f.path),
              ),
            );
          }),
      ],
    );
  }

  void _equipCard(String path, String name, bool hasEmbeddedBook) {
    setState(() {
      if (_activeCardPath == path) {
        _activeCardPath = null;
        _activeCardName = null;
      } else {
        _activeCardPath = path;
        _activeCardName = name;

        // 如果角色卡自带内嵌专属世界书，自动将其绑定激活为当前世界书
        if (hasEmbeddedBook) {
          _activeBookPath = path;
          _activeBookName = '$name (角色卡专属世界书)';
        }
      }
    });
    _saveConfig();
    _syncAgentPreset();
  }

  /// 把当前装配的角色卡写成官方 Agent 预设（与「伙伴·完整」同一机制），
  /// 注入宿主 rootfs 的 dsh-web.patch.yml。新对话里直接选这个预设 = 官方
  /// 原生链路的角色卡聊天。卸下角色卡时同步移除该预设。
  void _syncAgentPreset() {
    try {
      const patchPath = '/data/user/0/io.github.ccch1mneyyy.dsh_app/files/runtime/rootfs/etc/dsh-app/dsh-web.patch.yml';
      final f = File(patchPath);
      if (!f.existsSync()) return;
      var text = f.readAsStringSync();
      // 移除旧的酒馆预设块（从标记行到下一个 "- insert:" 或文件尾）
      final marker = '    # TAVERN_CARD_PRESET_BEGIN';
      final endMarker = '    # TAVERN_CARD_PRESET_END';
      if (text.contains(marker)) {
        final startIdx = text.indexOf(marker);
        final endIdx = text.indexOf(endMarker);
        if (startIdx != -1 && endIdx != -1) {
          text = text.substring(0, startIdx) + text.substring(endIdx + endMarker.length);
          // 清理可能残留的空行
          text = text.replaceAll('\n\n\n', '\n\n');
        }
      }
      if (_activeCardPath == null) {
        f.writeAsStringSync(text);
        return;
      }
      // 读取角色卡人设字段
      final cardFile = File(_activeCardPath!);
      final card = json.decode(cardFile.readAsStringSync()) as Map<String, dynamic>;
      final data = (card['data'] is Map) ? card['data'] as Map<String, dynamic> : card;
      final name = (data['name'] ?? _activeCardName ?? '角色').toString();
      final desc = (data['description'] ?? '').toString();
      final personality = (data['personality'] ?? '').toString();
      final scenario = (data['scenario'] ?? '').toString();
      final firstMes = (data['first_mes'] ?? '').toString();

      final promptLines = <String>[
        '你是「$name」。请完全沉浸在角色扮演中，始终以 $name 的身份与用户对话。',
        if (desc.isNotEmpty) ...['', '【角色设定】', desc],
        if (personality.isNotEmpty) ...['', '【性格特征】', personality],
        if (scenario.isNotEmpty) ...['', '【当前场景】', scenario],
        if (firstMes.isNotEmpty) ...['', '【开场白参考】', firstMes],
        '',
        '【扮演规则】',
        '- 永远保持 $name 的身份、语气和性格，不要跳出角色。',
        '- 说话自然生动，符合角色人设，不要使用助手式的口吻。',
        '- 不讨论扮演本身，除非用户明确要求。',
      ];
      final prefix = promptLines.join('\n');
      // YAML 块标量：每行缩进 16 格（patch 内 persona.prefix 层级）
      final yamlPrefix = prefix.split('\n').map((l) => l.isEmpty ? '' : '                $l').join('\n');

      final block = [
        marker,
        '    # 由酒馆设定页自动生成：当前装配角色卡 → 官方 Agent 预设',
        '    - id: preset-tavern-card',
        "      name: '@deepseek-ai/dsh-agent-preset'",
        '      config:',
        '        id: tavern-card',
        '        name: 酒馆·$name',
        '        description: 角色卡扮演：$name。只有人设，没有工具。',
        '        order: 92',
        '        plugins:',
        '          - id: persona',
        "            name: '@deepseek-ai/dsh-persona'",
        '            config:',
        '              complete: true',
        '              includeRuntimeContext: false',
        '              prefix: |-$yamlPrefix',
        '          - id: compaction',
        '            name: cordis:group',
        '            group: true',
        '            isolate:',
        '              compaction: true',
        '            config:',
        '              - id: compaction-basic',
        "                name: '@deepseek-ai/dsh-compaction-basic'",
        '              - id: command-compact',
        "                name: '@deepseek-ai/dsh-command-compact'",
        endMarker,
      ].join('\n');
      text = '$text\n$block\n';
      f.writeAsStringSync(text);
    } catch (_) {
      // 预设注入失败不影响装配本身
    }
  }

  void _openCardDetail(String path) {
    try {
      final f = File(path);
      final d = json.decode(f.readAsStringSync());
      if (d is Map) {
        setState(() {
          _viewingCardPath = path;
          _viewingCard = Map<String, dynamic>.from(d);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('读取角色卡失败: $e')));
    }
  }

  Widget _buildCardDetailView() {
    final d = _viewingCard!;
    final cardData = (d['data'] is Map) ? d['data'] : d;
    final name = cardData['name']?.toString() ?? '未知角色';
    final desc = cardData['description']?.toString() ?? '';
    final personality = cardData['personality']?.toString() ?? '';
    final firstMes = cardData['first_mes']?.toString() ?? '';
    final bool hasBook = cardData.containsKey('character_book') && cardData['character_book'] is Map;
    final bookData = hasBook ? cardData['character_book'] : null;
    final entries = (bookData != null && bookData['entries'] is List) ? (bookData['entries'] as List) : [];

    final isEquipped = _activeCardPath == _viewingCardPath;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _viewingCard = null),
            ),
            Expanded(
              child: Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            FilledButton(
              onPressed: () => _equipCard(_viewingCardPath!, name, hasBook),
              child: Text(isEquipped ? '卸下角色' : '装配此角色'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('角色人设与性格：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(personality.isNotEmpty ? personality : (desc.isNotEmpty ? desc : '无描述'), style: const TextStyle(fontSize: 13)),
                if (firstMes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('开场问候语 (First Message)：', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(firstMes, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: Colors.indigo.withOpacity(0.05),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.indigo.withOpacity(0.3), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('专属世界书 (${entries.length} 条)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (hasBook)
                      FilledButton.tonal(
                        onPressed: () {
                          // 将内嵌世界书转入世界书编辑模式
                          setState(() {
                            _editingBookPath = _viewingCardPath;
                            _editingBook = Map<String, dynamic>.from(bookData);
                            _viewingCard = null;
                            _tabController.animateTo(1); // 切换到世界书页
                          });
                        },
                        child: const Text('管理/编辑词条'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(hasBook ? '该角色卡内嵌了 ${entries.length} 条世界书背景设定。装配该角色时会自动绑定此世界书。' : '该角色卡无内嵌世界书，可在下方「绑定外部世界书」选择外部世界书联动。', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('绑定外部独立世界书：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('如果不使用内嵌世界书，或者想挂载额外的世界观，可以直接在已扫描到的外部世界书中选择一本绑定：', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                if (_bookFiles.isEmpty)
                  const Text('暂无独立世界书文件', style: TextStyle(color: Colors.grey))
                else
                  ..._bookFiles.map((b) {
                    final isBound = _activeBookPath == b.path;
                    final bName = b.path.split('/').last;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.menu_book),
                      title: Text(bName),
                      trailing: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: isBound ? Colors.green.withOpacity(0.15) : null,
                          foregroundColor: isBound ? Colors.green[800] : null,
                        ),
                        onPressed: () {
                          setState(() {
                            if (isBound) {
                              _activeBookPath = null;
                              _activeBookName = null;
                            } else {
                              _activeBookPath = b.path;
                              _activeBookName = bName;
                            }
                          });
                          _saveConfig();
                        },
                        child: Text(isBound ? '已绑定' : '绑定此书'),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ================= 2. 独立世界书管理 =================
  Widget _buildWorldBookTab() {
    if (_editingBook != null) {
      final entriesRaw = _editingBook!['entries'];
      List<dynamic> entries = [];
      if (entriesRaw is List) {
        entries = entriesRaw;
      } else if (entriesRaw is Map) {
        entries = entriesRaw.values.toList();
      }

      final isBookActive = _activeBookPath == _editingBookPath;

      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _editingBook = null),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_editingBookPath?.split('/').last}',
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
                  onPressed: () {
                    setState(() {
                      if (isBookActive) {
                        _activeBookPath = null;
                        _activeBookName = null;
                      } else {
                        _activeBookPath = _editingBookPath;
                        _activeBookName = _editingBookPath!.split('/').last;
                      }
                    });
                    _saveConfig();
                  },
                  child: Text(isBookActive ? '卸载' : '装载生效'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('保存'),
                  onPressed: _saveEditingBook,
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
                        _activeBookPath != null ? '当前装载世界书：${_activeBookName ?? ""}' : '当前未装载任何世界书',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _activeBookPath != null ? _activeBookPath!.split('/').last : '可从下方列表或角色卡内嵌中选择装载',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                if (_activeBookPath != null)
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() {
                        _activeBookPath = null;
                        _activeBookName = null;
                      });
                      _saveConfig();
                    },
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
                label: const Text('路径导入世界书'),
                onPressed: () => _openPathImportDialog(isCard: false),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新本地扫描',
              onPressed: _scanFiles,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('手机扫描到的独立世界书列表：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (_bookFiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('未扫描到独立世界书')),
          )
        else
          ..._bookFiles.map((f) {
            final isActive = _activeBookPath == f.path;
            final name = f.path.split('/').last;
            return Card(
              elevation: isActive ? 2 : 1,
              child: ListTile(
                leading: Icon(Icons.menu_book, color: isActive ? Colors.green : null),
                title: Text(name, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(isActive ? '【当前使用中】' : f.path),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: isActive ? Colors.green.withOpacity(0.15) : null,
                        foregroundColor: isActive ? Colors.green[800] : null,
                      ),
                      onPressed: () {
                        setState(() {
                          if (isActive) {
                            _activeBookPath = null;
                            _activeBookName = null;
                          } else {
                            _activeBookPath = f.path;
                            _activeBookName = name;
                          }
                        });
                        _saveConfig();
                      },
                      child: Text(isActive ? '使用中' : '装载'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: '删除此文件',
                      onPressed: () => _deleteFile(f.path, isCard: false),
                    ),
                  ],
                ),
                onTap: () => _openBookForEditing(f.path),
              ),
            );
          }),
      ],
    );
  }

  void _openBookForEditing(String path) {
    try {
      final f = File(path);
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
          _editingBookPath = path;
          _editingBook = bookData;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打开世界书失败: $e')));
    }
  }

  void _saveEditingBook() {
    if (_editingBookPath != null && _editingBook != null) {
      try {
        final f = File(_editingBookPath!);
        final raw = f.readAsStringSync();
        final decoded = json.decode(raw);

        // 如果是内嵌在角色卡中的世界书，写回角色卡的 character_book 节点
        if (decoded is Map && decoded.containsKey('data') && decoded['data'] is Map && (decoded['data'] as Map).containsKey('character_book')) {
          decoded['data']['character_book'] = _editingBook;
          f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(decoded));
        } else if (decoded is Map && decoded.containsKey('character_book')) {
          decoded['character_book'] = _editingBook;
          f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(decoded));
        } else {
          // 普通独立世界书
          f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_editingBook));
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功！')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  void _deleteFile(String path, {required bool isCard}) {
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
                if (f.existsSync()) f.deleteSync();
                if (_activeBookPath == path) {
                  _activeBookPath = null;
                  _activeBookName = null;
                }
                if (_activeCardPath == path) {
                  _activeCardPath = null;
                  _activeCardName = null;
                }
                _saveConfig(notify: false);
                _scanFiles();
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

  void _openPathImportDialog({required bool isCard}) {
    final ctrl = TextEditingController(text: '/sdcard/Download/');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCard ? '输入角色卡路径导入' : '输入世界书路径导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('可输入手机内任意 JSON ${isCard ? "角色卡 (含人设/开场白)" : "世界书"} 绝对路径：', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '/sdcard/Download/xxx.json'),
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
                if (isCard) {
                  _openCardDetail(p);
                } else {
                  _openBookForEditing(p);
                }
              }
            },
            child: const Text('导入读取'),
          ),
        ],
      ),
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

  // ================= 3. 自导入硬锁 =================
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

  // ================= 4. 预设正则 =================
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
  // ================= 酒馆式角色卡新建 / 编辑 =================
  static const _cardsDir = '/sdcard/Download/st/cards';
  void _openCardEditor(String? editPath) {
    Map<String, dynamic> cardData = {};
    if (editPath != null) {
      try {
        final d = json.decode(File(editPath).readAsStringSync());
        cardData = Map<String, dynamic>.from((d['data'] is Map) ? d['data'] : d);
      } catch (_) {}
    }
    final nameCtrl = TextEditingController(text: cardData['name']?.toString() ?? '');
    final descCtrl = TextEditingController(text: cardData['description']?.toString() ?? '');
    final personalityCtrl = TextEditingController(text: cardData['personality']?.toString() ?? '');
    final scenarioCtrl = TextEditingController(text: cardData['scenario']?.toString() ?? '');
    final firstMesCtrl = TextEditingController(text: cardData['first_mes']?.toString() ?? '');
    final mesExampleCtrl = TextEditingController(text: cardData['mes_example']?.toString() ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) => Scaffold(
            appBar: AppBar(
              title: Text(editPath == null ? '新建角色卡' : '编辑角色卡'),
              actions: [
                TextButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('角色名不能为空')));
                      return;
                    }
                    final name = nameCtrl.text.trim();
                    final spec = {
                      'spec': 'chara_card_v2',
                      'spec_version': '2.0',
                      'data': {
                        'name': name,
                        'description': descCtrl.text.trim(),
                        'personality': personalityCtrl.text.trim(),
                        'scenario': scenarioCtrl.text.trim(),
                        'first_mes': firstMesCtrl.text.trim(),
                        'mes_example': mesExampleCtrl.text.trim(),
                        'character_book': {
                          'entries': (cardData['character_book'] is Map &&
                                  (cardData['character_book'] as Map)['entries'] is List)
                              ? (cardData['character_book'] as Map)['entries']
                              : [],
                        },
                      },
                    };
                    try {
                      Directory(_cardsDir).createSync(recursive: true);
                      final safe = name.replaceAll(RegExp(r'\w\u4e00-\u9fa5-'), '_');
                      final outPath = editPath ?? '$_cardsDir/${safe}_spec_v2.json';
                      File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(spec));
                      if (mounted) Navigator.pop(ctx);
                      _scanFiles();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('角色卡「$name」已保存！')));
                    } catch (e) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('保存失败: $e')));
                    }
                  },
                  child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            body: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '角色名 *', border: OutlineInputBorder(), hintText: '例如：曜'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: '角色设定（背景、身份、外貌等）', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: personalityCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '性格特征', alignLabelWithHint: true, border: OutlineInputBorder(), hintText: '例如：冷静、话少、外冷内热'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: scenarioCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '当前场景', alignLabelWithHint: true, border: OutlineInputBorder(), hintText: '例如：深夜的观测站，两人刚刚汇合'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: firstMesCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: '开场白（First Message）', alignLabelWithHint: true, border: OutlineInputBorder(), hintText: '角色的第一句话，决定整个对话的基调'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mesExampleCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '对话示例（可选）', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Text('提示：编辑已有角色卡时，其内嵌世界书词条会原样保留。', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
