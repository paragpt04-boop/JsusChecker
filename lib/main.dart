import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const CheckerApp());

const cG = Color(0xFF00FF41);
const cCy = Color(0xFF00E5FF);
const cYe = Color(0xFFFFD600);
const cRe = Color(0xFFFF1744);
const cMg = Color(0xFFE040FB);
const cDg = Color(0xFF2A5A2A);
const cBg = Color(0xFF000800);
const cBg2 = Color(0xFF010C01);
const cBr = Color(0xFF0A1F0A);
const cOr = Color(0xFFFF6D00);

class HitEntry {
  final String username, password, panel, m3u;
  String status = 'CHECKING';
  String expira = '...';
  String conex = '?';
  String activ = '0';
  String timezone = '';
  int live = 0, vod = 0, series = 0;
  bool checked = false;
  bool panelVerified = false;
  HitEntry({required this.username, required this.password, required this.panel})
    : m3u = '$panel/get.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&type=m3u_plus';
}

final _client = HttpClient()..badCertificateCallback = (_, __, ___) => true;

const _uas = [
  'Mozilla/5.0 (Linux; Android 13) Chrome/120.0',
  'VLC/3.0.20', 'TiviMate/4.7.0', 'IPTVSmarters/3.1.5', 'okhttp/4.12.0',
];
String _ua() => _uas[DateTime.now().millisecondsSinceEpoch % _uas.length];

// Parse hits file
// Formats supported:
// USER: xxx / PASS: xxx / SERVER: xxx
// server|user|pass
// user:pass (needs server separately)
List<HitEntry> parseHits(String text) {
  final entries = <HitEntry>[];
  final seen = <String>{};
  final clean = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // METODO 1: URLs M3U - el mas confiable
  final lines = clean.split('\n');
  for (final line in lines) {
    final l = line.trim();
    if (l.contains('get.php') && l.contains('username=') && l.contains('password=')) {
      try {
        // Extraer la URL limpia
        final urlMatch = RegExp(r'https?://\S+').firstMatch(l);
        if (urlMatch == null) continue;
        final uri = Uri.parse(urlMatch.group(0)!);
        final user = Uri.decodeComponent(uri.queryParameters['username'] ?? '');
        final pass = Uri.decodeComponent(uri.queryParameters['password'] ?? '');
        if (user.isEmpty || pass.isEmpty) continue;
        final port = (uri.port != 0 && uri.port != 80 && uri.port != 443) ? ':${uri.port}' : '';
        final panel = '${uri.scheme}://${uri.host}$port';
        final key = '$user:$pass:$panel';
        if (!seen.contains(key)) {
          seen.add(key);
          entries.add(HitEntry(username: user, password: pass, panel: panel));
        }
      } catch (_) {}
    }
  }

  // METODO 2: Bloques con campos USER/PASS/SERVER
  if (entries.isEmpty) {
    String? u, p, s;
    void save() {
      if (u != null && p != null && s != null) {
        final key = '$u:$p:$s';
        if (!seen.contains(key)) {
          seen.add(key);
          entries.add(HitEntry(username: u!, password: p!, panel: s!));
        }
        u = p = s = null;
      }
    }
    for (final raw in lines) {
      // Limpiar emojis y decoraciones
      final line = raw.replaceAll(RegExp(r'[^\x00-\x7F\u00C0-\u024F:./\-_@0-9A-Za-z ]'), ' ').trim();
      final lower = line.toLowerCase();
      if (line.isEmpty) { save(); continue; }
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final key = line.substring(0, colonIdx).trim().toLowerCase();
      final val = line.substring(colonIdx + 1).trim();
      if (val.isEmpty) continue;
      if (key.contains('user') || key.contains('usr')) {
        if (!val.startsWith('http')) u = val;
      } else if (key.contains('pass') || key.contains('pwd')) {
        p = val;
      } else if (key.contains('server') || key.contains('srv') || key.contains('host')) {
        s = val.startsWith('http') ? val.replaceAll(RegExp(r'/+\$'), '') : 'http://$val';
      }
    }
    save();
  }

  return entries;
}


