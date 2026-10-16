import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

String serverIp = '127.0.0.1';

Future<void> detectServerIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      if (iface.name == 'lo') continue;
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          serverIp = addr.address;
          return;
        }
      }
    }
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YaruWindowTitleBar.ensureInitialized();
  await detectServerIp();
  runApp(const ServerDashboardApp());
}

class ServerDashboardApp extends StatefulWidget {
  const ServerDashboardApp({super.key});

  @override
  State<ServerDashboardApp> createState() => _ServerDashboardAppState();
}

class _ServerDashboardAppState extends State<ServerDashboardApp> {
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
      const ConfigsPage(),
      const TerminalPage(),
      const NetworkPage(),
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
            length: 8,
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
                (Icons.code, Icons.code, 'Configs'),
                (Icons.terminal, Icons.terminal, 'Terminal'),
                (Icons.lan_outlined, Icons.lan, 'Network'),
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
    final r = await Process.run('systemctl', ['is-active', service]);
    if (mounted) {
      setState(() => _active[service] = r.stdout.toString().trim() == 'active');
    }
  }

  Future<void> _run(String action, String service) async {
    setState(() => _busy[service] = true);
    await Process.run('sudo', ['systemctl', action, service]);
    await _check(service);
    if (mounted) setState(() => _busy[service] = false);
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
      setState(() => _busy[s] = true);
      await Process.run('sudo', ['systemctl', action, s]);
    }
    for (final s in ['nginx', 'mariadb']) {
      await _check(s);
      setState(() => _busy[s] = false);
    }
  }

  Future<void> _open(String url) async {
    await Process.run('xdg-open', [url]);
  }

  Future<String> _out(List<String> cmd) async {
    final r = await Process.run('sudo', cmd);
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
              '(e.g. sudo /opt/server_dashboard/server_dashboard).'
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
    if (mounted) _showTextDialog(context, 'SSL Certificate', r.stdout.toString());
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
        for (final line in content.split('\n')) {
          if (line.trim().startsWith('root') && line.contains('/var/www')) {
            root =
                line.trim().replaceFirst('root', '').replaceAll(';', '').trim();
            break;
          }
        }
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
                final statusColor = site.status == 'Active'
                    ? Colors.green.shade600
                    : Theme.of(context).colorScheme.error;

                return ListTile(
                  selected: selected,
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  onTap: () => setState(() => _selected = site.name),
                  leading: Icon(
                    site.status == 'Active'
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: statusColor,
                  ),
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
    final p = await Process.start('sudo', ['mariadb', '-N', '-B']);
    p.stdin.write(sql);
    await p.stdin.close();
    final out = await p.stdout.transform(utf8.decoder).join();
    final err = await p.stderr.transform(utf8.decoder).join();
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    final dropUser = db.users.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete database "${db.name}"?'),
        content: Text(
          'This permanently drops the database and all its data.'
          '${dropUser ? '\n\nThe user "${db.users.first}" will also be dropped.' : ''}',
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
      for (final u in db.users) {
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
  }) {
    final controllers =
        fields.map((f) => TextEditingController(text: f.initial)).toList();
    return showDialog<List<String>>(
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
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _loadDatabases();
    _load();
  }

  Future<void> _loadDatabases() async {
    try {
      final p = await Process.start('sudo', ['mariadb', '-N', '-B']);
      p.stdin.write('SELECT SCHEMA_NAME FROM information_schema.SCHEMATA;');
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      await p.stderr.drain();
      await p.exitCode;
      final dbs = out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !_systemDbs.contains(l))
          .toList()
        ..sort();
      if (mounted) setState(() => _databases = dbs);
    } catch (_) {}
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
    if (mounted) setState(() => _files = files);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
        const Text(
          'Encrypted AES-256-CBC • Retention 30 days • Weekly Monday 02:00',
          style: TextStyle(color: Colors.grey),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      if (r.exitCode != 0) {
        setState(() => _log = 'Restore FAILED:\n$out');
        _snack('Restore failed');
      } else {
        setState(() => _log = 'Restore complete.\n$out');
        _snack('Restored ${path.split('/').last}');
      }
    } catch (e) {
      setState(() => _log = 'Restore FAILED:\n$e');
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
    '.env File': '/var/www/websites/demoweb.local/.env',
    'php.ini': '/etc/php/8.5/fpm/php.ini',
    'my.cnf': '/etc/mysql/mariadb.conf.d/50-server.cnf',
  };

  String? _selected;
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _select(configFiles.keys.first);
  }

  Future<void> _select(String name) async {
    setState(() {
      _selected = name;
      _loading = true;
    });
    final path = configFiles[name]!;
    final content = await _readFile(path);
    if (mounted) {
      setState(() {
        _content = content;
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
    // Fall back to privileged read for root-only files (e.g. .env).
    final r = await Process.run('sudo', ['-n', 'cat', path]);
    if (r.exitCode == 0) return r.stdout.toString();
    return '';
  }

  Future<void> _save() async {
    final path = configFiles[_selected]!;
    final tmp = '/tmp/_config_write.tmp';
    await File(tmp).writeAsString(_content);
    await Process.run('sudo', ['cp', tmp, path]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $path')),
      );
    }
  }

  Future<void> _testNginx() async {
    final r = await Process.run('sudo', ['nginx', '-t']);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Test: ${r.stdout.isNotEmpty ? r.stdout : r.stderr}'.trim()),
        ),
      );
    }
  }

  Future<void> _reloadNginx() async {
    await Process.run('sudo', ['systemctl', 'reload', 'nginx']);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nginx reloaded')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opening $dir')),
      );
    }
  }

  Future<void> _openNginxFolder() async {
    final dir = Directory('/etc/nginx/sites-available');
    final target = await dir.exists() ? dir.path : '/etc/nginx';
    await Process.run('xdg-open', [target]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opening $target')),
      );
    }
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
            _selected == null ? '' : configFiles[_selected] ?? '',
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
              for (final name in configFiles.keys)
                ChoiceChip(
                  label: Text(name),
                  selected: _selected == name,
                  onSelected: (_) => _select(name),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: YaruCircularProgressIndicator())
                : YaruBorderContainer(
                    child: Scrollbar(
                      child: TextField(
                        controller: TextEditingController(text: _content)
                          ..selection =
                              TextSelection.collapsed(offset: _content.length),
                        onChanged: (v) => _content = v,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                      ),
                    ),
                  ),
          ),
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
    final r = await Process.run('sh', ['-c', cmd]);
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
    if (prefix <= 0 || prefix >= 32) return '';
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

    final conn = await Process.run('nmcli', ['-t', '-f', 'STATE', 'networking']);
    if (conn.exitCode == 0 &&
        conn.stdout.toString().trim().toLowerCase() == 'enabled') {
      final up =
          await Process.run('nmcli', ['-t', '-f', 'RUNNING', 'networking']);
      status = up.stdout.toString().trim() == 'yes' ? 'Connected' : 'Offline';
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