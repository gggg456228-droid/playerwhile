import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(620, 780),
      minimumSize: Size(480, 620),
      center: true,
      alwaysOnTop: true,
      title: 'PlayerWhile',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const PlayerWhileApp());
}

class PlayerWhileApp extends StatelessWidget {
  const PlayerWhileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PlayerWhile',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B7CFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0C0C10),
        cardTheme: const CardThemeData(
          color: Color(0xFF15151C),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF121218),
          border: OutlineInputBorder(),
        ),
        useMaterial3: true,
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

class _HomePageState extends State<HomePage> {
  final store = CharacterStore();
  List<InstalledCharacter> installed = [];
  bool loading = true;
  bool alwaysOnTop = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final values = await store.loadIndex();
    if (!mounted) return;
    setState(() {
      installed = values;
      loading = false;
    });
  }

  Future<void> _openUpdater() async {
    if (isDesktop) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: SizedBox(
            width: 760,
            height: 720,
            child: UpdaterPanel(store: store, onChanged: _reload),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: const Color(0xFF111117),
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.94,
          child: UpdaterPanel(store: store, onChanged: _reload),
        ),
      );
    }
  }

  Future<void> _toggleTop() async {
    if (!isDesktop) return;
    alwaysOnTop = !alwaysOnTop;
    await windowManager.setAlwaysOnTop(alwaysOnTop);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PLAYERWHILE', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (isDesktop)
            IconButton(
              tooltip: alwaysOnTop ? 'Открепить окно' : 'Поверх окон',
              onPressed: _toggleTop,
              icon: Icon(alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined),
            ),
          IconButton(
            tooltip: 'GitHub обновление',
            onPressed: _openUpdater,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openUpdater,
        icon: const Icon(Icons.link),
        label: const Text('GitHub'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : installed.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: installed.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _installedCard(installed[i]),
                  ),
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_2_outlined, size: 58, color: Colors.white54),
            const SizedBox(height: 16),
            const Text('Персонажей пока нет', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Нажми GitHub, вставь ссылку на репозиторий и выбери персонажа из списка.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _openUpdater, icon: const Icon(Icons.link), label: const Text('Открыть обновление')),
          ],
        ),
      ),
    );
  }

  Widget _installedCard(InstalledCharacter item) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${item.owner}/${item.repo}\n${item.path}\n${item.updatedAtLocal}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Обновить из GitHub',
          onPressed: () => _updateInstalled(item),
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }

  Future<void> _updateInstalled(InstalledCharacter item) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Обновляю ${item.name}...')));
    try {
      final source = GitHubSource(
        owner: item.owner,
        repo: item.repo,
        branch: item.branch,
        basePath: '',
        originalUrl: item.sourceUrl,
      );
      final loader = GitHubLoader();
      final repo = await loader.load(source);
      final match = repo.candidates.where((e) => e.path == item.path).toList();
      if (match.isEmpty) throw Exception('Персонаж больше не найден в репозитории');
      await store.install(repo.source, match.first, loader);
      await _reload();
      messenger.showSnackBar(SnackBar(content: Text('${item.name} обновлён')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ошибка: ${cleanError(e)}')));
    }
  }
}

class UpdaterPanel extends StatefulWidget {
  final CharacterStore store;
  final Future<void> Function() onChanged;

  const UpdaterPanel({super.key, required this.store, required this.onChanged});

  @override
  State<UpdaterPanel> createState() => _UpdaterPanelState();
}

class _UpdaterPanelState extends State<UpdaterPanel> {
  final controller = TextEditingController();
  final searchController = TextEditingController();
  final loader = GitHubLoader();
  RepositorySnapshot? snapshot;
  bool loading = false;
  String? error;
  String query = '';
  final Map<String, bool> updating = {};