Future<void> checkEntry(HitEntry e) async {
  try {
    final url = '${e.panel}/player_api.php?username=${Uri.encodeComponent(e.username)}&password=${Uri.encodeComponent(e.password)}';
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await res.transform(utf8.decoder).join();
    
    Map<String, dynamic> data;
    try { data = jsonDecode(body) as Map<String, dynamic>; }
    catch (_) {
      e.status = body.contains('"auth":1') ? 'ACTIVE' : 'INVALID';
      e.checked = true;
      return;
    }
    
    final ui = (data['user_info'] as Map?) ?? {};
    final si = (data['server_info'] as Map?) ?? {};
    final auth = ui['auth'];
    final st = ui['status']?.toString().toLowerCase().trim() ?? '';
    
    final isActive = auth == 1 || auth == '1' || auth == true ||
      ['active','activo','enabled','premium','trial','free'].contains(st);
    
    if (!isActive || st == 'banned' || st == 'disabled') {
      e.status = st == 'expired' || st == 'vencido' ? 'EXPIRED' : 'INVALID';
      e.checked = true;
      return;
    }
    
    // Parse expiry
    final ts = ui['exp_date'];
    if (ts == null || int.tryParse(ts.toString()) == null || int.parse(ts.toString()) <= 0) {
      e.expira = 'Ilimitado';
    } else {
      final exp = DateTime.fromMillisecondsSinceEpoch(int.parse(ts.toString()) * 1000);
      e.expira = exp.toString().split(' ')[0];
      e.status = exp.isBefore(DateTime.now()) ? 'EXPIRED' : 'ACTIVE';
      e.checked = true;
      e.conex = ui['max_connections']?.toString() ?? '?';
      e.activ = ui['active_cons']?.toString() ?? '0';
      e.timezone = si['timezone']?.toString() ?? '';
      return;
    }
    
    e.status = 'ACTIVE';
    e.conex = ui['max_connections']?.toString() ?? '?';
    e.activ = ui['active_cons']?.toString() ?? '0';
    e.timezone = si['timezone']?.toString() ?? '';
    e.checked = true;
    
    // Verify panel
    await _verifyPanel(e);
    
  } catch (_) {
    e.status = 'ERROR';
    e.checked = true;
  }
}

Future<void> _verifyPanel(HitEntry e) async {
  try {
    final results = await Future.wait([
      _cnt(e.panel, e.username, e.password, 'get_live_streams'),
      _cnt(e.panel, e.username, e.password, 'get_vod_categories'),
      _cnt(e.panel, e.username, e.password, 'get_series_categories'),
    ]);
    e.live = results[0];
    e.vod = results[1];
    e.series = results[2];
    e.panelVerified = true;
  } catch (_) {}
}

Future<int> _cnt(String panel, String user, String pass, String action) async {
  try {
    final url = '$panel/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}&action=$action';
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body);
    if (data is List) return data.length;
  } catch (_) {}
  return 0;
}

class CheckerApp extends StatelessWidget {
  const CheckerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JsusChecker',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: cBg,
      colorScheme: const ColorScheme.dark(primary: cG),
      fontFamily: 'monospace',
    ),
    home: const CheckerScreen(),
  );
}

class CheckerScreen extends StatefulWidget {
  const CheckerScreen({super.key});
  @override
  State<CheckerScreen> createState() => _CS();
}

class _CS extends State<CheckerScreen> with TickerProviderStateMixin {
  final _entries = <HitEntry>[];
  bool _checking = false;
  bool _paused = false;
  int _checked = 0, _active = 0, _expired = 0, _invalid = 0;
  DateTime? _t0;
  Timer? _timer;
  int _threads = 10;
  int _filter = 0; // 0=all 1=active 2=expired 3=invalid

