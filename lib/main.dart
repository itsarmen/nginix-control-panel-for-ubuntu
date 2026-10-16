import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart';

String serverIp = '127.0.0.1';

Future<void> detectServerIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    const virtualPrefixes = [
      'docker',
      'br-',
      'veth',
      'virbr',
      'tun',
      'tap',
      'vmnet',
      'dummy',
    ];
    for (final iface in interfaces) {
      if (iface.name == 'lo') continue;
      if (virtualPrefixes.any(iface.name.startsWith)) continue;
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          serverIp = addr.address;
          return;
        }
      }
    }
  } catch (_) {}
}

/// Shows a floating toast notification (bottom-right, rounded, auto-dismiss)
/// instead of the default full-width bottom SnackBar.
void showToast(BuildContext context, String message) =>
    _Toasts.show(context, message);

enum _ToastKind { info, success, error }

class _ToastData {
  _ToastData(this.message, this.kind);

  final String message;
  final _ToastKind kind;
}

class _Toasts {
  static final List<_ToastData> _items = [];
  static OverlayEntry? _entry;

  static void show(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final data = _ToastData(message, _kindFor(message));
    _items.add(data);
    if (_entry == null) {
      final entry = OverlayEntry(
        builder: (_) => _ToastOverlay(items: _items),
      );
      _entry = entry;
      overlay.insert(entry);
    } else {
      _entry!.markNeedsBuild();
    }
    Future.delayed(const Duration(seconds: 4), () => _remove(data));
  }

  static void _remove(_ToastData data) {
    if (!_items.remove(data)) return;
    final entry = _entry;
    if (entry == null) return;
    if (_items.isEmpty) {
      entry.remove();
      _entry = null;
    } else {
      entry.markNeedsBuild();
    }
  }

  static _ToastKind _kindFor(String message) {
    final m = message.toLowerCase();
    const errorWords = [
      'fail',
      'error',
      'could not',
      'cannot',
      'invalid',
      'required',
      'unable',
      'must',
    ];
    const successWords = [
      'saved',
      'complete',
      'success',
      'reloaded',
      'created',
      'restored',
      'enabled',
      'deleted',
      'changed',
      'closed',
      'ok:',
    ];
    if (errorWords.any(m.contains)) return _ToastKind.error;
    if (successWords.any(m.contains)) return _ToastKind.success;
    return _ToastKind.info;
  }
}

class _ToastOverlay extends StatelessWidget {
  const _ToastOverlay({required this.items});

  final List<_ToastData> items;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final item in items) _ToastCard(data: item),
          ],
        ),
      ),
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({required this.data});

  final _ToastData data;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color accent, IconData icon) = switch (widget.data.kind) {
      _ToastKind.error => (const Color(0xFFE5484D), Icons.error_outline),
      _ToastKind.success =>
        (const Color(0xFF30A46C), Icons.check_circle_outline),
      _ToastKind.info => (scheme.primary, Icons.info_outline),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FadeTransition(
        opacity: _c,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              color: scheme.surfaceContainerHighest,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: accent),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.data.message,
                        style: TextStyle(color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YaruWindowTitleBar.ensureInitialized();
  await detectServerIp();
  runApp(const NginixControlPanelApp());
}

class NginixControlPanelApp extends StatefulWidget {
  const NginixControlPanelApp({super.key});

  @override
  State<NginixControlPanelApp> createState() => _NginixControlPanelAppState();
}

class _NginixControlPanelAppState extends State<NginixControlPanelApp> {
  final ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      data: YaruThemeData(themeMode: _themeMode),
      builder: (context, yaru, child) => _Dashboard(
        themeMode: _themeMode,
        lightTheme: yaru.theme,
        darkTheme: yaru.darkTheme,
      ),
    );
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard({
    required this.themeMode,
    this.lightTheme,
    this.darkTheme,
  });

  final ThemeMode themeMode;
  final ThemeData? lightTheme;
  final ThemeData? darkTheme;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ServicesPage(key: PageStorageKey('services')),
      const WebsitesPage(),
      const DatabasesPage(),
      const BackupsPage(),
      const RestorePage(),
      const CronJobsPage(),
      const ConfigsPage(),
      const TerminalPage(),
      const NetworkPage(),
      const FirewallPage(),
    ];

    return MaterialApp(
      title: 'Nginix Control Panel',
      debugShowCheckedModeBanner: false,
      theme: widget.lightTheme,
      darkTheme: widget.darkTheme,
      themeMode: widget.themeMode,
      home: _HomeShell(
        selectedIndex: _selectedIndex,
        onSelected: (i) => setState(() => _selectedIndex = i),
        body: pages[_selectedIndex],
      ),
    );
  }
}