  @override
  void dispose() {
    controller.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) controller.text = data!.text!.trim();
  }

  Future<void> _load() async {
    FocusScope.of(context).unfocus();
    setState(() {
      loading = true;
      error = null;
      snapshot = null;
    });
    try {
      final source = GitHubSource.parse(controller.text);
      final result = await loader.load(source);
      if (!mounted) return;
      setState(() => snapshot = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _install(CharacterCandidate candidate) async {
    final snap = snapshot;
    if (snap == null) return;
    setState(() => updating[candidate.path] = true);
    try {
      await widget.store.install(snap.source, candidate, loader);
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${candidate.name} обновлён')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${cleanError(e)}')));
    } finally {
      if (mounted) setState(() => updating[candidate.path] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = snapshot?.candidates ?? const <CharacterCandidate>[];
    final filtered = query.trim().isEmpty
        ? all
        : all.where((e) => '${e.name} ${e.path}'.toLowerCase().contains(query.toLowerCase())).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Text('GitHub персонажи', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _load(),
                  decoration: const InputDecoration(hintText: 'https://github.com/user/repo', prefixIcon: Icon(Icons.link)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _paste, tooltip: 'Вставить', icon: const Icon(Icons.content_paste)),
              const SizedBox(width: 8),
              FilledButton(onPressed: loading ? null : _load, child: loading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Загрузить')),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          ],
          if (snapshot != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${snapshot!.source.owner}/${snapshot!.source.repo}  •  ${snapshot!.source.branch}  •  ${all.length} персонажей',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: searchController,
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(hintText: 'Поиск персонажа', prefixIcon: Icon(Icons.search), isDense: true),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: snapshot == null
                ? const Center(child: Text('Вставь ссылку на GitHub', style: TextStyle(color: Colors.white38)))
                : filtered.isEmpty
                    ? const Center(child: Text('Персонажи не найдены', style: TextStyle(color: Colors.white54)))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = filtered[i];
                          final busy = updating[item.path] == true;
                          return ListTile(
                            leading: Icon(item.isFolder ? Icons.folder_copy_outlined : Icons.description_outlined),
                            title: Text(item.name),
                            subtitle: Text('${item.path}  •  ${item.files.length} файл${item.files.length == 1 ? '' : 'ов'}', maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: FilledButton.tonalIcon(
                              onPressed: busy ? null : () => _install(item),
                              icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update_alt, size: 18),
                              label: const Text('Обновить'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class GitHubSource {
  final String owner;
  final String repo;
  final String branch;
  final String basePath;
  final String originalUrl;

  const GitHubSource({required this.owner, required this.repo, required this.branch, required this.basePath, required this.originalUrl});

  factory GitHubSource.parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) throw FormatException('Вставь ссылку GitHub');
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.parse(text);
    if (uri.host.toLowerCase() != 'github.com') throw FormatException('Нужна ссылка github.com');
    final parts = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) throw FormatException('Ссылка должна вести на репозиторий');
    final owner = parts[0];
    final repo = parts[1].replaceAll(RegExp(r'\.git$'), '');
    var branch = '';
    var base = '';
    if (parts.length >= 4 && (parts[2] == 'tree' || parts[2] == 'blob')) {
      branch = parts[3];
      if (parts.length > 4) base = parts.sublist(4).join('/');
      if (parts[2] == 'blob' && base.contains('/')) base = p.posix.dirname(base);
    }
    return GitHubSource(owner: owner, repo: repo, branch: branch, basePath: base == '.' ? '' : base, originalUrl: raw.trim());
  }

  GitHubSource resolved(String resolvedBranch) => GitHubSource(owner: owner, repo: repo, branch: resolvedBranch, basePath: basePath, originalUrl: originalUrl);
}

class RepoFile {
  final String path;
  final String sha;
  final int size;

  const RepoFile({required this.path, required this.sha, required this.size});
}

class CharacterCandidate {
  final String name;
  final String path;
  final bool isFolder;
  final List<RepoFile> files;

  const CharacterCandidate({required this.name, required this.path, required this.isFolder, required this.files});
}

class RepositorySnapshot {
  final GitHubSource source;
  final List<CharacterCandidate> candidates;

  const RepositorySnapshot({required this.source, required this.candidates});
}

class GitHubLoader {
  final client = http.Client();

  Map<String, String> get headers => const {'Accept': 'application/vnd.github+json', 'User-Agent': 'PlayerWhile'};

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode == 403 && response.headers['x-ratelimit-remaining'] == '0') {
      throw Exception('GitHub временно ограничил анонимные запросы. Попробуй позже.');
    }
    if (response.statusCode == 404) throw Exception('Репозиторий или ветка не найдены. Приватные репозитории без токена не читаются.');
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('GitHub ответил ${response.statusCode}');
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, dynamic>) throw Exception('Неожиданный ответ GitHub');
    return value;
  }

  Future<RepositorySnapshot> load(GitHubSource input) async {
    final repoMeta = await _json(Uri.https('api.github.com', '/repos/${input.owner}/${input.repo}'));
    final branch = input.branch.isEmpty ? (repoMeta['default_branch'] as String? ?? 'main') : input.branch;
    final branchMeta = await _json(Uri.https('api.github.com', '/repos/${input.owner}/${input.repo}/branches/${Uri.encodeComponent(branch)}'));
    final commit = branchMeta['commit'] as Map<String, dynamic>?;
    final commitDetail = commit?['commit'] as Map<String, dynamic>?;
    final tree = commitDetail?['tree'] as Map<String, dynamic>?;
    final treeSha = tree?['sha'] as String?;
    if (treeSha == null) throw Exception('Не удалось определить дерево репозитория');
    final treeJson = await _json(Uri.https('api.github.com', '/repos/${input.owner}/${input.repo}/git/trees/$treeSha', {'recursive': '1'}));
    if (treeJson['truncated'] == true) throw Exception('Репозиторий слишком большой для полного списка GitHub API');
    final rawTree = treeJson['tree'] as List<dynamic>? ?? const [];
    final files = <RepoFile>[];
    for (final entry in rawTree) {
      if (entry is! Map<String, dynamic> || entry['type'] != 'blob') continue;
      final path = entry['path'] as String?;
      final sha = entry['sha'] as String?;
      if (path == null || sha == null) continue;
      if (input.basePath.isNotEmpty && path != input.basePath && !path.startsWith('${input.basePath}/')) continue;
      files.add(RepoFile(path: path, sha: sha, size: (entry['size'] as num?)?.toInt() ?? 0));
    }
    final source = input.resolved(branch);
    return RepositorySnapshot(source: source, candidates: discoverCharacters(files, input.basePath));
  }

  Future<List<int>> downloadBlob(GitHubSource source, RepoFile file) async {
    final value = await _json(Uri.https('api.github.com', '/repos/${source.owner}/${source.repo}/git/blobs/${file.sha}'));
    final encoding = value['encoding'];
    final content = value['content'] as String? ?? '';
    if (encoding != 'base64') throw Exception('GitHub вернул неподдерживаемую кодировку');
    return base64.decode(content.replaceAll('\n', ''));
  }
}

List<CharacterCandidate> discoverCharacters(List<RepoFile> files, String basePath) {
  const roots = {'characters', 'character', 'players', 'sheets', 'profiles', 'персонажи'};
  const sentinels = {'character.json', 'character.yaml', 'character.yml', 'sheet.json', 'sheet.yaml', 'sheet.yml', 'profile.json', 'profile.yaml', 'profile.yml', 'character.md', 'sheet.md'};
  const extensions = {'.json', '.yaml', '.yml', '.toml', '.md', '.txt'};
  final groups = <String, List<RepoFile>>{};
  final names = <String, String>{};

  for (final file in files) {
    final rel = basePath.isNotEmpty && file.path.startsWith('$basePath/') ? file.path.substring(basePath.length + 1) : file.path;
    final parts = p.posix.split(rel);
    final rootIndex = parts.indexWhere((e) => roots.contains(e.toLowerCase()));
    if (rootIndex >= 0 && rootIndex + 1 < parts.length) {
      final first = parts[rootIndex + 1];
      final isDirectFile = rootIndex + 1 == parts.length - 1;
      if (isDirectFile) {
        if (extensions.contains(p.extension(first).toLowerCase())) {
          groups[file.path] = [file];
          names[file.path] = p.basenameWithoutExtension(first);
        }
      } else {
        final prefixParts = parts.take(rootIndex + 2).toList();
        final relPrefix = p.posix.joinAll(prefixParts);
        final fullPrefix = basePath.isEmpty ? relPrefix : p.posix.join(basePath, relPrefix);
        groups.putIfAbsent(fullPrefix, () => []).add(file);
        names[fullPrefix] = first;
      }
    }
  }

  if (groups.isEmpty) {
    final sentinelDirs = <String>{};
    for (final file in files) {
      if (sentinels.contains(p.posix.basename(file.path).toLowerCase())) sentinelDirs.add(p.posix.dirname(file.path));
    }
    for (final dir in sentinelDirs) {
      final list = files.where((f) => f.path == dir || f.path.startsWith('$dir/')).toList();
      groups[dir] = list;
      names[dir] = p.posix.basename(dir);
    }
  }

  if (groups.isEmpty) {
    for (final file in files) {
      if (!extensions.contains(p.extension(file.path).toLowerCase())) continue;
      groups[file.path] = [file];
      names[file.path] = p.basenameWithoutExtension(file.path);
    }
  }

  final result = groups.entries
      .map((e) => CharacterCandidate(name: names[e.key] ?? p.posix.basename(e.key), path: e.key, isFolder: e.value.length > 1 || !p.posix.basename(e.key).contains('.'), files: e.value..sort((a, b) => a.path.compareTo(b.path))))
      .toList();
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

class InstalledCharacter {
  final String name;
  final String owner;
  final String repo;
  final String branch;
  final String path;
  final String sourceUrl;
  final String updatedAt;
  final int fileCount;

  const InstalledCharacter({required this.name, required this.owner, required this.repo, required this.branch, required this.path, required this.sourceUrl, required this.updatedAt, required this.fileCount});

  String get key => '$owner/$repo@$branch:$path';
  String get updatedAtLocal {
    final dt = DateTime.tryParse(updatedAt)?.toLocal();
    if (dt == null) return updatedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Map<String, dynamic> toJson() => {'name': name, 'owner': owner, 'repo': repo, 'branch': branch, 'path': path, 'sourceUrl': sourceUrl, 'updatedAt': updatedAt, 'fileCount': fileCount};

  factory InstalledCharacter.fromJson(Map<String, dynamic> j) => InstalledCharacter(
        name: j['name'] as String? ?? '',
        owner: j['owner'] as String? ?? '',
        repo: j['repo'] as String? ?? '',
        branch: j['branch'] as String? ?? 'main',
        path: j['path'] as String? ?? '',
        sourceUrl: j['sourceUrl'] as String? ?? '',
        updatedAt: j['updatedAt'] as String? ?? '',
        fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
      );
}

class CharacterStore {
  Future<Directory> root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'PlayerWhile'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> indexFile() async => File(p.join((await root()).path, 'characters.json'));

  Future<List<InstalledCharacter>> loadIndex() async {
    try {
      final file = await indexFile();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final list = decoded.whereType<Map>().map((e) => InstalledCharacter.fromJson(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveIndex(List<InstalledCharacter> values) async {
    final file = await indexFile();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(values.map((e) => e.toJson()).toList()), flush: true);
  }

  String safe(String value) {
    var out = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    if (out.isEmpty) out = 'character';
    return out.length > 80 ? out.substring(0, 80) : out;
  }

  Future<void> install(GitHubSource source, CharacterCandidate candidate, GitHubLoader loader) async {
    final base = await root();
    final folderName = safe('${candidate.name}__${source.owner}_${source.repo}');
    final destination = Directory(p.join(base.path, 'characters', folderName));
    final temp = Directory('${destination.path}.updating');
    if (await temp.exists()) await temp.delete(recursive: true);
    await temp.create(recursive: true);

    for (final file in candidate.files) {
      final bytes = await loader.downloadBlob(source, file);
      String relative;
      if (candidate.isFolder && file.path.startsWith('${candidate.path}/')) {
        relative = file.path.substring(candidate.path.length + 1);
      } else {
        relative = p.posix.basename(file.path);
      }
      final output = File(p.joinAll([temp.path, ...p.posix.split(relative)]));
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes, flush: true);
    }

    if (await destination.exists()) await destination.delete(recursive: true);
    await temp.rename(destination.path);

    final current = await loadIndex();
    final updated = InstalledCharacter(
      name: candidate.name,
      owner: source.owner,
      repo: source.repo,
      branch: source.branch,
      path: candidate.path,
      sourceUrl: source.originalUrl,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      fileCount: candidate.files.length,
    );
    current.removeWhere((e) => e.key == updated.key);
    current.add(updated);
    await _saveIndex(current);
  }
}

String cleanError(Object error) {
  var text = error.toString();
  text = text.replaceFirst(RegExp(r'^(Exception|FormatException):\s*'), '');
  return text;
}
