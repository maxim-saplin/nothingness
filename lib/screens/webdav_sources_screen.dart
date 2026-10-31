import 'package:flutter/material.dart';

import '../models/webdav_source.dart';
import '../services/webdav_library_service.dart';
import '../services/webdav_client.dart';

class WebDavSourcesScreen extends StatefulWidget {
  const WebDavSourcesScreen({super.key, this.service});

  final WebDavLibraryService? service;

  static Future<void> push(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const WebDavSourcesScreen()));

  @override
  State<WebDavSourcesScreen> createState() => _WebDavSourcesScreenState();
}

class _WebDavSourcesScreenState extends State<WebDavSourcesScreen> {
  late final WebDavLibraryService _service;
  int _cacheLimitMiB = 512;
  int _preloadCount = WebDavLibraryService.defaultPreloadCount;
  bool _loading = true;
  late Future<(int, int)> _statsFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WebDavLibraryService.instance;
    _statsFuture = _readStats();
    _service.snapshotRevisionNotifier.addListener(_refreshStats);
    _service.cacheRevisionNotifier.addListener(_refreshStats);
    _load();
  }

  Future<(int, int)> _readStats() => Future.wait([
    _service.snapshotSizeBytes(),
    _service.audioCacheSizeBytes(),
  ]).then((sizes) => (sizes[0], sizes[1]));

  void _refreshStats() {
    if (mounted) {
      setState(() {
        _statsFuture = _readStats();
      });
    }
  }

  @override
  void dispose() {
    _service.snapshotRevisionNotifier.removeListener(_refreshStats);
    _service.cacheRevisionNotifier.removeListener(_refreshStats);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _service.init();
      if (!mounted) return;
      setState(() {
        _cacheLimitMiB = (_service.cacheLimitBytes / (1024 * 1024))
            .round()
            .clamp(64, 4096)
            .toInt();
        _preloadCount = _service.preloadCountNotifier.value;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addSource() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddWebDavSourceDialog(service: _service),
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV source added; indexing started.')),
      );
    }
  }

  Future<void> _removeSource(WebDavSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove source?'),
        content: Text('Remove ${source.name} and its local snapshot?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _service.removeSource(source.id);
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear downloaded audio?'),
        content: const Text(
          'This removes unused local audio files. The metadata snapshot and '
          'currently playing or preloaded tracks are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _service.clearUnusedAudioCache();
  }

  Future<void> _setPreloadCount(int count) async {
    try {
      await _service.setPreloadCount(count);
    } catch (error) {
      if (!mounted) return;
      setState(() => _preloadCount = _service.preloadCountNotifier.value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save preload setting: $error')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KiB';
    final mebibytes = bytes / (1024 * 1024);
    if (mebibytes < 1024) return '${mebibytes.toStringAsFixed(1)} MiB';
    return '${(mebibytes / 1024).toStringAsFixed(2)} GiB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV libraries'),
        actions: [
          IconButton(
            key: const ValueKey('webdav-add-source'),
            onPressed: _loading ? null : _addSource,
            tooltip: 'Add source',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: Listenable.merge([
                _service.sourcesNotifier,
                _service.syncProgressNotifier,
                _service.transferProgressNotifier,
                _service.snapshotRevisionNotifier,
                _service.cacheRevisionNotifier,
              ]),
              builder: (context, _) {
                final sources = _service.sources;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Text(
                      'A local metadata snapshot enables offline browsing. Audio '
                      'is downloaded when selected and kept in a separate cache.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (sources.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No WebDAV sources configured.'),
                        ),
                      ),
                    for (final source in sources) _sourceCard(source, theme),
                    const SizedBox(height: 20),
                    Text('LOCAL STORAGE', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _storageStats(theme),
                    const SizedBox(height: 16),
                    Text('Upcoming tracks to preload: $_preloadCount'),
                    Slider(
                      key: const ValueKey('webdav-preload-count'),
                      value: _preloadCount.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$_preloadCount',
                      onChanged: (value) =>
                          setState(() => _preloadCount = value.round()),
                      onChangeEnd: (value) => _setPreloadCount(value.round()),
                    ),
                    Text('Downloaded audio limit: $_cacheLimitMiB MiB'),
                    Slider(
                      key: const ValueKey('webdav-cache-limit'),
                      value: _cacheLimitMiB.toDouble().clamp(64, 4096),
                      min: 64,
                      max: 4096,
                      divisions: 63,
                      label: '$_cacheLimitMiB MiB',
                      onChanged: (value) => setState(
                        () => _cacheLimitMiB = (value / 64).round() * 64,
                      ),
                      onChangeEnd: (value) =>
                          _service.setCacheLimitMiB((value / 64).round() * 64),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const ValueKey('webdav-clear-cache'),
                        onPressed: _clearCache,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear unused audio cache'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'App passwords are stored in secure system storage. '
                        'Remote files are not modified.',
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _sourceCard(WebDavSource source, ThemeData theme) {
    final progress = _service.syncProgressNotifier.value[source.id];
    final transfers = _service.transferProgressNotifier.value.entries
        .where((entry) => entry.key.startsWith('webdav://${source.id}/'))
        .map((entry) => entry.value)
        .toList(growable: false);
    final transfer = transfers.isEmpty ? null : transfers.first;
    return Card(
      key: ValueKey('webdav-source-${source.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(source.name, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  key: ValueKey('webdav-refresh-${source.id}'),
                  tooltip: 'Refresh index',
                  onPressed: progress?.isComplete == false
                      ? null
                      : () => _service
                            .refreshSource(source.id)
                            .catchError((_) {}),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  key: ValueKey('webdav-remove-${source.id}'),
                  tooltip: 'Remove source',
                  onPressed: () => _removeSource(source),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Text(
              '${source.serverUrl} · ${source.folderPath}',
              style: theme.textTheme.bodySmall,
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              if (!progress.isComplete) const LinearProgressIndicator(),
              Text(
                progress.error ??
                    (progress.isComplete
                        ? 'Index ready'
                        : 'Indexing: ${progress.foldersScanned} folders, '
                              '${progress.tracksIndexed} audio files checked'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: progress.error == null
                      ? null
                      : theme.colorScheme.error,
                ),
              ),
            ],
            if (transfer != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: transfer.fraction),
              Text(
                '${transfer.isPreload ? 'Preloading' : 'Downloading'}: '
                '${_formatBytes(transfer.bytesReceived)}'
                '${transfer.totalBytes == null ? '' : ' / ${_formatBytes(transfer.totalBytes!)}'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _storageStats(ThemeData theme) => FutureBuilder<(int, int)>(
    future: _statsFuture,
    builder: (context, snapshot) {
      final sizes = snapshot.data;
      return Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Metadata snapshot'),
            subtitle: const Text('Directory and filename data only'),
            trailing: Text(
              sizes == null ? '—' : _formatBytes(sizes.$1),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Downloaded audio'),
            subtitle: const Text('Current/next tracks are pinned'),
            trailing: Text(
              sizes == null ? '—' : _formatBytes(sizes.$2),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    },
  );
}

class _AddWebDavSourceDialog extends StatefulWidget {
  const _AddWebDavSourceDialog({required this.service});

  final WebDavLibraryService service;

  @override
  State<_AddWebDavSourceDialog> createState() => _AddWebDavSourceDialogState();
}

class _AddWebDavSourceDialogState extends State<_AddWebDavSourceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _folder = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _folder.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.addSource(
        name: _name.text,
        serverUrl: _server.text,
        username: _username.text,
        appPassword: _password.text,
        folderPath: _folder.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (error) {
          WebDavException() => error.toString(),
          FormatException() => 'Use an HTTPS server URL and a valid folder path.',
          _ => 'Could not connect. Check the server, folder, and app password.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add WebDAV source'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('webdav-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextFormField(
                key: const ValueKey('webdav-server'),
                controller: _server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Nextcloud server URL',
                  hintText: 'https://cloud.example.com',
                ),
                validator: _required,
              ),
              TextFormField(
                key: const ValueKey('webdav-username'),
                controller: _username,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: _required,
                autocorrect: false,
              ),
              TextFormField(
                key: const ValueKey('webdav-password'),
                controller: _password,
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Nextcloud app password',
                ),
                validator: _required,
                autocorrect: false,
              ),
              TextFormField(
                key: const ValueKey('webdav-folder'),
                controller: _folder,
                decoration: const InputDecoration(
                  labelText: 'Folder path inside your account',
                  hintText: 'Music',
                ),
                autocorrect: false,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Create an app password in Nextcloud. The password is stored '
                'in secure device storage and is never included in the library snapshot.',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('webdav-save-source'),
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Connect'),
      ),
    ],
  );
}