  late AnimationController _glowAc, _pulseAc;
  late Animation<double> _glow, _pulse;
  final _rnd = Random();
  List<List<double>> _drops = [];
  List<List<String>> _chars = [];
  Timer? _matTimer;
  static const _mch = '01ABCDEFアイウエオ<>{}[]|/*';

  @override
  void initState() {
    super.initState();
    _glowAc = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(_glowAc);
    _pulseAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0).animate(_pulseAc);
    _initMatrix();
    _matTimer = Timer.periodic(const Duration(milliseconds: 80), (_) => _tickMatrix());
  }

  void _initMatrix() {
    const cols = 28, rows = 55;
    _drops = List.generate(cols, (_) => List.generate(rows, (_) => 0.0));
    _chars = List.generate(cols, (_) => List.generate(rows, (_) => _mch[_rnd.nextInt(_mch.length)]));
  }

  void _tickMatrix() {
    if (!mounted) return;
    setState(() {
      for (var c = 0; c < _drops.length; c++) {
        if (_rnd.nextDouble() < 0.03) _drops[c][0] = 1.0;
        for (var r = _drops[c].length - 1; r > 0; r--) {
          if (_drops[c][r-1] > 0.5 && _drops[c][r] < 0.1) _drops[c][r] = _drops[c][r-1] * 0.95;
          if (_drops[c][r] > 0) { _drops[c][r] -= 0.018; if (_rnd.nextDouble() < 0.08) _chars[c][r] = _mch[_rnd.nextInt(_mch.length)]; }
        }
        _drops[c][0] *= 0.92;
      }
    });
  }

  @override
  void dispose() {
    _glowAc.dispose(); _pulseAc.dispose();
    _timer?.cancel(); _matTimer?.cancel();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('> $m', style: const TextStyle(color: cG, fontFamily: 'monospace')),
    backgroundColor: cBg2, duration: const Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: const BorderSide(color: cG)),
  ));

  Future<void> _loadFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r == null) return;
    final text = await File(r.files.single.path!).readAsString();
    final parsed = parseHits(text);
    setState(() {
      _entries.clear();
      _entries.addAll(parsed);
      _checked = _active = _expired = _invalid = 0;
    });
    _toast('${parsed.length} entradas cargadas');
  }

  Future<void> _startCheck() async {
    if (_entries.isEmpty) { _toast('Carga un archivo primero'); return; }
    // Reset
    for (final e in _entries) {
      e.status = 'CHECKING'; e.checked = false;
      e.panelVerified = false; e.live = 0; e.vod = 0; e.series = 0;
    }
    setState(() {
      _checking = true; _paused = false;
      _checked = _active = _expired = _invalid = 0;
      _t0 = DateTime.now();
    });
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        _checked = _entries.where((e) => e.checked).length;
        _active = _entries.where((e) => e.status == 'ACTIVE').length;
        _expired = _entries.where((e) => e.status == 'EXPIRED').length;
        _invalid = _entries.where((e) => e.status == 'INVALID' || e.status == 'ERROR').length;
      });
    });
    await _runCheck();
  }

  Future<void> _runCheck() async {
    int pos = 0, active = 0;
    final done = Completer<void>();
    void chk() { if (pos >= _entries.length && active == 0 && !done.isCompleted) done.complete(); }

    Future<void> work(HitEntry e) async {
      while (_paused && _checking) await Future.delayed(const Duration(milliseconds: 100));
      if (!_checking) { active--; chk(); return; }
      await checkEntry(e);
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 10));
      active--; chk();
    }

    while (pos < _entries.length && _checking) {
      if (active < _threads && !_paused) { active++; work(_entries[pos++]); }
      else await Future.delayed(const Duration(milliseconds: 20));
    }

    await done.future.timeout(const Duration(hours: 2), onTimeout: () {});
    _timer?.cancel();
    if (mounted) setState(() => _checking = false);
    _toast('Completado — $_active activas');
  }

  List<HitEntry> get _filtered {
    switch (_filter) {
      case 1: return _entries.where((e) => e.status == 'ACTIVE').toList();
      case 2: return _entries.where((e) => e.status == 'EXPIRED').toList();
      case 3: return _entries.where((e) => e.status == 'INVALID' || e.status == 'ERROR').toList();
      default: return _entries;
    }
  }

  Future<void> _exportAll() async => _export(_entries);
  Future<void> _exportActive() async => _export(_entries.where((e) => e.status == 'ACTIVE').toList());

  Future<void> _export(List<HitEntry> list) async {
    if (list.isEmpty) { _toast('Sin entradas para exportar'); return; }
    final buf = StringBuffer('JsusChecker — Export\n${'='*50}\n\n');
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      buf.writeln('[${i+1}] ${e.status}');
      buf.writeln('USER   : ${e.username}');
      buf.writeln('PASS   : ${e.password}');
      buf.writeln('SERVER : ${e.panel}');
      buf.writeln('EXPIRA : ${e.expira}');
      buf.writeln('CONEX  : ${e.activ}/${e.conex}');
      if (e.panelVerified) {
        buf.writeln('CANALES: ${e.live}');
        buf.writeln('VOD    : ${e.vod}');
        buf.writeln('SERIES : ${e.series}');
      }
      if (e.timezone.isNotEmpty) buf.writeln('ZONA   : ${e.timezone}');
      buf.writeln('M3U    : ${e.m3u}');
      buf.writeln('${'─'*40}\n');
    }
    final dir = await getExternalStorageDirectory();
    final file = File('${dir!.path}/JsusChecker_${DateTime.now().toIso8601String().split('T')[0]}.txt');
    await file.writeAsString(buf.toString());
    await Share.shareXFiles([XFile(file.path)]);
    _toast('${list.length} entradas exportadas');
  }

  Future<void> _exportSingle(HitEntry e) async {
    final buf = StringBuffer();
    buf.writeln('STATUS : ${e.status}');
    buf.writeln('USER   : ${e.username}');
    buf.writeln('PASS   : ${e.password}');
    buf.writeln('SERVER : ${e.panel}');
    buf.writeln('EXPIRA : ${e.expira}');
    buf.writeln('CONEX  : ${e.activ}/${e.conex}');
    if (e.panelVerified) {
      buf.writeln('CANALES: ${e.live}');
      buf.writeln('VOD    : ${e.vod}');
      buf.writeln('SERIES : ${e.series}');
    }
    buf.writeln('M3U    : ${e.m3u}');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    _toast('Copiado al portapapeles');
  }

  String get _elapsed {
    if (_t0 == null) return '00:00:00';
    final d = DateTime.now().difference(_t0!);
    return '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
  }

  double get _pct => _entries.isNotEmpty ? _checked / _entries.length : 0;

  String _fn(int n) => n >= 1000 ? '${(n/1000).toStringAsFixed(1)}k' : '$n';

  Color _stColor(String st) {
    switch (st) {
      case 'ACTIVE': return cG;
      case 'EXPIRED': return cOr;
      case 'INVALID': return cRe;
      case 'ERROR': return cRe;
      default: return cDg;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cBg,
    body: Stack(children: [
      // Matrix
      Positioned.fill(child: CustomPaint(painter: _MatrixPainter(_drops, _chars))),
      // Vignette
      Positioned.fill(child: Container(decoration: BoxDecoration(
        gradient: RadialGradient(center: Alignment.center, radius: 1.1,
          colors: [Colors.transparent, cBg.withOpacity(0.7)])))),
      // Content
      SafeArea(child: Column(children: [
        _header(),
        _statsBar(),
        if (_entries.isNotEmpty) _filterBar(),
        Expanded(child: _entries.isEmpty ? _emptyState() : _list()),
        _bottomBar(),
      ])),
    ]),
  );

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.95),
      border: Border(bottom: BorderSide(color: cG.withOpacity(0.2))),
    ),
    child: Row(children: [
      AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cG.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 12)],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(9),
          child: Image.asset('android-icon/icon.png',
            errorBuilder: (_, __, ___) => Container(color: cBg2,
              child: const Center(child: Text('✓', style: TextStyle(color: cG, fontSize: 20)))))),
      )),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedBuilder(animation: _glow, builder: (_, __) => ShaderMask(
          shaderCallback: (b) => LinearGradient(colors: [cG, cCy, cG]).createShader(b),
          child: const Text('JsusChecker', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)))),
        Text('IPTV Account Verifier v1.0',
          style: TextStyle(fontSize: 8, color: cDg.withOpacity(0.8), letterSpacing: 2)),
      ])),
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (_checking ? cG : cDg).withOpacity(0.08),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: (_checking ? cG : cDg).withOpacity(0.4)),
          boxShadow: [BoxShadow(color: (_checking ? cG : cDg).withOpacity(_checking ? _pulse.value * 0.3 : 0.1), blurRadius: 10)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _checking ? cG : cDg,
            boxShadow: [BoxShadow(color: (_checking ? cG : cDg).withOpacity(_pulse.value), blurRadius: 6)])),
          const SizedBox(width: 5),
          Text(_checking ? 'CHECKING' : 'IDLE',
            style: TextStyle(fontSize: 9, color: _checking ? cG : cDg,
              letterSpacing: 1.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ]),
      )),
    ]),
  );

  Widget _statsBar() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.85),
      border: Border(bottom: BorderSide(color: cBr)),
    ),
    child: Column(children: [
      if (_checking || _checked > 0) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          AnimatedBuilder(animation: _glow, builder: (_, __) => Text(
            '${(_pct*100).toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 14, color: cG, fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 10)]))),
          Text('$_checked / ${_entries.length}',
            style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')),
          Text(_elapsed, style: const TextStyle(fontSize: 10, color: cCy, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 6),
        Stack(children: [
          Container(height: 6, decoration: BoxDecoration(color: cBr, borderRadius: BorderRadius.circular(3))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 6,
            width: (MediaQuery.of(context).size.width - 20) * _pct,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(colors: [Color(0xFF003310), cG]),
              boxShadow: [BoxShadow(color: cG.withOpacity(0.5), blurRadius: 6)],
            ),
          ),
        ]),
        const SizedBox(height: 10),
      ],
      Row(children: [
        Expanded(child: _statBox('TOTAL', '${_entries.length}', cCy)),
        const SizedBox(width: 6),
        Expanded(child: _statBox('ACTIVAS', '$_active', cG)),
        const SizedBox(width: 6),
        Expanded(child: _statBox('VENCIDAS', '$_expired', cOr)),
        const SizedBox(width: 6),
        Expanded(child: _statBox('INVÁLIDAS', '$_invalid', cRe)),
      ]),
    ]),
  );

  Widget _statBox(String label, String val, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: c.withOpacity(0.06),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: c.withOpacity(0.25)),
    ),
    child: Column(children: [
      Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c,
        fontFamily: 'monospace', shadows: [Shadow(color: c, blurRadius: 10)])),
      Text(label, style: TextStyle(fontSize: 7, color: c.withOpacity(0.6), letterSpacing: 1.5)),
    ]),
  );

  Widget _filterBar() => Container(
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.9),
      border: Border(bottom: BorderSide(color: cBr)),
    ),
    child: Row(children: [
      _filterBtn('TODAS', 0),
      _filterBtn('ACTIVAS', 1),
      _filterBtn('VENCIDAS', 2),
      _filterBtn('INVÁLIDAS', 3),
    ]),
  );

  Widget _filterBtn(String label, int idx) => Expanded(child: GestureDetector(
    onTap: () => setState(() => _filter = idx),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _filter == idx ? _filterColor(idx).withOpacity(0.1) : Colors.transparent,
        border: Border(bottom: BorderSide(
          color: _filter == idx ? _filterColor(idx) : Colors.transparent, width: 2))),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1,
          color: _filter == idx ? _filterColor(idx) : cDg, fontFamily: 'monospace')),
    ),
  ));

  Color _filterColor(int idx) {
    switch (idx) {
      case 1: return cG;
      case 2: return cOr;
      case 3: return cRe;
      default: return cCy;
    }
  }

  Widget _emptyState() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    AnimatedBuilder(animation: _pulse, builder: (_, __) => Text('[ CHECKER ]',
      style: TextStyle(fontSize: 18, color: cG.withOpacity(_pulse.value * 0.6),
        fontFamily: 'monospace', letterSpacing: 4,
        shadows: [Shadow(color: cG.withOpacity(_pulse.value * 0.4), blurRadius: 20)]))),
    const SizedBox(height: 12),
    Text('Carga un archivo .txt con hits', style: TextStyle(fontSize: 11, color: cDg, fontFamily: 'monospace')),
    const SizedBox(height: 4),
    Text('Formatos: USER/PASS/SERVER o M3U', style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.6), fontFamily: 'monospace')),
  ]));

  Widget _list() => ListView.builder(
    padding: const EdgeInsets.all(8),
    itemCount: _filtered.length,
    itemBuilder: (_, i) => _entryCard(_filtered[i]),
  );

  Widget _entryCard(HitEntry e) {
    final c = _stColor(e.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.88),
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: c, width: 3),
          top: BorderSide(color: c.withOpacity(0.2)),
          right: BorderSide(color: c.withOpacity(0.1)),
          bottom: BorderSide(color: c.withOpacity(0.1)),
        ),
        boxShadow: [BoxShadow(color: c.withOpacity(0.08), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: c.withOpacity(0.07),
            border: Border(bottom: BorderSide(color: c.withOpacity(0.15)))),
          child: Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(
              shape: BoxShape.circle, color: c,
              boxShadow: [BoxShadow(color: c, blurRadius: 4)])),
            const SizedBox(width: 6),
            Text(e.status, style: TextStyle(fontSize: 10, color: c,
              fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 2)),
            const Spacer(),
            if (e.status == 'CHECKING')
              SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(c)))
            else
              Text(e.expira, style: TextStyle(fontSize: 9, color: c.withOpacity(0.7),
                fontFamily: 'monospace')),
          ]),
        ),
        // Credentials
        Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 6), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row('USER', e.username, cG),
          _row('PASS', e.password, cCy),
          _row('HOST', e.panel, cMg),
          if (e.status == 'ACTIVE') ...[
            const SizedBox(height: 4),
            Wrap(spacing: 5, runSpacing: 3, children: [
              _badge('CON:${e.activ}/${e.conex}', cCy),
              if (e.timezone.isNotEmpty) _badge('TZ:${e.timezone}', cMg),
            ]),
          ],
          // Panel info
          if (e.panelVerified) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: cBr),
              ),
              child: Row(children: [
                Expanded(child: _panelStat('📺 CANALES', _fn(e.live), cG)),
                Container(width: 1, height: 28, color: cBr),
                Expanded(child: _panelStat('🎬 VOD', _fn(e.vod), cCy)),
                Container(width: 1, height: 28, color: cBr),
                Expanded(child: _panelStat('📺 SERIES', _fn(e.series), cMg)),
              ]),
            ),
          ] else if (e.status == 'ACTIVE' && !e.panelVerified) ...[
            const SizedBox(height: 6),
            Row(children: [
              const SizedBox(width: 10, height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: cG)),
              const SizedBox(width: 6),
              Text('Verificando panel...', style: TextStyle(fontSize: 8, color: cDg, fontFamily: 'monospace')),
            ]),
          ],
        ])),
        // Actions
        Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 8), child: Row(children: [
          _actionBtn('📋 COPIAR', cCy, () => _exportSingle(e)),
          const SizedBox(width: 6),
          _actionBtn('📺 M3U', cG, () {
            Clipboard.setData(ClipboardData(text: e.m3u));
            _toast('M3U copiado');
          }),
          const SizedBox(width: 6),
          _actionBtn('🔄', cMg, () async {
            setState(() { e.status = 'CHECKING'; e.checked = false; e.panelVerified = false; });
            await checkEntry(e);
            if (mounted) setState(() {});
            _toast('Re-verificado');
          }),
        ])),
      ]),
    );
  }

  Widget _row(String k, String v, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(children: [
      Text('$k: ', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
      Expanded(child: Text(v, style: TextStyle(fontSize: 9, color: c, fontFamily: 'monospace',
        shadows: [Shadow(color: c.withOpacity(0.4), blurRadius: 4)]),
        overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(2),
      border: Border.all(color: c.withOpacity(0.25))),
    child: Text(t, style: TextStyle(fontSize: 8, color: c, fontFamily: 'monospace')));

  Widget _panelStat(String label, String val, Color c) => Column(children: [
    Text(val, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c,
      fontFamily: 'monospace', shadows: [Shadow(color: c, blurRadius: 8)])),
    Text(label, style: TextStyle(fontSize: 7, color: c.withOpacity(0.7), letterSpacing: 0.5)),
  ]);

  Widget _actionBtn(String label, Color c, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(3),
        border: Border.all(color: c.withOpacity(0.3))),
      child: Text(label, style: TextStyle(fontSize: 9, color: c,
        fontWeight: FontWeight.bold, fontFamily: 'monospace'))));

  Widget _bottomBar() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.97),
      border: Border(top: BorderSide(color: cG.withOpacity(0.2))),
    ),
    child: Row(children: [
      Expanded(child: _btn('📂 CARGAR', cCy, _loadFile)),
      const SizedBox(width: 8),
      Expanded(child: _btn(
        _checking ? (_paused ? '▶ RESUME' : '⏸ PAUSE') : '⚡ VERIFICAR',
        _checking ? (_paused ? cG : cYe) : cG,
        _checking
          ? () => setState(() => _paused = !_paused)
          : _startCheck)),
      const SizedBox(width: 8),
      Expanded(child: _btn('💾 ACTIVAS', cG, _exportActive)),
      const SizedBox(width: 8),
      _btn('⬛', cRe,
        () { setState(() => _checking = false); _timer?.cancel(); },
        small: true),
    ]),
  );

  Widget _btn(String label, Color c, VoidCallback onTap, {bool small = false}) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: EdgeInsets.symmetric(vertical: small ? 10 : 10, horizontal: small ? 10 : 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withOpacity(0.06), c.withOpacity(0.12)]),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: c.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: c.withOpacity(0.12), blurRadius: 10)]),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold,
          letterSpacing: 1, fontFamily: 'monospace',
          shadows: [Shadow(color: c, blurRadius: 8)]))));
}

class _MatrixPainter extends CustomPainter {
  final List<List<double>> drops;
  final List<List<String>> chars;
  static const ch = '01ABCDEFアイウエオ<>{}[]|/*';
  _MatrixPainter(this.drops, this.chars);
  @override
  void paint(Canvas canvas, Size size) {
    for (var c = 0; c < drops.length; c++) {
      for (var r = 0; r < drops[c].length; r++) {
        final a = drops[c][r];
        if (a <= 0) continue;
        final color = cG.withOpacity(a * 0.3);
        final tp = TextPainter(
          text: TextSpan(text: chars[c][r],
            style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace')),
          textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(c * 14.0, r * 14.0));
      }
    }
  }
  @override
  bool shouldRepaint(_MatrixPainter old) => true;
}