class _HomeShell extends StatelessWidget {
  const _HomeShell({
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: YaruWindowTitleBar(
        centerTitle: false,
leading: Padding(
            padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
            child: SizedBox(
              width: 18,
              height: 18,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: Image.asset(
                  'assets/app-icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nginix Control Panel',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                serverIp,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          YaruNavigationRail(
            length: 10,
            selectedIndex: selectedIndex,
            leading: const SizedBox.shrink(),
            trailing: const SizedBox.shrink(),
            onDestinationSelected: onSelected,
            itemBuilder: (context, index, selected) {
              final items = [
                (Icons.settings_outlined, Icons.settings, 'Services'),
                (Icons.language_outlined, Icons.language, 'Websites'),
                (Icons.storage_outlined, Icons.storage, 'Databases'),
                (Icons.backup_outlined, Icons.backup, 'Backups'),
                (Icons.settings_backup_restore, Icons.settings_backup_restore, 'Restore'),
                (Icons.schedule_outlined, Icons.schedule, 'Cron Jobs'),
                (Icons.code, Icons.code, 'Configs'),
                (Icons.terminal, Icons.terminal, 'Terminal'),
                (Icons.lan_outlined, Icons.lan, 'Network'),
                (Icons.shield_outlined, Icons.shield, 'Firewall'),
              ];
              final icon =
                  selected ? items[index].$2 : items[index].$1;
              return YaruNavigationRailItem(
                selected: selectedIndex == index,
                icon: Icon(icon),
                label: Text(items[index].$3),
                onTap: () => onSelected(index),
                style: YaruNavigationRailStyle.labelled,
              );
            },
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/* ================================================================
   Services
   ================================================================ */

class ServiceInfo {
  final String name;
  final String service;
  const ServiceInfo(this.name, this.service);
}

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  static const services = [
    ServiceInfo('Nginx Web Server', 'nginx'),
    ServiceInfo('MariaDB Database', 'mariadb'),
    ServiceInfo('Cron Scheduler', 'cron'),
    ServiceInfo('UFW Firewall', 'ufw'),
  ];

  final Map<String, bool> _active = {};
  final Map<String, bool> _busy = {};

  @override
  void initState() {
    super.initState();
    for (final s in services) {
      _check(s.service);
    }
  }

  Future<void> _check(String service) async {
    bool active;
    if (service == 'ufw') {
      final r = await Process.run('sudo', ['-n', 'ufw', 'status']);
      active = r.stdout.toString().contains('Status: active');
    } else {
      final r = await Process.run('systemctl', ['is-active', service]);
      active = r.stdout.toString().trim() == 'active';
    }
    if (mounted) setState(() => _active[service] = active);
  }

  void _snack(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  Future<void> _run(String action, String service) async {
    if (mounted) setState(() => _busy[service] = true);
    String? err;
    try {
      final r =
          await Process.run('sudo', ['-n', 'systemctl', action, service]);
      if (r.exitCode != 0) err = '${r.stdout}${r.stderr}'.trim();
    } catch (e) {
      err = '$e';
    }
    await _check(service);
    if (mounted) {
      setState(() => _busy[service] = false);
      if (err != null && err.isNotEmpty) {
        _snack('$action $service failed: $err');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        YaruSection(
          headline: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('System Services',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          child: Column(
            children: [
              for (final (i, service) in services.indexed) ...[
                if (i > 0) const Divider(height: 1),
                _serviceTile(context, service),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        YaruSection(
          headline: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Quick Actions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(context, Icons.refresh, 'Restart All',
                  () => _runAll('restart')),
              _actionButton(context, Icons.language, 'Open Platform',
                  () => _open('https://$serverIp')),
              _actionButton(context, Icons.data_object, 'phpMyAdmin',
                  () => _open('https://127.0.0.1/phpmyadmin')),
              _actionButton(context, Icons.shield, 'Firewall Status',
                  _showFirewall),
              _actionButton(context, Icons.memory, 'System Info', _showSysInfo),
              _actionButton(context, Icons.verified_user, 'SSL Certificate',
                  _showSsl),
            ],
          ),
        ),
      ],
    );
  }

  Widget _serviceTile(BuildContext context, ServiceInfo s) {
    final isActive = _active[s.service];
    final busy = _busy[s.service] ?? false;
    final color = switch (isActive) {
      true => Colors.green.shade600,
      false => Theme.of(context).colorScheme.error,
      null => Colors.orange,
    };

    return ListTile(
      leading: SizedBox(
        width: 22,
        height: 22,
        child: isActive == null
            ? const YaruCircularProgressIndicator(strokeWidth: 2)
            : Icon(Icons.circle, color: color, size: 14),
      ),
      title: Text(s.name),
      subtitle: Text(
        isActive == true
            ? 'Running'
            : isActive == false
                ? 'Stopped'
                : 'Checking…',
        style: TextStyle(color: color),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          OutlinedButton(
            onPressed: busy ? null : () => _run('restart', s.service),
            child: const Text('Restart'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => _run('stop', s.service),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context, IconData icon, String label,
      VoidCallback onPressed) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _runAll(String action) async {
    for (final s in ['nginx', 'mariadb']) {
      if (mounted) setState(() => _busy[s] = true);
      await Process.run('sudo', ['-n', 'systemctl', action, s]);
    }
    for (final s in ['nginx', 'mariadb']) {
      await _check(s);
      if (mounted) setState(() => _busy[s] = false);
    }
  }

  Future<void> _open(String url) async {
    await Process.run('xdg-open', [url]);
  }

  Future<String> _out(List<String> cmd) async {
    final r = await Process.run('sudo', ['-n', ...cmd]);
    final stdout = r.stdout.toString().trim();
    if (stdout.isNotEmpty) return stdout;
    return r.stderr.toString().trim();
  }

  Future<void> _showFirewall() async {
    final out = await _out(['ufw', 'status', 'verbose']);
    if (!mounted) return;
    _showTextDialog(
      context,
      'Firewall Status',
      out.isEmpty
          ? 'Cannot read firewall status.\n'
              'Run the dashboard with sudo privileges '
              '(e.g. sudo /opt/nginix-control-panel/nginix-control-panel).'
          : out,
    );
  }

  Future<void> _showSysInfo() async {
    final host = await Process.run('hostname', []);
    final os = await Process.run('sh', ['-c', 'head -4 /etc/os-release']);
    final mem = await Process.run('free', ['-h']);
    final disk = await Process.run('sh', ['-c', 'df -h / | tail -1']);
    final ip = await Process.run('hostname', ['-I']);
    final text = 'Hostname: ${host.stdout}\n'
        '${os.stdout}\n'
        'Memory:\n${mem.stdout}\n'
        'Disk: ${disk.stdout}\n'
        'IP: ${ip.stdout}';
    if (mounted) _showTextDialog(context, 'System Info', text);
  }

  Future<void> _showSsl() async {
    final r = await Process.run('sh', [
      '-c',
      'openssl x509 -in /etc/nginx/ssl/server.crt -noout -subject -issuer -dates'
    ]);
    if (!mounted) return;
    final out = r.exitCode == 0
        ? r.stdout.toString()
        : 'Could not read certificate:\n${r.stderr.toString().trim()}';
    _showTextDialog(context, 'SSL Certificate', out);
  }

  void _showTextDialog(BuildContext context, String title, String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace')),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/* ================================================================
   Websites
   ================================================================ */

class Site {
  final String name;
  final String status;
  final String root;
  final String config;
  final String url;
  Site(this.name, this.status, this.root, this.config, {this.url = ''});
}

/// The nginx HTTP Basic gate guarding phpMyAdmin, read from
/// /etc/nginx/phpmyadmin-gate.json (written by setup-server.sh).
class GateCreds {
  const GateCreds({
    required this.name,
    required this.url,
    required this.realm,
    required this.user,
    required this.password,
  });

  final String name;
  final String url;
  final String realm;
  final String user;
  final String password;
}

class WebsitesPage extends StatefulWidget {
  const WebsitesPage({super.key});

  @override
  State<WebsitesPage> createState() => _WebsitesPageState();
}

class _WebsitesPageState extends State<WebsitesPage> {
  List<Site> _sites = [];
  bool _loading = true;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const _websitesJsonPath = '/etc/nginx/websites.json';

  Future<void> _load() async {
    setState(() => _loading = true);

    // The website list is defined in /etc/nginx/websites.json. If that file is
    // missing or invalid we fall back to scanning the nginx sites directory.
    final configured = await _loadFromJson();
    if (configured != null) {
      if (mounted) {
        setState(() {
          _sites = configured;
          _loading = false;
        });
      }
      return;
    }

    final dir = Directory('/etc/nginx/sites-available');
    final enabled = Directory('/etc/nginx/sites-enabled');
    final enabledNames = <String>{};
    if (await enabled.exists()) {
      await for (final e in enabled.list()) {
        enabledNames.add(e.path.split('/').last);
      }
    }

    final sites = <Site>[];
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.path.split('/').last;
        final status = enabledNames.contains(name) ? 'Active' : 'Disabled';

        var root = '-';
        final content = await e.readAsString();
        final m = RegExp(r'^\s*root\s+([^;#]+);', multiLine: true)
            .firstMatch(content);
        if (m != null) root = m.group(1)!.trim();
        sites.add(Site(name, status, root, e.path));
      }
    }
    sites.sort((a, b) => a.name.compareTo(b.name));
    if (mounted) {
      setState(() {
        _sites = sites;
        _loading = false;
      });
    }
  }

  Future<List<Site>?> _loadFromJson() async {
    try {
      final file = File(_websitesJsonPath);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      final entries = decoded is Map ? decoded['websites'] : decoded;
      if (entries is! List) return null;

      final enabledNames = <String>{};
      final enabled = Directory('/etc/nginx/sites-enabled');
      if (await enabled.exists()) {
        await for (final e in enabled.list()) {
          enabledNames.add(e.path.split('/').last);
        }
      }

      final sites = <Site>[];
      for (final entry in entries) {
        if (entry is! Map) continue;
        final name = (entry['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final config = (entry['config'] ?? '').toString();
        final root = (entry['root'] ?? '-').toString();
        final url = (entry['url'] ?? '').toString();
        final enabledFlag = entry['enabled'];
        final status = enabledFlag is bool
            ? (enabledFlag ? 'Active' : 'Disabled')
            : (config.isNotEmpty &&
                    enabledNames.contains(config.split('/').last))
                ? 'Active'
                : 'Configured';
        sites.add(Site(name, status, root, config, url: url));
      }
      return sites;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openInBrowser(Site site) async {
    final raw = site.url.isNotEmpty
        ? site.url
        : 'http://$serverIp/${site.name}';
    final url = raw.replaceAll('{serverIp}', serverIp).replaceAll('{ip}', serverIp);
    await Process.run('xdg-open', [url]);
  }

  Future<void> _openFolder(String path) async {
    if (path == '-' || !Directory(path).existsSync()) return;
    await Process.run('xdg-open', [path]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Available Websites',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        YaruBorderContainer(
          child: SizedBox(
            height: 280,
            child: ListView.separated(
              itemCount: _sites.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final site = _sites[i];
                final selected = site.name == _selected;
                final statusColor = switch (site.status) {
                  'Active' => Colors.green.shade600,
                  'Configured' => Colors.orange,
                  _ => Colors.grey,
                };
                final statusIcon = switch (site.status) {
                  'Active' => Icons.check_circle,
                  'Configured' => Icons.settings,
                  _ => Icons.radio_button_unchecked,
                };

                return ListTile(
                  selected: selected,
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  onTap: () => setState(() => _selected = site.name),
                  leading: Icon(statusIcon, color: statusColor),
                  title: Text(site.name),
                  subtitle: Text('${site.status}  •  ${site.root}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Open in Browser',
                        onPressed: () => _openInBrowser(site),
                        icon: const Icon(Icons.language),
                      ),
                      IconButton(
                        tooltip: 'Open Document Root',
                        onPressed: site.root == '-'
                            ? null
                            : () => _openFolder(site.root),
                        icon: const Icon(Icons.folder_open),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/* ================================================================
   Databases
   ================================================================ */

class DbInfo {
  final String name;
  final List<String> users;
  DbInfo(this.name, this.users);
}

class DatabasesPage extends StatefulWidget {
  const DatabasesPage({super.key});

  @override
  State<DatabasesPage> createState() => _DatabasesPageState();
}

class _DatabasesPageState extends State<DatabasesPage> {
  static const _systemDbs = {
    'information_schema',
    'mysql',
    'performance_schema',
    'sys',
  };

  List<DbInfo> _dbs = [];
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  // -- helpers ---------------------------------------------------------------

  Future<String> _sql(String sql) async {
    final p = await Process.start('sudo', ['-n', 'mariadb', '-N', '-B']);
    p.stdin.write(sql);
    await p.stdin.close();
    final outFuture = p.stdout.transform(utf8.decoder).join();
    final errFuture = p.stderr.transform(utf8.decoder).join();
    final out = await outFuture;
    final err = await errFuture;
    final code = await p.exitCode;
    if (code != 0) {
      throw Exception(err.trim().isEmpty ? 'Command failed' : err.trim());
    }
    return out.trim();
  }

  static String _ident(String name) => '`${name.replaceAll('`', '')}`';

  static String _lit(String value) => "'${value.replaceAll("'", "''")}'";

  static bool _validIdent(String name) =>
      RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final out = await _sql(
        "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA;",
      );
      final names = out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !_systemDbs.contains(l))
          .toList()
        ..sort();

      final dbs = <DbInfo>[];
      for (final name in names) {
        final users = <String>[];
        try {
          final u = await _sql(
            'SELECT GRANTEE FROM information_schema.SCHEMA_PRIVILEGES '
            'WHERE TABLE_SCHEMA=${_lit(name)};',
          );
          for (final line in u.split('\n')) {
            final m = RegExp(r"^'([^']+)'@").firstMatch(line.trim());
            if (m != null && !users.contains(m.group(1))) {
              users.add(m.group(1)!);
            }
          }
        } catch (_) {}
        dbs.add(DbInfo(name, users));
      }
      if (mounted) {
        setState(() {
          _dbs = dbs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Failed to load databases: $e');
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  // -- actions ---------------------------------------------------------------

  Future<void> _createDatabase() async {
    final result = await _showFormDialog(
      title: 'New Database',
      fields: const [
        _FormField('Database name', hint: 'myapp'),
        _FormField('Username', hint: 'myapp'),
        _FormField('Password', hint: 'auto-generate if left blank', obscure: true),
      ],
      submitLabel: 'Create',
    );
    if (result == null) return;

    final dbName = result[0].trim();
    var user = result[1].trim();
    var pass = result[2];
    if (dbName.isEmpty) return _snack('Database name is required');
    if (!_validIdent(dbName)) {
      return _snack('Database name may only contain letters, digits, _');
    }
    if (user.isEmpty) user = dbName;
    if (!_validIdent(user)) {
      return _snack('Username may only contain letters, digits, _');
    }
    if (pass.isEmpty) pass = _randomPassword();

    setState(() => _busy.add(dbName));
    try {
      await _sql(
        'CREATE DATABASE IF NOT EXISTS ${_ident(dbName)} '
        'CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'
        "CREATE USER IF NOT EXISTS '$user'@'localhost' "
        'IDENTIFIED BY ${_lit(pass)};'
        "ALTER USER '$user'@'localhost' IDENTIFIED BY ${_lit(pass)};"
        'GRANT ALL PRIVILEGES ON ${_ident(dbName)}.* '
        "TO '$user'@'localhost';"
        'FLUSH PRIVILEGES;',
      );
      _snack('Created database "$dbName" (user: $user, password: $pass)');
    } catch (e) {
      _snack('Create failed: $e');
    }
    if (mounted) setState(() => _busy.remove(dbName));
    await _load();
  }

  Future<void> _changePassword(DbInfo db) async {
    final defaultUser = db.users.isEmpty ? db.name : db.users.first;
    final result = await _showFormDialog(
      title: 'Change Password — ${db.name}',
      fields: [
        _FormField('Username', initial: defaultUser),
        const _FormField('New password', obscure: true, hint: 'auto-generate if blank'),
      ],
      submitLabel: 'Change',
    );
    if (result == null) return;

    final user = result[0].trim();
    var pass = result[1];
    if (user.isEmpty) return _snack('Username is required');
    if (!_validIdent(user)) {
      return _snack('Username may only contain letters, digits, _');
    }
    if (pass.isEmpty) pass = _randomPassword();

    setState(() => _busy.add(db.name));
    try {
      await _sql(
        "ALTER USER '$user'@'localhost' IDENTIFIED BY ${_lit(pass)};"
        'FLUSH PRIVILEGES;',
      );
      _snack('Password for "$user" changed to: $pass');
    } catch (e) {
      _snack('Password change failed: $e');
    }
    if (mounted) setState(() => _busy.remove(db.name));
  }

  Future<void> _deleteDatabase(DbInfo db) async {
    // Only drop users whose schema privileges are limited to this database,
    // so accounts shared with other databases are preserved.
    final droppable = <String>[];
    final shared = <String>[];
    try {
      final rows = await _sql(
        'SELECT GRANTEE, TABLE_SCHEMA FROM information_schema.SCHEMA_PRIVILEGES;',
      );
      final map = <String, Set<String>>{};
      for (final line in rows.split('\n')) {
        final parts = line.split('\t');
        if (parts.length < 2) continue;
        final m = RegExp(r"^'([^']+)'@").firstMatch(parts[0].trim());
        if (m == null) continue;
        map.putIfAbsent(m.group(1)!, () => <String>{}).add(parts[1].trim());
      }
      for (final u in db.users) {
        final schemas = map[u] ?? <String>{};
        if (schemas.difference({db.name}).isEmpty) {
          droppable.add(u);
        } else {
          shared.add(u);
        }
      }
    } catch (_) {
      shared.addAll(db.users);
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete database "${db.name}"?'),
        content: Text(
          'This permanently drops the database and all its data.'
          '${droppable.isNotEmpty ? '\n\nUsers to drop: ${droppable.join(', ')}' : ''}'
          '${shared.isNotEmpty ? '\n\nKept (shared with other databases): '
              '${shared.join(', ')}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy.add(db.name));
    try {
      var sql = 'DROP DATABASE IF EXISTS ${_ident(db.name)};';
      for (final u in droppable) {
        sql += "DROP USER IF EXISTS '$u'@'localhost';";
      }
      sql += 'FLUSH PRIVILEGES;';
      await _sql(sql);
      _snack('Deleted database "${db.name}"');
    } catch (e) {
      _snack('Delete failed: $e');
    }
    if (mounted) setState(() => _busy.remove(db.name));
    await _load();
  }

  static String _randomPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final rnd = Random.secure();
    return List.generate(20, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<List<String>?> _showFormDialog({
    required String title,
    required List<_FormField> fields,
    required String submitLabel,
  }) async {
    final controllers =
        fields.map((f) => TextEditingController(text: f.initial)).toList();
    try {
      return await showDialog<List<String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  TextField(
                    controller: controllers[i],
                    obscureText: fields[i].obscure,
                    decoration: InputDecoration(
                      labelText: fields[i].label,
                      hintText: fields[i].hint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                controllers.map((c) => c.text).toList(),
              ),
              child: Text(submitLabel),
            ),
          ],
        ),
      );
    } finally {
      for (final c in controllers) {
        c.dispose();
      }
    }
  }

  // -- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Databases',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _createDatabase,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Database'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'MariaDB • create, drop databases and manage user passwords',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: YaruCircularProgressIndicator(),
            ),
          )
        else
          YaruBorderContainer(
            child: _dbs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('No databases found',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : Column(
                    children: [
                      for (final (i, db) in _dbs.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _dbTile(context, db),
                      ],
                    ],
                  ),
          ),
      ],
    );
  }

  Widget _dbTile(BuildContext context, DbInfo db) {
    final busy = _busy.contains(db.name);
    return ListTile(
      leading: Icon(Icons.storage_rounded,
          color: Theme.of(context).colorScheme.primary),
      title: Text(db.name),
      subtitle: Text(db.users.isEmpty
          ? 'No dedicated user'
          : 'Users: ${db.users.join(', ')}'),
      trailing: Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: busy ? null : () => _changePassword(db),
            icon: const Icon(Icons.password, size: 18),
            label: const Text('Password'),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => _deleteDatabase(db),
            icon: Icon(Icons.delete_outline,
                size: 18, color: Theme.of(context).colorScheme.error),
            label: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _FormField {
  final String label;
  final String? hint;
  final String? initial;
  final bool obscure;
  const _FormField(this.label,
      {this.hint, this.initial, this.obscure = false});
}

/* ================================================================
   Backups
   ================================================================ */

class BackupsPage extends StatefulWidget {
  const BackupsPage({super.key});

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  static const _allLabel = 'All databases';
  static const _systemDbs = {
    'information_schema',
    'mysql',
    'performance_schema',
    'sys',
  };

  List<String> _databases = [];
  String _selected = _allLabel;
  List<File> _files = [];
  String _schedule = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _loadDatabases();
    _load();
  }

  Future<void> _loadDatabases() async {
    try {
      final p = await Process.start('sudo', ['-n', 'mariadb', '-N', '-B']);
      p.stdin.write('SELECT SCHEMA_NAME FROM information_schema.SCHEMATA;');
      await p.stdin.close();
      final outFuture = p.stdout.transform(utf8.decoder).join();
      final errFuture = p.stderr.transform(utf8.decoder).join();
      final out = await outFuture;
      final err = await errFuture;
      final code = await p.exitCode;
      if (code != 0) {
        _snack('Could not list databases: ${err.trim()}');
        return;
      }
      final dbs = out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !_systemDbs.contains(l))
          .toList()
        ..sort();
      if (mounted) setState(() => _databases = dbs);
    } catch (e) {
      _snack('Could not list databases: $e');
    }
  }

  Future<void> _load() async {
    final dir = Directory('/var/backups/mariadb');
    if (!await dir.exists()) {
      if (mounted) setState(() => _files = []);
      return;
    }
    final files = await dir
        .list()
        .where((e) => e.path.endsWith('.enc'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    var schedule = '';
    try {
      final cron = File('/etc/cron.d/mariadb-backup');
      if (await cron.exists()) {
        for (final line in (await cron.readAsString()).split('\n')) {
          final t = line.trim();
          if (t.isEmpty || t.startsWith('#')) continue;
          schedule = t.split(RegExp(r'\s+')).take(5).join(' ');
          break;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _files = files;
        _schedule = schedule;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  Future<void> _backupNow() async {
    setState(() => _running = true);
    try {
      final args = _selected == _allLabel
          ? ['-n', '/usr/local/bin/backup-db.sh']
          : ['-n', '/usr/local/bin/backup-db.sh', _selected];
      final r = await Process.run('sudo', args);
      if (r.exitCode != 0) {
        final err = r.stderr.toString().trim();
        _snack('Backup failed${err.isEmpty ? '' : ': $err'}');
      } else {
        _snack('Backup complete: $_selected');
      }
    } catch (e) {
      _snack('Backup failed: $e');
    }
    await _load();
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Database Backups',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue:
                    _databases.contains(_selected) ? _selected : _allLabel,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Database',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: _allLabel,
                    child: Text(_allLabel),
                  ),
                  for (final db in _databases)
                    DropdownMenuItem(value: db, child: Text(db)),
                ],
                onChanged: _running
                    ? null
                    : (v) => setState(() => _selected = v ?? _allLabel),
              ),
            ),
            const SizedBox(width: 12),
            _running
                ? const Row(children: [
                    YaruCircularProgressIndicator(strokeWidth: 2.5),
                    SizedBox(width: 12),
                    Text('Backing up…'),
                  ])
                : FilledButton.icon(
                    onPressed: _backupNow,
                    icon: const Icon(Icons.backup, size: 18),
                    label: const Text('BACKUP NOW'),
                  ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Open backups folder',
              onPressed: () =>
                  Process.run('xdg-open', ['/var/backups/mariadb']),
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Encrypted AES-256-CBC • Retention 30 days'
          '${_schedule.isEmpty ? '' : ' • Schedule: $_schedule'}',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        YaruBorderContainer(
          child: _files.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: Text('No backups found',
                          style: TextStyle(color: Colors.grey))),
                )
              : Column(
                  children: [
                    for (final (i, file) in _files.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _fileTile(context, file),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _fileTile(BuildContext context, File f) {
    final byteSize = f.statSync().size;
    final size = byteSize < 1024 * 1024
        ? '${(byteSize / 1024).toStringAsFixed(1)} KB'
        : '${(byteSize / 1024 / 1024).toStringAsFixed(1)} MB';
    final date = f.statSync().modified.toLocal().toString().substring(0, 16);
    final name = f.path.split('/').last;

    // db-<label>-YYYY-MM-DD_HH-MM-SS.sql.enc  (older: db-<label>-YYYYMMDD-HHMMSS)
    String label = '';
    String when = '';
    final m = RegExp(
      r'^db-(.+?)-(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.sql\.enc$',
    ).firstMatch(name);
    final legacy =
        RegExp(r'^db-(.+?)-(\d{8}-\d{6})\.sql\.enc$').firstMatch(name);
    if (m != null) {
      label = m.group(1)!;
      when = m.group(2)!.replaceFirst('_', ' ');
    } else if (legacy != null) {
      label = legacy.group(1)!;
      when = legacy.group(2)!;
    }

    return ListTile(
      leading: const Icon(Icons.archive),
      title: Text(name),
      subtitle: Text(
        '${label.isEmpty ? '' : 'Database: $label  •  '}$size  •  ${when.isEmpty ? date : when}',
      ),
      trailing: IconButton(
        tooltip: 'Open Backup Folder',
        onPressed: () => Process.run('xdg-open', ['/var/backups/mariadb']),
        icon: const Icon(Icons.folder_open),
      ),
    );
  }
}

/* ================================================================
   Restore
   ================================================================ */

class RestorePage extends StatefulWidget {
  const RestorePage({super.key});

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  static const _backupDir = '/var/backups/mariadb';

  List<File> _files = [];
  String? _selected;
  bool _loading = true;
  bool _restoring = false;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dir = Directory(_backupDir);
    final files = <File>[];
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.sql.enc')) files.add(e);
      }
    }
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
        if (_selected != null && !files.any((f) => f.path == _selected)) {
          _selected = null;
        }
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  String _dbLabel(String name) {
    final m = RegExp(r'^db-(.+?)-(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.sql\.enc$')
        .firstMatch(name);
    if (m != null) return m.group(1)!;
    final legacy =
        RegExp(r'^db-(.+?)-\d{8}-\d{6}\.sql\.enc$').firstMatch(name);
    return legacy?.group(1) ?? 'unknown';
  }

  String _size(File f) {
    final b = f.statSync().size;
    return b < 1024 * 1024
        ? '${(b / 1024).toStringAsFixed(1)} KB'
        : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _restore() async {
    final path = _selected;
    if (path == null) return;
    final label = _dbLabel(path.split('/').last);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore database?'),
        content: Text(
          'This will restore from:\n${path.split('/').last}\n\n'
          'Target database: $label\n\n'
          'Existing tables with the same name will be overwritten. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() {
      _restoring = true;
      _log = 'Restoring $path …';
    });

    try {
      final r = await Process.run('sudo', [
        '-n',
        '/usr/local/bin/restore-db.sh',
        path,
      ]);
      final out = '${r.stdout}${r.stderr}'.trim();
      if (!mounted) return;
      if (r.exitCode != 0) {
        setState(() => _log = 'Restore FAILED:\n$out');
        _snack('Restore failed');
      } else {
        setState(() => _log = 'Restore complete.\n$out');
        _snack('Restored ${path.split('/').last}');
      }
    } catch (e) {
      if (mounted) setState(() => _log = 'Restore FAILED:\n$e');
      _snack('Restore failed: $e');
    }

    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Restore from Backup',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh backups',
              onPressed: _loading || _restoring ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Open backups folder',
              onPressed: () => Process.run('xdg-open', [_backupDir]),
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Decrypts an AES-256-CBC backup and imports it into MariaDB.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: YaruCircularProgressIndicator(),
            ),
          )
        else if (_files.isEmpty)
          YaruBorderContainer(
            child: const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                  child: Text('No backups available',
                      style: TextStyle(color: Colors.grey))),
            ),
          )
        else ...[
          YaruBorderContainer(
            child: RadioGroup<String>(
              groupValue: _selected,
              onChanged: (v) {
                if (!_restoring) setState(() => _selected = v);
              },
              child: Column(
                children: [
                  for (final (i, f) in _files.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    RadioListTile<String>(
                      value: f.path,
                      title: Text(f.path.split('/').last),
                      subtitle: Text(
                        'Database: ${_dbLabel(f.path.split('/').last)}  •  ${_size(f)}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed:
                    _selected == null || _restoring ? null : _restore,
                icon: const Icon(Icons.settings_backup_restore, size: 18),
                label: const Text('RESTORE'),
              ),
              const SizedBox(width: 12),
              if (_restoring)
                const Row(children: [
                  YaruCircularProgressIndicator(strokeWidth: 2.5),
                  SizedBox(width: 12),
                  Text('Restoring…'),
                ]),
            ],
          ),
        ],
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 16),
          YaruBorderContainer(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _log,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/* ================================================================
   Configs
   ================================================================ */

class ConfigsPage extends StatefulWidget {
  const ConfigsPage({super.key});

  @override
  State<ConfigsPage> createState() => _ConfigsPageState();
}

class _ConfigsPageState extends State<ConfigsPage> {
  static final configFiles = <String, String>{
    'Nginx Main Config': '/etc/nginx/nginx.conf',
    'Nginx Site Config': '/etc/nginx/sites-available/demoweb.local',
    'Websites List': '/etc/nginx/websites.json',
    'php.ini': '/etc/php/8.5/fpm/php.ini',
    'my.cnf': '/etc/mysql/mariadb.conf.d/50-server.cnf',
  };

  static const _gateJsonPath = '/etc/nginx/phpmyadmin-gate.json';
  static const _gateTab = 'phpMyAdmin Gate';

  String? _selected;
  String _content = '';
  bool _loading = true;
  GateCreds? _gate;
  bool _showGatePassword = false;
  final _editor = TextEditingController();

  @override
  void initState() {
    super.initState();
    _select(configFiles.keys.first);
    _loadGate();
  }

  Future<void> _loadGate() async {
    var content = '';
    try {
      final file = File(_gateJsonPath);
      if (await file.exists()) content = await file.readAsString();
    } catch (_) {}
    // Root-only file: fall back to a privileged read.
    if (content.trim().isEmpty) {
      final r = await Process.run('sudo', ['-n', 'cat', _gateJsonPath]);
      if (r.exitCode == 0) content = r.stdout.toString();
    }
    if (content.trim().isEmpty) return;
    GateCreds? gate;
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        gate = GateCreds(
          name: (decoded['name'] ?? 'phpMyAdmin').toString(),
          url: (decoded['url'] ?? '').toString(),
          realm: (decoded['realm'] ?? '').toString(),
          user: (decoded['user'] ?? '').toString(),
          password: (decoded['password'] ?? '').toString(),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _gate = gate);
  }

  Future<void> _openGateInBrowser() async {
    final gate = _gate;
    if (gate == null) return;
    final raw = gate.url.isNotEmpty ? gate.url : 'https://$serverIp/phpmyadmin';
    final url =
        raw.replaceAll('{serverIp}', serverIp).replaceAll('{ip}', serverIp);
    await Process.run('xdg-open', [url]);
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    showToast(context, '$label copied to clipboard');
  }

  static const _htpasswdPath = '/etc/nginx/.nginix-htpasswd';

  Future<void> _openGateFolder() async {
    final dir = Directory(_gateJsonPath).parent.path;
    final target = await Directory(dir).exists() ? dir : '/etc/nginx';
    await Process.run('xdg-open', [target]);
    if (mounted) showToast(context, 'Opening $target');
  }

  String _randomPassword() {
    final rnd = Random.secure();
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    return List.generate(18, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _promptChangeGatePassword() async {
    final gate = _gate;
    if (gate == null) return;
    final controller = TextEditingController(text: _randomPassword());
    var obscure = true;
    final newPass = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change phpMyAdmin gate password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('User: ${gate.user}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'New password',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Generate',
                        onPressed: () => setDialogState(
                            () => controller.text = _randomPassword()),
                        icon: const Icon(Icons.casino),
                      ),
                      IconButton(
                        tooltip: obscure ? 'Show' : 'Hide',
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                        icon: Icon(
                            obscure ? Icons.visibility : Icons.visibility_off),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Updates the nginx login (.nginix-htpasswd) and '
                'phpmyadmin-gate.json.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (newPass == null || newPass.isEmpty) return;
    await _changeGatePassword(newPass);
  }

  Future<void> _changeGatePassword(String newPassword) async {
    final gate = _gate;
    if (gate == null) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final hashRes =
        await Process.run('openssl', ['passwd', '-apr1', newPassword]);
    if (hashRes.exitCode != 0) {
      _snack('Failed to hash password');
      return;
    }
    final hash = hashRes.stdout.toString().trim();

    final tmpHt =
        File('${Directory.systemTemp.path}/nginix_htpasswd_$stamp.tmp');
    final tmpJson =
        File('${Directory.systemTemp.path}/nginix_gate_$stamp.json');

    var ok = true;
    try {
      await tmpHt.writeAsString('${gate.user}:$hash\n');
      await tmpJson.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({
            'name': gate.name,
            'url': gate.url,
            'realm': gate.realm,
            'user': gate.user,
            'password': newPassword,
          })}\n');

      final cp1 = await Process.run('sudo', ['-n', 'cp', tmpHt.path, _htpasswdPath]);
      final cp2 = await Process
          .run('sudo', ['-n', 'cp', tmpJson.path, _gateJsonPath]);
      if (cp1.exitCode != 0 || cp2.exitCode != 0) {
        ok = false;
      } else {
        await Process.run(
            'sudo', ['-n', 'chmod', '640', _htpasswdPath]);
        await Process.run(
            'sudo', ['-n', 'chown', 'root:www-data', _htpasswdPath]);
        await Process.run('sudo', ['-n', 'chmod', '600', _gateJsonPath]);
        await Process.run('sudo', ['-n', 'chown', 'root:root', _gateJsonPath]);
      }
    } catch (_) {
      ok = false;
    } finally {
      try {
        await tmpHt.delete();
      } catch (_) {}
      try {
        await tmpJson.delete();
      } catch (_) {}
    }

    if (!ok) {
      _snack('Failed to update gate password');
      return;
    }
    if (mounted) {
      setState(() => _gate = GateCreds(
            name: gate.name,
            url: gate.url,
            realm: gate.realm,
            user: gate.user,
            password: newPassword,
          ));
    }
    _snack('Gate password updated');
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  Future<void> _select(String name) async {
    setState(() {
      _selected = name;
      _loading = true;
    });
    if (name == _gateTab) {
      await _loadGate();
      if (mounted) setState(() => _loading = false);
      return;
    }
    final path = configFiles[name]!;
    final content = await _readFile(path);
    if (mounted) {
      setState(() {
        _content = content;
        _editor.text = content;
        _editor.selection =
            TextSelection.collapsed(offset: content.length);
        _loading = false;
      });
    }
  }

  Future<String> _readFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {}
    // Fall back to privileged read for root-only files.
    final r = await Process.run('sudo', ['-n', 'cat', path]);
    if (r.exitCode == 0) return r.stdout.toString();
    return '';
  }

  Future<void> _save() async {
    final path = configFiles[_selected]!;
    final tmpFile = File('${Directory.systemTemp.path}/config_write_'
        '${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await tmpFile.writeAsString(_content);
      final r = await Process.run('sudo', ['-n', 'cp', tmpFile.path, path]);
      if (r.exitCode == 0) {
        _snack('Saved: $path');
      } else {
        _snack('Save failed: ${'${r.stdout}${r.stderr}'.trim()}');
      }
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
  }

  Future<void> _testNginx() async {
    final r = await Process.run('sudo', ['-n', 'nginx', '-t']);
    if (!mounted) return;
    final out = '${r.stdout}${r.stderr}'.trim();
    _snack(r.exitCode == 0 ? 'Test OK: $out' : 'Test failed: $out');
  }

  Future<void> _reloadNginx() async {
    final r = await Process.run('sudo', ['-n', 'systemctl', 'reload', 'nginx']);
    if (!mounted) return;
    if (r.exitCode == 0) {
      _snack('Nginx reloaded');
    } else {
      _snack('Reload failed: ${'${r.stdout}${r.stderr}'.trim()}');
    }
  }

  Future<void> _openConfigFolder() async {
    final path = configFiles[_selected] ?? '';
    var dir = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '/etc/nginx';
    if (!await Directory(dir).exists()) {
      dir = '/etc/nginx';
    }
    await Process.run('xdg-open', [dir]);
    if (mounted) {
      showToast(context, 'Opening $dir');
    }
  }

  Future<void> _openNginxFolder() async {
    final dir = Directory('/etc/nginx/sites-available');
    final target = await dir.exists() ? dir.path : '/etc/nginx';
    await Process.run('xdg-open', [target]);
    if (mounted) {
      showToast(context, 'Opening $target');
    }
  }

  Widget _buildGateCard() {
    final gate = _gate!;
    final scheme = Theme.of(context).colorScheme;
    final url = gate.url.isNotEmpty ? gate.url : 'https://{serverIp}/phpmyadmin';
    return YaruBorderContainer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('${gate.name} Gate Login',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  tooltip: 'Open gate folder',
                  onPressed: _openGateFolder,
                  icon: const Icon(Icons.folder_open),
                ),
                OutlinedButton.icon(
                  onPressed: _promptChangeGatePassword,
                  icon: const Icon(Icons.password, size: 18),
                  label: const Text('Change Password'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _openGateInBrowser,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'nginx login (realm "${gate.realm}") requested before the '
              'phpMyAdmin database login.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _gateRow('URL', url),
            _gateRow('Username', gate.user),
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text('Password',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
                Expanded(
                  child: Text(
                    _showGatePassword ? gate.password : '••••••••',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: _showGatePassword ? 'Hide' : 'Show',
                  onPressed: () => setState(
                      () => _showGatePassword = !_showGatePassword),
                  icon: Icon(_showGatePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                ),
                IconButton(
                  tooltip: 'Copy username & password',
                  onPressed: () =>
                      _copy('Login', '${gate.user} / ${gate.password}'),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _gateRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
          IconButton(
            tooltip: 'Copy $label',
            onPressed: () => _copy(label, value),
            icon: const Icon(Icons.copy, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Config Editor',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                tooltip: 'Open nginx config folder',
                onPressed: _openNginxFolder,
                icon: const Icon(Icons.folder_open),
              ),
              IconButton(
                tooltip: 'Open folder of selected file',
                onPressed: _openConfigFolder,
                icon: const Icon(Icons.drive_file_move_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selected == null
                ? ''
                : (_selected == _gateTab
                    ? _gateJsonPath
                    : configFiles[_selected] ?? ''),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final name in [...configFiles.keys, _gateTab])
                ChoiceChip(
                  label: Text(name),
                  selected: _selected == name,
                  onSelected: (_) => _select(name),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _selected == _gateTab
                ? (_gate == null
                    ? const Center(
                        child: Text('No phpmyadmin-gate.json found.'))
                    : SingleChildScrollView(child: _buildGateCard()))
                : _loading
                    ? const Center(child: YaruCircularProgressIndicator())
                    : YaruBorderContainer(
                        child: Scrollbar(
                          child: TextField(
                            controller: _editor,
                            onChanged: (v) => _content = v,
                            maxLines: null,
                            expands: true,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13),
                            decoration: const InputDecoration(
                                border: InputBorder.none),
                          ),
                        ),
                      ),
          ),
          if (_selected != _gateTab) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save File'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _testNginx,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Test Nginx'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _reloadNginx,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reload Nginx'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/* ================================================================
   Terminal
   ================================================================ */

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _log = <String>[];
  final _scroll = ScrollController();

  static final commands = <String, String>{
    'Disk Usage': 'df -h',
    'Memory': 'free -h',
    'Top Processes': 'ps aux --sort=-%cpu | head -15',
    'Network': 'ss -tlnp',
    'Nginx Error Log': 'tail -50 /var/log/nginx/demoweb.local-error.log',
    'Backup Log': 'tail -50 /var/log/backup-db.log',
    'MySQL Status': 'systemctl status mariadb',
    'SSL Cert': 'openssl x509 -in /etc/nginx/ssl/server.crt -noout -text | head -15',
    'Firewall': 'ufw status verbose',
    'Cron Jobs': 'crontab -l',
  };

  Future<void> _run(String name, String cmd) async {
    setState(() => _log.add('\n═══ $name: $cmd ═══'));
    final r = await Process.run('sudo', ['-n', 'sh', '-c', cmd]);
    final out = '${r.stdout}\n${r.stderr}';
    if (mounted) {
      setState(() => _log.add(out.isEmpty ? '(no output)' : out));
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _scrollToEnd() {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in commands.entries)
                OutlinedButton(
                  onPressed: () => _run(entry.key, entry.value),
                  child: Text(entry.key),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Scrollbar(
                controller: _scroll,
                child: ListView(
                  controller: _scroll,
                  children: [
                    for (final line in _log)
                      SelectableText(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/* ================================================================
   Network
   ================================================================ */

class NetworkInfo {
  final String ip;
  final String netmask;
  final String gateway;
  final List<String> dns;
  final String status;
  final String ping;
  NetworkInfo(this.ip, this.netmask, this.gateway, this.dns, this.status,
      this.ping);
}

class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  NetworkInfo? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _prefixToMask(int prefix) {
    if (prefix < 0 || prefix > 32) return '';
    final mask = 0xFFFFFFFF << (32 - prefix);
    return '${(mask >> 24) & 255}.${(mask >> 16) & 255}.${(mask >> 8) & 255}.${mask & 255}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    String ip = '';
    String netmask = '';
    String gateway = '';
    String status = 'Offline';
    String ping = 'Not tested';
    final dns = <String>[];

    String device = '';
    final devs = await Process.run('nmcli', ['-t', 'device', 'status']);
    if (devs.exitCode == 0) {
      final tethered = {'rndis_host', 'usbnet', 'cdc_ether', 'cdc_ncm'};
      for (final line in (devs.stdout as String? ?? '').split('\n')) {
        final parts = line.split(':');
        if (parts.length >= 3 && parts[1] == 'ethernet' &&
            parts[2] == 'connected') {
          final d = parts[0];
          final drv = await Process.run('nmcli',
              ['-g', 'GENERAL.DRIVER', 'device', 'show', d]);
          final driver = drv.stdout.toString().trim();
          if (!tethered.contains(driver)) {
            device = d;
            break;
          }
        }
      }
    }

    if (device.isEmpty) {
      final route = await Process.run('ip', ['route', 'show', 'default']);
      if (route.exitCode == 0) {
        final m = RegExp(r'dev\s+(\S+)').firstMatch(route.stdout.toString());
        if (m != null) device = m.group(1)!;
      }
    }

    if (device.isNotEmpty) {
      final addr =
          await Process.run('ip', ['-o', '-4', 'addr', 'show', 'dev', device]);
      if (addr.exitCode == 0) {
        final m = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)')
            .firstMatch(addr.stdout.toString());
        if (m != null) {
          ip = m.group(1)!;
          netmask = _prefixToMask(int.parse(m.group(2)!));
        }
      }

      final gw =
          await Process.run('nmcli', ['-g', 'IP4.GATEWAY', 'device', 'show', device]);
      if (gw.exitCode == 0 && gw.stdout.toString().trim().isNotEmpty) {
        gateway = gw.stdout.toString().trim();
      }

      final nmcliDns = await Process.run('nmcli', [
        '-t',
        '-f',
        'IP4.DNS',
        'device',
        'show',
        device,
      ]);
      if (nmcliDns.exitCode == 0) {
        final ipRe = RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b');
        for (final m in ipRe.allMatches(nmcliDns.stdout.toString())) {
          if (dns.length < 2) dns.add(m.group(1)!);
        }
      }
    }

    final conn = await Process.run('nmcli', ['-t', 'networking']);
    if (conn.exitCode == 0 &&
        conn.stdout.toString().trim().toLowerCase() == 'enabled') {
      final up =
          await Process.run('nmcli', ['-t', '-f', 'RUNNING', 'general']);
      status = up.stdout.toString().trim().toLowerCase() == 'running'
          ? 'Connected'
          : (ip.isNotEmpty ? 'Connected' : 'Offline');
    } else {
      status = ip.isNotEmpty ? 'Connected' : 'Offline';
    }

    if (dns.isEmpty) {
      final resolv = File('/etc/resolv.conf');
      if (await resolv.exists()) {
        final content = await resolv.readAsString();
        for (final line in content.split('\n')) {
          final m = RegExp(r'^\s*nameserver\s+(.+)$').firstMatch(line);
          if (m != null) {
            for (final part in m.group(1)!.split(RegExp(r'[\s,]+'))) {
              if (part.isNotEmpty && dns.length < 2) dns.add(part);
            }
          }
        }
      }
    }

    final pingResult = await Process.run(
      'ping',
      ['-c', '4', '-W', '2', 'google.com'],
      runInShell: true,
    );
    if (pingResult.exitCode == 0) {
      final out = pingResult.stdout.toString();
      final stats = RegExp(r'= ([^=]+) =').firstMatch(out);
      final loss =
          RegExp(r'(\d+(?:\.\d+)?)% packet loss').firstMatch(out);
      final lossText = loss?.group(1) ?? '0';
      final timeText = stats?.group(1)?.trim() ?? '';
      ping = 'Online · $lossText% loss${timeText.isNotEmpty ? ' · $timeText' : ''}';
    } else if (status == 'Connected') {
      ping = 'Google unreachable';
    } else {
      ping = 'Not tested';
    }

    if (mounted) {
      setState(() {
        _info = NetworkInfo(ip, netmask, gateway, dns, status, ping);
        _loading = false;
      });
    }
  }

  Widget _row(BuildContext context, String label, String value,
      [Color? valueColor]) {
    final missing = value.isEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Text(
        missing ? 'Not available' : value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: valueColor ??
              (missing
                  ? colorScheme.error
                  : Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        YaruSection(
          headline: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Network Information',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          child: Column(
            children: [
              _row(context, 'Connection Status',
                  info == null ? '' : info.status,
                  info == null
                      ? null
                      : info.status == 'Connected'
                          ? Colors.green.shade600
                          : Theme.of(context).colorScheme.error),
              const Divider(height: 1),
              _row(context, 'Ping Test (Google)', info == null ? '' : info.ping),
              const Divider(height: 1),
              _row(context, 'IP Address', info?.ip ?? ''),
              const Divider(height: 1),
              _row(context, 'Subnet Mask', info?.netmask ?? ''),
              const Divider(height: 1),
              _row(context, 'Gateway', info?.gateway ?? ''),
              const Divider(height: 1),
              _row(context, 'Primary DNS',
                  info == null || info.dns.isEmpty ? '' : info.dns[0]),
              const Divider(height: 1),
              _row(context, 'Secondary DNS',
                  info == null || info.dns.length < 2 ? '' : info.dns[1]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: Icon(_loading ? Icons.hourglass_top : Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ),
      ],
    );
  }
}

/* ================================================================
   Firewall
   ================================================================ */

class UfwRule {
  final String spec;
  final String action;
  final String proto;
  final Set<int> ports;
  const UfwRule(this.spec, this.action, this.proto, this.ports);
}

class UfwStatus {
  final bool active;
  final List<UfwRule> rules;
  final Set<int> openTcp;
  const UfwStatus(this.active, this.rules, this.openTcp);
}

class FirewallPage extends StatefulWidget {
  const FirewallPage({super.key});

  @override
  State<FirewallPage> createState() => _FirewallPageState();
}

class _FirewallPageState extends State<FirewallPage> {
  final _portCtrl = TextEditingController();
  final _portFocus = FocusNode();
  String _proto = 'tcp';

  final _chkPortCtrl = TextEditingController();
  final _chkHostCtrl = TextEditingController(text: '127.0.0.1');
  bool _checking = false;
  int? _chkPort;
  String _chkHost = '';
  bool? _chkListening;
  bool? _chkFw;
  bool? _chkReach;

  UfwStatus? _status;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _portFocus.dispose();
    _chkPortCtrl.dispose();
    _chkHostCtrl.dispose();
    super.dispose();
  }

  static Set<int> _portsFor(String to) {
    final t = to.trim();
    final lower = t.toLowerCase();
    if (lower.contains('nginx full') || lower.contains('www full')) {
      return {80, 443};
    }
    if (lower.contains('nginx https')) return {443};
    if (lower.contains('nginx http') || lower == 'www') return {80};
    if (lower.contains('openssh') || lower == 'ssh') return {22};

    // Numeric specs, including comma lists ("80,443/tcp") and ranges.
    final ports = <int>{};
    final body = t.replaceAll(RegExp(r'/(tcp|udp)$', caseSensitive: false), '');
    for (final part in body.split(',')) {
      final p = part.trim();
      final range = RegExp(r'^(\d+)(?::(\d+))?$').firstMatch(p);
      if (range == null) continue;
      final a = int.parse(range.group(1)!);
      final b = range.group(2) != null ? int.parse(range.group(2)!) : a;
      if (a > b || a > 65535) continue;
      for (var port = a; port <= b && port <= 65535; port++) {
        ports.add(port);
      }
    }
    return ports;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _error = null;
    bool active = false;
    final rules = <UfwRule>[];
    final openTcp = <int>{};

    final r = await Process.run('sudo', ['-n', 'ufw', 'status']);
    final out = '${r.stdout}${r.stderr}';
    if (r.exitCode != 0) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = r.stderr.toString().trim().isEmpty
              ? 'ufw status failed (exit ${r.exitCode})'
              : r.stderr.toString().trim();
          _loading = false;
        });
      }
      return;
    }
    if (out.toLowerCase().contains('status: active')) active = true;

    final lineRe =
        RegExp(r'^(.+?)\s{2,}(ALLOW|DENY|LIMIT|REJECT)\s+(.+)$');
    for (var line in out.split('\n')) {
      line = line.trimRight();
      if (line.trim().isEmpty ||
          line.startsWith('To') ||
          line.startsWith('--') ||
          line.toLowerCase().startsWith('status:')) {
        continue;
      }
      final m = lineRe.firstMatch(line);
      if (m == null) continue;
      var spec = m.group(1)!.trim();
      final v6 = spec.endsWith('(v6)');
      spec = spec.replaceAll(RegExp(r'\s*\(v6\)\s*$'), '').trim();
      final action = m.group(2)!;
      final ports = _portsFor(spec);
      String proto = 'tcp';
      final pm = RegExp(r'/(tcp|udp)$').firstMatch(spec);
      if (pm != null) proto = pm.group(1)!;
      rules.add(UfwRule(spec, action, proto, ports));
      if (action == 'ALLOW' && proto == 'tcp') {
        openTcp.addAll(ports);
      }
      if (v6 && action == 'ALLOW' && proto == 'tcp') {
        openTcp.addAll(ports);
      }
    }

    if (mounted) {
      setState(() {
        _status = UfwStatus(active, rules, openTcp);
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  Future<void> _ufw(List<String> args, String okMsg) async {
    setState(() => _busy = true);
    try {
      final r = await Process.run('sudo', ['-n', 'ufw', ...args]);
      if (r.exitCode != 0) {
        final err = '${r.stdout}${r.stderr}'.trim();
        _snack('Failed${err.isEmpty ? '' : ': $err'}');
      } else {
        _snack(okMsg);
      }
    } catch (e) {
      _snack('Failed: $e');
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _togglePort(int port, bool open) async {
    final st = _status;
    if (st == null) return;
    if (!st.active) {
      _snack('Firewall is inactive — enable it first');
      return;
    }
    if (open) {
      await _ufw(['allow', '$port/tcp'], 'Opened port $port/tcp');
      return;
    }
    final specs = <String>{};
    for (final rule in st.rules) {
      if (rule.action == 'ALLOW' &&
          rule.proto == 'tcp' &&
          rule.ports.contains(port)) {
        specs.add(rule.spec);
      }
    }
    if (specs.isEmpty) {
      _snack('Port $port/tcp is already closed');
      return;
    }
    setState(() => _busy = true);
    final errors = <String>[];
    for (final spec in specs) {
      final r =
          await Process.run('sudo', ['-n', 'ufw', 'delete', 'allow', spec]);
      if (r.exitCode != 0) {
        errors.add('${r.stdout}${r.stderr}'.trim());
      }
    }
    await _load();
    if (mounted) setState(() => _busy = false);
    if (errors.isEmpty) {
      _snack('Closed port $port/tcp');
    } else {
      _snack('Close failed: ${errors.where((e) => e.isNotEmpty).join('; ')}');
    }
  }

  Future<void> _enableFirewall() async {
    setState(() => _busy = true);
    // Always allow web traffic first; abort if this fails so we never enable
    // an incomplete rule set.
    final ng = await Process.run('sudo', ['-n', 'ufw', 'allow', 'Nginx Full']);
    if (ng.exitCode != 0) {
      final err = '${ng.stdout}${ng.stderr}'.trim();
      _snack('Could not allow Nginx Full'
          '${err.isEmpty ? '' : ': $err'} — firewall not enabled');
      await _load();
      if (mounted) setState(() => _busy = false);
      return;
    }

    // Allow SSH so remote access is not cut off: use the OpenSSH profile when
    // available, otherwise allow port 22 only if an SSH server is running.
    final allowed = <String>['HTTP', 'HTTPS'];
    final apps = await Process.run('sudo', ['-n', 'ufw', 'app', 'list']);
    if (apps.stdout.toString().contains('OpenSSH')) {
      await Process.run('sudo', ['-n', 'ufw', 'allow', 'OpenSSH']);
      allowed.add('SSH');
    } else {
      final ssh = await Process.run('sh', [
        '-c',
        'systemctl is-active --quiet ssh || systemctl is-active --quiet sshd',
      ]);
      if (ssh.exitCode == 0) {
        await Process.run('sudo', ['-n', 'ufw', 'allow', '22/tcp']);
        allowed.add('SSH');
      }
    }

    final r = await Process.run('sudo', ['-n', 'ufw', '--force', 'enable']);
    if (r.exitCode != 0) {
      final err = '${r.stdout}${r.stderr}'.trim();
      _snack('Enable failed${err.isEmpty ? '' : ': $err'}');
    } else {
      _snack('Firewall enabled (${allowed.join(', ')} allowed)');
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _applyCustom(bool open) async {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) {
      _snack('Enter a valid port (1–65535)');
      return;
    }
    if (!(_status?.active ?? false)) {
      _snack('Firewall is inactive — enable it first');
      return;
    }
    final spec = '$port/$_proto';
    if (open) {
      await _ufw(['allow', spec], 'Opened port $spec');
    } else {
      await _ufw(['delete', 'allow', spec], 'Closed port $spec');
    }
  }

  Future<void> _checkPort() async {
    final port = int.tryParse(_chkPortCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) {
      _snack('Enter a valid port (1–65535)');
      return;
    }
    final host = _chkHostCtrl.text.trim().isEmpty
        ? '127.0.0.1'
        : _chkHostCtrl.text.trim();

    setState(() {
      _checking = true;
      _chkPort = port;
      _chkHost = host;
      _chkListening = null;
      _chkFw = null;
      _chkReach = null;
    });

    // 1. Is something listening locally on this TCP port?
    bool listening = false;
    try {
      final ss = await Process.run('ss', ['-ltnH']);
      if (ss.exitCode == 0) {
        for (final line in (ss.stdout as String? ?? '').split('\n')) {
          final cols = line.trim().split(RegExp(r'\s+'));
          if (cols.length >= 4) {
            final local = cols[3];
            final m = RegExp(r'[:.](\d+)$').firstMatch(local);
            if (m != null && int.tryParse(m.group(1)!) == port) {
              listening = true;
              break;
            }
          }
        }
      }
    } catch (_) {}

    // 2. Does UFW allow it?
    bool? allowed;
    if (_status != null) {
      allowed = _status!.active && _status!.openTcp.contains(port);
    }

    // 3. Can we reach host:port right now?
    bool reachable = false;
    try {
      final sock = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      reachable = true;
      sock.destroy();
    } catch (_) {
      reachable = false;
    }

    if (mounted) {
      setState(() {
        _chkListening = listening;
        _chkFw = allowed;
        _chkReach = reachable;
        _checking = false;
      });
    }
  }

  Widget _chkRow(String label, bool? value, String? yes, String? no) {
    final errorColor = Theme.of(context).colorScheme.error;
    Color color;
    String text;
    if (value == null) {
      color = Colors.grey;
      text = 'Unknown';
    } else if (value) {
      color = Colors.green.shade600;
      text = yes ?? 'Yes';
    } else {
      color = errorColor;
      text = no ?? 'No';
    }
    return ListTile(
      dense: true,
      leading: Icon(
        value == null
            ? Icons.help_outline
            : value
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
        color: color,
      ),
      title: Text(label),
      trailing: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _toggleTile(int port, String label) {
    final open = _status?.openTcp.contains(port) ?? false;
    return ListTile(
      leading: Icon(open ? Icons.lock_open : Icons.lock,
          color: open ? Colors.green.shade600 : Colors.grey),
      title: Text('$label  ($port/tcp)'),
      subtitle: Text(open ? 'Open — accepting connections' : 'Closed'),
      trailing: Switch(
        value: open,
        onChanged: _busy || _loading || !(_status?.active ?? false)
            ? null
            : (v) => _togglePort(port, v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    final active = st?.active ?? false;
    final errorColor = Theme.of(context).colorScheme.error;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Firewall',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            if (!_loading)
              Chip(
                avatar: Icon(
                  active ? Icons.shield : Icons.shield_outlined,
                  size: 18,
                  color: active ? Colors.green.shade700 : errorColor,
                ),
                label: Text(_error != null
                    ? 'Unknown'
                    : active
                        ? 'Active'
                        : 'Inactive'),
              ),
            const Spacer(),
            if (_busy || _loading)
              const YaruCircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy || _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Manage the UFW firewall (ports 80/443 and custom rules).',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        if (!_loading && _error != null)
          YaruBorderContainer(
            child: ListTile(
              leading: Icon(Icons.error_outline, color: errorColor),
              title: const Text('Unable to read firewall status'),
              subtitle: Text(_error!),
              trailing: TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Retry'),
              ),
            ),
          ),
        if (!_loading && _error != null) const SizedBox(height: 12),
        if (!_loading && _error == null && !active)
          YaruBorderContainer(
            child: ListTile(
              leading: Icon(Icons.warning_amber, color: errorColor),
              title: const Text('Firewall is inactive'),
              subtitle: const Text(
                  'Rules have no effect until UFW is enabled. Enabling allows '
                  'SSH, HTTP and HTTPS first so you are not locked out.'),
              trailing: FilledButton(
                onPressed: _busy ? null : _enableFirewall,
                child: const Text('ENABLE'),
              ),
            ),
          ),
        if (!_loading && _error == null && !active) const SizedBox(height: 12),
        YaruBorderContainer(
          child: Column(
            children: [
              _toggleTile(80, 'HTTP'),
              const Divider(height: 1),
              _toggleTile(443, 'HTTPS'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Custom Port',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 130,
              child: TextField(
                controller: _portCtrl,
                focusNode: _portFocus,
                keyboardType: TextInputType.number,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: 'e.g. 8080',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _applyCustom(true),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                initialValue: _proto,
                decoration: const InputDecoration(
                  labelText: 'Protocol',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                  DropdownMenuItem(value: 'udp', child: Text('UDP')),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _proto = v ?? 'tcp'),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _busy ? null : () => _applyCustom(true),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('OPEN'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _applyCustom(false),
              icon: const Icon(Icons.remove, size: 18),
              label: const Text('CLOSE'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Port Status Checker',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 130,
              child: TextField(
                controller: _chkPortCtrl,
                keyboardType: TextInputType.number,
                enabled: !_checking,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: 'e.g. 443',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _checkPort(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _chkHostCtrl,
                enabled: !_checking,
                decoration: const InputDecoration(
                  labelText: 'Host / IP',
                  hintText: '127.0.0.1 or example.com',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _checkPort(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _checking ? null : _checkPort,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('CHECK'),
            ),
          ],
        ),
        if (_checking || _chkPort != null) ...[
          const SizedBox(height: 12),
          YaruBorderContainer(
            child: _checking
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                        child: YaruCircularProgressIndicator(
                            strokeWidth: 2.5)),
                  )
                : Column(
                    children: [
                      ListTile(
                        dense: true,
                        title: Text('Check: $_chkHost:$_chkPort/tcp',
                            style:
                                const TextStyle(fontFamily: 'monospace')),
                        subtitle: const Text(
                            'TCP connect uses a 3 second timeout'),
                      ),
                      const Divider(height: 1),
                      _chkRow('Listening on this server', _chkListening,
                          'Something is listening', 'Nothing is listening'),
                      const Divider(height: 1),
                      _chkRow('UFW firewall allows it', _chkFw,
                          'Allowed by UFW', 'Blocked / UFW inactive'),
                      const Divider(height: 1),
                      _chkRow('Connection to $_chkHost', _chkReach,
                          'Connection succeeded',
                          'Refused or timed out'),
                    ],
                  ),
          ),
        ],
        const SizedBox(height: 20),
        const Text('Active Rules',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        YaruBorderContainer(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: YaruCircularProgressIndicator()),
                )
              : (st == null || st.rules.isEmpty)
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: Text('No rules',
                              style: TextStyle(color: Colors.grey))),
                    )
                  : Column(
                      children: [
                        for (final (i, rule) in st.rules.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: Icon(
                              rule.action == 'ALLOW'
                                  ? Icons.check_circle_outline
                                  : Icons.block,
                              color: rule.action == 'ALLOW'
                                  ? Colors.green.shade600
                                  : errorColor,
                            ),
                            title: Text(rule.spec,
                                style:
                                    const TextStyle(fontFamily: 'monospace')),
                            trailing: Text(rule.action,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

/* ================================================================
   Cron Jobs (automatic backup schedule)
   ================================================================ */

class CronJobsPage extends StatefulWidget {
  const CronJobsPage({super.key});

  @override
  State<CronJobsPage> createState() => _CronJobsPageState();
}

class _CronJobsPageState extends State<CronJobsPage> {
  static const _cronPath = '/etc/cron.d/mariadb-backup';
  static const _backupScript = '/usr/local/bin/backup-db.sh';
  static const _systemDbs = {
    'information_schema',
    'mysql',
    'performance_schema',
    'sys',
  };

  static const _presets = <String, String>{
    'Every hour': '0 * * * *',
    'Every day (02:00)': '0 2 * * *',
    'Every week (Monday 02:00)': '0 2 * * 1',
    'Every month (1st, 02:00)': '0 2 1 * *',
    'Custom cron': '',
  };

  final _customCtrl = TextEditingController();

  List<String> _databases = [];
  Set<String> _selected = {};
  bool _all = true;
  String _preset = 'Every week (Monday 02:00)';
  String _currentCron = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<String> _sql(String sql) async {
    final p = await Process.start('sudo', ['-n', 'mariadb', '-N', '-B']);
    p.stdin.write(sql);
    await p.stdin.close();
    final outFuture = p.stdout.transform(utf8.decoder).join();
    final errFuture = p.stderr.transform(utf8.decoder).join();
    final out = await outFuture;
    final err = await errFuture;
    final code = await p.exitCode;
    if (code != 0) {
      throw Exception(err.trim().isEmpty ? 'Command failed' : err.trim());
    }
    return out.trim();
  }

  void _snack(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await _sql(
        'SELECT SCHEMA_NAME FROM information_schema.SCHEMATA;',
      );
      final dbs = out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !_systemDbs.contains(l))
          .toList()
        ..sort();

      final r = await Process.run('sudo', ['-n', 'cat', _cronPath]);
      final content = r.exitCode == 0 ? r.stdout.toString() : '';

      String schedule = '';
      final chosen = <String>{};
      bool all = false;
      for (final raw in content.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 7) continue;
        if (schedule.isEmpty) schedule = parts.sublist(0, 5).join(' ');
        final cmd = parts.sublist(6).join(' ');
        final m = RegExp(r'backup-db\.sh\s*([^>]*)').firstMatch(cmd);
        if (m == null) continue;
        final arg = m.group(1)!.trim();
        if (arg.isEmpty || arg == 'all') {
          all = true;
        } else {
          chosen.add(arg);
        }
      }
      if (schedule.isEmpty) {
        schedule = _presets['Every week (Monday 02:00)']!;
      }

      var preset = 'Custom cron';
      for (final e in _presets.entries) {
        if (e.key != 'Custom cron' && e.value == schedule) {
          preset = e.key;
          break;
        }
      }
      if (preset == 'Custom cron') _customCtrl.text = schedule;

      if (mounted) {
        setState(() {
          _databases = dbs;
          _all = all || chosen.isEmpty;
          _selected = chosen;
          _preset = preset;
          _currentCron = content;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _schedule => _preset == 'Custom cron'
      ? _customCtrl.text.trim()
      : _presets[_preset]!;

  List<String> get _targets {
    if (_all || _selected.isEmpty) return [''];
    return _selected.toList()..sort();
  }

  String _preview() {
    final sched = _schedule;
    final dbs = _targets;
    final label =
        _all || _selected.isEmpty ? 'all databases' : (_selected.toList()..sort()).join(', ');
    final buf = StringBuffer()
      ..writeln('# Managed by Nginix Control Panel - automatic database backup')
      ..writeln('# Period: $_preset')
      ..writeln('# Databases: $label');
    for (final db in dbs) {
      final arg = db.isEmpty ? '' : ' $db';
      buf.writeln('$sched root $_backupScript$arg >/dev/null 2>&1');
    }
    return buf.toString();
  }

  Future<void> _save() async {
    final sched = _schedule;
    if (!RegExp(r'^[\d*,/\-]+(\s+[\d*,/\-]+){4}$').hasMatch(sched)) {
      _snack('Schedule must be a valid 5-field cron expression');
      return;
    }
    if (!_all && _selected.isEmpty) {
      _snack('Select at least one database');
      return;
    }
    setState(() => _saving = true);
    final tmp = File('${Directory.systemTemp.path}/cron_write_'
        '${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await tmp.writeAsString(_preview());
      final cp = await Process.run('sudo', ['-n', 'cp', tmp.path, _cronPath]);
      if (cp.exitCode != 0) {
        _snack('Failed to write cron file: ${cp.stderr.toString().trim()}');
      } else {
        final ch = await Process.run('sudo', ['-n', 'chmod', '644', _cronPath]);
        if (ch.exitCode != 0) {
          _snack('Could not set permissions: ${ch.stderr.toString().trim()}');
        } else {
          _snack('Backup schedule saved');
          await _load();
        }
      }
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final errColor = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Cron Jobs',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_saving || _loading)
              const YaruCircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _saving || _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Automatic backup period for selected databases.',
            style: TextStyle(color: Colors.grey)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: errColor)),
        ],
        const SizedBox(height: 12),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: YaruCircularProgressIndicator(),
            ),
          )
        else ...[
          YaruBorderContainer(
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Current schedule'),
              subtitle: Text(
                _currentCron.trim().isEmpty
                    ? 'No cron file found yet'
                    : _currentCron.trim().split('\n').where(
                        (l) => l.trim().isNotEmpty && !l.trim().startsWith('#')).join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Auto Backup Period',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _presets.containsKey(_preset) ? _preset : 'Custom cron',
            decoration: const InputDecoration(
              labelText: 'Period',
              border: OutlineInputBorder(),
            ),
            items: _presets.keys
                .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                .toList(),
            onChanged: _saving
                ? null
                : (v) => setState(() => _preset = v ?? _preset),
          ),
          if (_preset == 'Custom cron') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customCtrl,
              enabled: !_saving,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'Cron expression',
                hintText: 'm h dom mon dow   (e.g. 30 3 * * 0)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Databases',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          YaruBorderContainer(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Back up all databases'),
                  subtitle: const Text('Includes anything added later'),
                  value: _all,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _all = v),
                ),
                if (!_all) ...[
                  const Divider(height: 1),
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() =>
                                _selected = _databases.toSet()),
                        child: const Text('Select all'),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _selected = {}),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  for (final db in _databases)
                    CheckboxListTile(
                      dense: true,
                      title: Text(db),
                      value: _selected.contains(db),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() {
                                if (v == true) {
                                  _selected.add(db);
                                } else {
                                  _selected.remove(db);
                                }
                              }),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Generated Cron Entry',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          YaruBorderContainer(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _preview().trimRight(),
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving || _loading ? null : _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('SAVE SCHEDULE'),
          ),
        ],
      ],
    );
  }
}