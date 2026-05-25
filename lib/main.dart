import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const App());

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

final _client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
const _uas = [
  'Mozilla/5.0 (Linux; Android 13) Chrome/120.0',
  'VLC/3.0.20', 'TiviMate/4.7.0', 'okhttp/4.12.0',
];
String _ua() => _uas[DateTime.now().millisecondsSinceEpoch % _uas.length];

const _secret = 'JsusChecker2026_X9K#mP@zQ7_SECRETO';

int _djbHash(String data) {
  var h = 5381;
  for (final ch in data.codeUnits) {
    h = ((h << 5) + h + ch) & 0xFFFFFFFF;
  }
  return h;
}

String _toB36(int n) {
  const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  var result = '';
  var x = n.abs();
  if (x == 0) return '0';
  while (x > 0) {
    result = chars[x % 36] + result;
    x ~/= 36;
  }
  return result.padLeft(15, '0');
}

class LicResult {
  final bool ok;
  final String msg;
  LicResult(this.ok, this.msg);
}

LicResult verifyKey(String devId, String key) {
  try {
    final parts = key.toUpperCase().split('-');
    if (parts.length != 5 || parts[0] != 'JSUS') return LicResult(false, 'Formato invalido');
    final exp = parts[4];
    if (exp.length != 8) return LicResult(false, 'Fecha invalida');
    final expDate = DateTime(
      int.parse(exp.substring(0, 4)),
      int.parse(exp.substring(4, 6)),
      int.parse(exp.substring(6, 8)));
    if (expDate.isBefore(DateTime.now())) return LicResult(false, 'Clave vencida');
    final data = '$devId:$exp:$_secret';
    final h = _djbHash(data);
    final hStr = _toB36(h);
    final expected = 'JSUS-${hStr.substring(0,5)}-${hStr.substring(5,10)}-${hStr.substring(10,15)}-$exp';
    if (key.toUpperCase() == expected) {
      final fmt = '${expDate.day.toString().padLeft(2,"0")}/${expDate.month.toString().padLeft(2,"0")}/${expDate.year}';
      return LicResult(true, 'Activa hasta $fmt');
    }
    return LicResult(false, 'Clave incorrecta para este dispositivo');
  } catch (_) {
    return LicResult(false, 'Clave invalida');
  }
}

class LicStatus {
  final bool active, trial;
  final String msg, devId;
  LicStatus({required this.active, this.trial = false, required this.msg, required this.devId});
}

Future<LicStatus> checkLicense() async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  if (!prefs.containsKey('inst')) {
    await prefs.setString('inst', now.toIso8601String());
  }
  final inst = DateTime.parse(prefs.getString('inst')!);
  final trialEnd = inst.add(const Duration(days: 3));
  var devId = prefs.getString('dev_id') ?? '';
  if (devId.isEmpty) {
    devId = 'JSUS' + now.millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    await prefs.setString('dev_id', devId);
  }
  final key = prefs.getString('lic_key') ?? '';
  if (key.isNotEmpty) {
    final r = verifyKey(devId, key);
    if (r.ok) return LicStatus(active: true, msg: r.msg, devId: devId);
    await prefs.remove('lic_key');
  }
  if (now.isBefore(trialEnd)) {
    final rem = trialEnd.difference(now);
    final d = rem.inDays;
    final h = rem.inHours % 24;
    final msg = d > 0 ? '$d dias de prueba' : '${h}h de prueba';
    return LicStatus(active: true, trial: true, msg: msg, devId: devId);
  }
  return LicStatus(active: false, msg: 'Prueba vencida', devId: devId);
}

Future<String> activateLicense(String key) async {
  final prefs = await SharedPreferences.getInstance();
  final devId = prefs.getString('dev_id') ?? '';
  final r = verifyKey(devId, key.trim());
  if (r.ok) {
    await prefs.setString('lic_key', key.trim().toUpperCase());
    return '✓ \${r.msg}';
  }
  return '✗ \${r.msg}';
}

class CheckResult {
  String status = '', expira = '', creado = '', conex = '', activ = '';
  String timezone = '', username = '', password = '', server = '', streamType = '';
  int live = 0, vod = 0, series = 0;
  bool panelVerified = false;
  String rawUrl = '', m3u = '', error = '';
}

Future<Map<String, dynamic>?> _checkAcc(String panel, String user, String pass) async {
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      final url = panel + '/player_api.php?username=' + Uri.encodeComponent(user) + '&password=' + Uri.encodeComponent(pass);
      final client = HttpClient();
      client.badCertificateCallback = (_, __, ___) => true;
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', _ua());
      req.headers.set('Accept', '*/*');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode >= 500) { client.close(); continue; }
      final body = await res.transform(utf8.decoder).join();
      client.close();
      try {
        final data = jsonDecode(body);
        if (data is Map<String, dynamic>) return data;
      } catch (_) {
        if (body.contains('"auth":1') || body.contains('"status":"Active"')) {
          return {'user_info': {'auth': 1, 'status': 'Active'}, 'server_info': {}};
        }
      }
      return null;
    } catch (e) {
      if (attempt == 2) return null;
      await Future.delayed(const Duration(seconds: 2));
    }
  }
  return null;
}

Future<int> _cnt(String panel, String user, String pass, String action) async {
  try {
    final url = '$panel/player_api.php?username=\${Uri.encodeComponent(user)}&password=\${Uri.encodeComponent(pass)}&action=$action';
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    final res = await req.close().timeout(const Duration(seconds: 30));
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body);
    if (data is List) return data.length;
  } catch (_) {}
  return 0;
}

Future<CheckResult> checkUrl(String raw) async {
  final r = CheckResult();
  r.rawUrl = raw.trim();
  try {
    final uri = Uri.parse(raw.trim());
    // Siempre incluir el puerto si está en la URL
    final port = (uri.port != 0 && uri.port != 80 && uri.port != 443)
      ? ':' + uri.port.toString()
      : (uri.port == 80 || uri.port == 443) ? '' : '';
    // Para puertos no estandar siempre incluir
    final portStr = uri.hasPort ? ':' + uri.port.toString() : '';
    r.server = uri.scheme + '://' + uri.host + portStr;
    r.streamType = uri.queryParameters['type'] ?? 'm3u_plus';
    r.username = Uri.decodeComponent(uri.queryParameters['username'] ?? '');
    r.password = Uri.decodeComponent(uri.queryParameters['password'] ?? '');
    r.m3u = raw.trim();
    if (r.username.isEmpty || r.password.isEmpty) {
      r.status = 'ERROR';
      r.error = 'No se encontraron credenciales en la URL';
      return r;
    }
    final data = await _checkAcc(r.server, r.username, r.password);
    if (data == null) {
      r.status = 'ERROR';
      r.error = 'Sin respuesta del servidor';
      return r;
    }
    final ui = (data['user_info'] as Map?) ?? {};
    final si = (data['server_info'] as Map?) ?? {};
    final auth = ui['auth'];
    final st = ui['status']?.toString().toLowerCase().trim() ?? '';
    final ok = auth == 1 || auth == '1' || auth == true ||
      ['active','activo','enabled','1','premium','trial','free'].contains(st);
    if (!ok || st == 'banned' || st == 'disabled') {
      r.status = (st == 'expired' || st == 'vencido') ? 'VENCIDA' : 'INVALIDA';
      return r;
    }
    final ts = ui['exp_date'];
    if (ts == null || int.tryParse(ts.toString()) == null || int.parse(ts.toString()) <= 0) {
      r.expira = 'Ilimitado';
    } else {
      final exp = DateTime.fromMillisecondsSinceEpoch(int.parse(ts.toString()) * 1000);
      final d1 = exp.day.toString().padLeft(2, '0');
      final m1 = exp.month.toString().padLeft(2, '0');
      r.expira = '\$d1/\$m1/\${exp.year}';
      if (exp.isBefore(DateTime.now())) {
        r.status = 'VENCIDA';
        return r;
      }
    }
    final tc = ui['created_at'];
    if (tc != null && int.tryParse(tc.toString()) != null && int.parse(tc.toString()) > 0) {
      final cre = DateTime.fromMillisecondsSinceEpoch(int.parse(tc.toString()) * 1000);
      final d2 = cre.day.toString().padLeft(2, '0');
      final m2 = cre.month.toString().padLeft(2, '0');
      r.creado = '\$d2/\$m2/\${cre.year}';
    }
    r.status = 'ACTIVA';
    r.conex = ui['max_connections']?.toString() ?? '?';
    r.activ = ui['active_cons']?.toString() ?? '0';
    r.timezone = si['timezone']?.toString() ?? '';
    final results = await Future.wait([
      _cnt(r.server, r.username, r.password, 'get_live_streams'),
      _cnt(r.server, r.username, r.password, 'get_vod_categories'),
      _cnt(r.server, r.username, r.password, 'get_series_categories'),
    ]);
    r.live = results[0];
    r.vod = results[1];
    r.series = results[2];
    r.panelVerified = true;
  } catch (e) {
    r.status = 'ERROR';
    r.error = e.toString();
  }
  return r;
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JsusChecker',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: cBg,
      colorScheme: const ColorScheme.dark(primary: cG),
      fontFamily: 'monospace',
    ),
    home: const SplashScreen(),
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SpS();
}

class _SpS extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(_ac);
    _init();
  }

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    final status = await checkLicense();
    if (!mounted) return;
    if (status.active) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomeScreen(licMsg: status.msg, isTrial: status.trial)));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => LicenseScreen(devId: status.devId)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cBg,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _glow,
        builder: (_, __) => Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cG.withOpacity(_glow.value * 0.6), width: 2),
            boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 25)]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('android-icon/icon.png',
              errorBuilder: (_, __, ___) => const Center(
                child: Text('✓', style: TextStyle(color: cG, fontSize: 36))))))),
      const SizedBox(height: 20),
      AnimatedBuilder(
        animation: _glow,
        builder: (_, __) => Text('JsusChecker',
          style: TextStyle(fontSize: 24, color: cG, fontFamily: 'monospace',
            fontWeight: FontWeight.bold, letterSpacing: 3,
            shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)]))),
      const SizedBox(height: 16),
      const CircularProgressIndicator(color: cG, strokeWidth: 2),
    ])),
  );
}

class LicenseScreen extends StatefulWidget {
  final String devId;
  const LicenseScreen({super.key, required this.devId});
  @override
  State<LicenseScreen> createState() => _LicS();
}

class _LicS extends State<LicenseScreen> with SingleTickerProviderStateMixin {
  final _keyCtrl = TextEditingController();
  String _msg = '';
  bool _loading = false, _showId = false;
  late AnimationController _ac;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(_ac);
  }

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  Future<void> _activate() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) { setState(() => _msg = 'Ingresa tu clave'); return; }
    setState(() { _loading = true; _msg = ''; });
    final result = await activateLicense(key);
    setState(() { _loading = false; _msg = result; });
    if (result.startsWith('✓')) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomeScreen(licMsg: result, isTrial: false)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _glow,
              builder: (_, __) => Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cRe.withOpacity(0.5), width: 2),
                  boxShadow: [BoxShadow(color: cRe.withOpacity(_glow.value * 0.15), blurRadius: 20)]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset('android-icon/icon.png',
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('🔒', style: TextStyle(fontSize: 36))))))),
            const SizedBox(height: 16),
            const Text('JsusChecker', style: TextStyle(fontSize: 22, color: cG,
              fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 3)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: cRe.withOpacity(0.1), borderRadius: BorderRadius.circular(2),
                border: Border.all(color: cRe.withOpacity(0.3))),
              child: const Text('LICENCIA REQUERIDA', style: TextStyle(fontSize: 10, color: cRe,
                letterSpacing: 3, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cBg2.withOpacity(0.9), borderRadius: BorderRadius.circular(6),
                border: Border.all(color: cBr)),
              child: Column(children: [
                Text('Tu periodo de prueba de 3 dias ha vencido.',
                  style: TextStyle(fontSize: 11, color: cDg, fontFamily: 'monospace'),
                  textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text('Contacta al desarrollador para obtener tu clave.',
                  style: TextStyle(fontSize: 10, color: cDg.withOpacity(0.7), fontFamily: 'monospace'),
                  textAlign: TextAlign.center),
              ])),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _showId = !_showId),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cBg2, borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: cCy.withOpacity(0.2))),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('MI DEVICE ID ', style: TextStyle(fontSize: 9, color: cDg, letterSpacing: 2)),
                    Text(_showId ? '▲' : '▼', style: const TextStyle(color: cCy, fontSize: 10)),
                  ]),
                  if (_showId) ...[
                    const SizedBox(height: 8),
                    Text(widget.devId, style: const TextStyle(fontSize: 12, color: cCy,
                      fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.devId));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('ID copiado', style: TextStyle(color: cG)),
                          backgroundColor: cBg2,
                          duration: Duration(seconds: 1)));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: cCy.withOpacity(0.1), borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: cCy.withOpacity(0.3))),
                        child: const Text('📋 COPIAR ID', style: TextStyle(fontSize: 10, color: cCy,
                          fontFamily: 'monospace', fontWeight: FontWeight.bold)))),
                  ],
                ]))),
            const SizedBox(height: 16),
            TextField(
              controller: _keyCtrl,
              style: const TextStyle(color: cG, fontSize: 12, fontFamily: 'monospace', letterSpacing: 1),
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'JSUS-XXXXX-XXXXX-XXXXX-XXXXXXXX',
                hintStyle: TextStyle(color: cDg.withOpacity(0.4), fontSize: 10),
                filled: true, fillColor: Colors.black54,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: cG.withOpacity(0.3))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: cG.withOpacity(0.3))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: cG, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14))),
            const SizedBox(height: 10),
            if (_msg.isNotEmpty) Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_msg.startsWith('✓') ? cG : cRe).withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: (_msg.startsWith('✓') ? cG : cRe).withOpacity(0.3))),
              child: Text(_msg, style: TextStyle(fontSize: 11,
                color: _msg.startsWith('✓') ? cG : cRe,
                fontFamily: 'monospace', fontWeight: FontWeight.bold),
                textAlign: TextAlign.center)),
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: _glow,
              builder: (_, __) => GestureDetector(
                onTap: _loading ? null : _activate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cG.withOpacity(0.07), cG.withOpacity(0.15)]),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: cG.withOpacity(0.6), width: 1.5),
                    boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 20)]),
                  child: _loading
                    ? const Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: cG, strokeWidth: 2)))
                    : Text('[ ACTIVAR LICENCIA ]', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 3,
                        fontFamily: 'monospace', color: cG,
                        shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 12)]))))),
          ]),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String licMsg;
  final bool isTrial;
  const HomeScreen({super.key, this.licMsg = '', this.isTrial = false});
  @override
  State<HomeScreen> createState() => _HS();
}

class _HS extends State<HomeScreen> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  CheckResult? _result;
  bool _loading = false;
  final _history = <CheckResult>[];
  late AnimationController _glowAc, _pulseAc;
  late Animation<double> _glow, _pulse;
  final _rnd = Random();
  List<List<double>> _drops = [];
  List<List<String>> _chars = [];
  Timer? _matTimer;
  static const _mch = '01ABCDEFabc<>{}[]';

  @override
  void initState() {
    super.initState();
    _glowAc = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(_glowAc);
    _pulseAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0).animate(_pulseAc);
    _initMatrix();
    _matTimer = Timer.periodic(const Duration(milliseconds: 70), (_) => _tickMatrix());
  }

  void _initMatrix() {
    const cols = 28, rows = 60;
    _drops = List.generate(cols, (_) => List.generate(rows, (_) => 0.0));
    _chars = List.generate(cols, (_) => List.generate(rows, (_) => _mch[_rnd.nextInt(_mch.length)]));
  }

  void _tickMatrix() {
    if (!mounted) return;
    setState(() {
      for (var c = 0; c < _drops.length; c++) {
        if (_rnd.nextDouble() < 0.03) _drops[c][0] = 1.0;
        for (var r = _drops[c].length - 1; r > 0; r--) {
          if (_drops[c][r-1] > 0.5 && _drops[c][r] < 0.1) {
            _drops[c][r] = _drops[c][r-1] * 0.95;
          }
          if (_drops[c][r] > 0) {
            _drops[c][r] -= 0.015;
            if (_rnd.nextDouble() < 0.08) {
              _chars[c][r] = _mch[_rnd.nextInt(_mch.length)];
            }
          }
        }
        _drops[c][0] *= 0.92;
      }
    });
  }

  @override
  void dispose() {
    _glowAc.dispose();
    _pulseAc.dispose();
    _matTimer?.cancel();
    super.dispose();
  }

  void _showActivation() async {
    final ctrl = TextEditingController();
    String msg = '';
    final prefs = await SharedPreferences.getInstance();
    final devIdVal = prefs.getString('dev_id') ?? 'Cargando...';
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: cBg2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: cMg.withOpacity(0.4))),
          title: const Text('🔑 ACTIVAR LICENCIA', style: TextStyle(color: cMg,
            fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // Device ID
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cBg, borderRadius: BorderRadius.circular(4),
                border: Border.all(color: cCy.withOpacity(0.2))),
              child: Column(children: [
                Text('TU DEVICE ID', style: TextStyle(fontSize: 8, color: cDg, letterSpacing: 2)),
                const SizedBox(height: 6),
                SelectableText(devIdVal, style: const TextStyle(fontSize: 11, color: cCy,
                  fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: devIdVal));
                    Navigator.pop(ctx);
                    _toast('Device ID copiado');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: cCy.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: cCy.withOpacity(0.3))),
                    child: const Text('📋 COPIAR ID', style: TextStyle(fontSize: 9, color: cCy,
                      fontFamily: 'monospace', fontWeight: FontWeight.bold)))),
              ])),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: cG, fontSize: 11, fontFamily: 'monospace'),
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'JSUS-XXXXX-XXXXX-XXXXX-XXXXXXXX',
                hintStyle: TextStyle(color: cDg.withOpacity(0.4), fontSize: 10),
                filled: true, fillColor: Colors.black54,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: cG.withOpacity(0.3))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: cG.withOpacity(0.3))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3),
                  borderSide: const BorderSide(color: cG)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10))),
            if (msg.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(msg, style: TextStyle(fontSize: 10,
                color: msg.startsWith('✓') ? cG : cRe,
                fontFamily: 'monospace'), textAlign: TextAlign.center),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CANCELAR', style: TextStyle(color: cRe, fontFamily: 'monospace'))),
            TextButton(
              onPressed: () async {
                final result = await activateLicense(ctrl.text.trim());
                setS(() => msg = result);
                if (result.startsWith('✓')) {
                  await Future.delayed(const Duration(seconds: 1));
                  if (ctx.mounted) Navigator.pop(ctx);
                  final status = await checkLicense();
                  if (mounted) {
                    Navigator.pushReplacement(context, MaterialPageRoute(
                      builder: (_) => HomeScreen(licMsg: status.msg, isTrial: status.trial)));
                  }
                }
              },
              child: Text('ACTIVAR', style: TextStyle(color: cG,
                fontFamily: 'monospace', fontWeight: FontWeight.bold))),
          ],
        )));
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('> $m', style: const TextStyle(color: cG, fontFamily: 'monospace')),
      backgroundColor: cBg2,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: const BorderSide(color: cG))));
  }

  Future<void> _check() async {
    final url = _ctrl.text.trim();
    if (url.isEmpty) { _toast('Pega una URL primero'); return; }
    setState(() { _loading = true; _result = null; });
    final r = await checkUrl(url);
    setState(() {
      _result = r;
      _loading = false;
      if (!_history.any((h) => h.rawUrl == r.rawUrl)) {
        _history.insert(0, r);
        if (_history.length > 20) _history.removeLast();
      }
    });
  }

  Color get _sc {
    switch (_result?.status) {
      case 'ACTIVA': return cG;
      case 'VENCIDA': return cOr;
      default: return cRe;
    }
  }

  String _fn(int n) => n >= 1000 ? '\${(n/1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _MP(_drops, _chars))),
        Positioned.fill(child: Container(decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center, radius: 1.1,
            colors: [Colors.transparent, cBg.withOpacity(0.75)])))),
        SafeArea(child: Column(children: [
          _hdr(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: widget.isTrial ? cYe.withOpacity(0.06) : cG.withOpacity(0.04),
            child: Row(children: [
              Text(widget.isTrial ? '⏳ ' : '✓ ', style: const TextStyle(fontSize: 12)),
              Expanded(child: Text(widget.licMsg.isNotEmpty ? widget.licMsg : 'Licencia activa',
                style: TextStyle(fontSize: 10,
                  color: widget.isTrial ? cYe : cG,
                  fontFamily: 'monospace'))),
              GestureDetector(
                onTap: () => _showActivation(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cMg.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: cMg.withOpacity(0.4))),
                  child: const Text('🔑 ACTIVAR', style: TextStyle(fontSize: 9, color: cMg,
                    fontFamily: 'monospace', fontWeight: FontWeight.bold)))),
            ])),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _urlInput(),
              const SizedBox(height: 12),
              if (_loading) _loadingCard(),
              if (_result != null && !_loading) _resultCard(),
              if (_history.isNotEmpty && _result == null && !_loading) _historySection(),
            ]))),
        ])),
      ]),
    );
  }

  Widget _hdr() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.95),
        border: Border(bottom: BorderSide(color: cG.withOpacity(0.2)))),
      child: Row(children: [
        AnimatedBuilder(
          animation: _glow,
          builder: (_, __) => Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cG.withOpacity(0.4)),
              boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 12)]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset('android-icon/icon.png',
                errorBuilder: (_, __, ___) => Container(color: cBg2,
                  child: const Center(child: Text('✓', style: TextStyle(color: cG, fontSize: 20)))))))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ShaderMask(
            shaderCallback: (b) => LinearGradient(colors: [cG, cCy, cG]).createShader(b),
            child: const Text('JsusChecker', style: TextStyle(fontSize: 18,
              fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2))),
          Text('URL Checker v2.0 - M3U · M3U_Plus · TS',
            style: TextStyle(fontSize: 8, color: cDg.withOpacity(0.8), letterSpacing: 1)),
        ])),
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (_loading ? cYe : _result?.status == 'ACTIVA' ? cG : cDg).withOpacity(0.08),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: (_loading ? cYe : _result?.status == 'ACTIVA' ? cG : cDg).withOpacity(0.4))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _loading ? cYe : _result?.status == 'ACTIVA' ? cG : cDg,
                boxShadow: [BoxShadow(
                  color: (_loading ? cYe : _result?.status == 'ACTIVA' ? cG : cDg).withOpacity(_pulse.value),
                  blurRadius: 6)])),
              const SizedBox(width: 5),
              Text(_loading ? 'CHECKING' : _result?.status ?? 'IDLE',
                style: TextStyle(fontSize: 9,
                  color: _loading ? cYe : _result?.status == 'ACTIVA' ? cG : cDg,
                  letterSpacing: 1.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ]))),
      ]));
  }

  Widget _urlInput() {
    return Container(
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.9), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cG.withOpacity(0.2))),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: cG.withOpacity(0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border(bottom: BorderSide(color: cBr))),
          child: Row(children: [
            Container(width: 2, height: 12, color: cG, margin: const EdgeInsets.only(right: 8)),
            const Text('PEGAR URL', style: TextStyle(fontSize: 10, color: cDg,
              letterSpacing: 2, fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
              onTap: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  _ctrl.text = data!.text!;
                  _toast('URL pegada');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cCy.withOpacity(0.08), borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: cCy.withOpacity(0.3))),
                child: const Text('📋 PEGAR', style: TextStyle(fontSize: 9, color: cCy,
                  fontFamily: 'monospace', fontWeight: FontWeight.bold)))),
          ])),
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: cG, fontSize: 11, fontFamily: 'monospace'),
            maxLines: 3, minLines: 1,
            onSubmitted: (_) => _check(),
            decoration: InputDecoration(
              hintText: 'http://server.com:8080/get.php?username=xxx&password=yyy&type=m3u_plus',
              hintStyle: TextStyle(color: cDg.withOpacity(0.4), fontSize: 10),
              filled: true, fillColor: Colors.black54,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(3),
                borderSide: BorderSide(color: cG.withOpacity(0.3))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3),
                borderSide: BorderSide(color: cG.withOpacity(0.3))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: cG, width: 1.5)),
              contentPadding: const EdgeInsets.all(10)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: AnimatedBuilder(
            animation: _glow,
            builder: (_, __) => GestureDetector(
              onTap: _check,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cG.withOpacity(0.06), cG.withOpacity(0.14)]),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: cG.withOpacity(0.6), width: 1.5),
                  boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 20)]),
                child: Text('[ VERIFICAR ]', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                    letterSpacing: 4, fontFamily: 'monospace', color: cG,
                    shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 12)])))))),
      ]));
  }

  Widget _loadingCard() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.9), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cBr)),
      child: Column(children: [
        AnimatedBuilder(
          animation: _glow,
          builder: (_, __) => Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cG.withOpacity(_glow.value), width: 2),
              boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 15)]),
            child: const Center(child: CircularProgressIndicator(color: cG, strokeWidth: 2)))),
        const SizedBox(height: 16),
        Text('VERIFICANDO...', style: TextStyle(fontSize: 12, color: cG,
          fontFamily: 'monospace', letterSpacing: 3,
          shadows: [const Shadow(color: cG, blurRadius: 6)])),
        const SizedBox(height: 4),
        Text('Comprobando estado...', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
      ]));
  }

  Widget _resultCard() {
    final r = _result!;
    final c = _sc;
    return Container(
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.9), borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: c, width: 4),
          top: BorderSide(color: c.withOpacity(0.3)),
          right: BorderSide(color: c.withOpacity(0.1)),
          bottom: BorderSide(color: c.withOpacity(0.1))),
        boxShadow: [BoxShadow(color: c.withOpacity(0.1), blurRadius: 20)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border(bottom: BorderSide(color: c.withOpacity(0.2)))),
          child: Row(children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: c,
                  boxShadow: [BoxShadow(color: c.withOpacity(_pulse.value), blurRadius: 10)]))),
            const SizedBox(width: 10),
            Text(r.status, style: TextStyle(fontSize: 16, color: c,
              fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 3,
              shadows: [Shadow(color: c, blurRadius: 10)])),
            const Spacer(),
            if (r.expira.isNotEmpty) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cYe.withOpacity(0.1), borderRadius: BorderRadius.circular(2),
                border: Border.all(color: cYe.withOpacity(0.3))),
              child: Text('📅 \${r.expira}', style: const TextStyle(fontSize: 9, color: cYe,
                fontFamily: 'monospace', fontWeight: FontWeight.bold))),
          ])),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sec('CREDENCIALES'),
          _row('USUARIO', r.username, cG),
          _row('CONTRASENA', r.password, cCy),
          _row('SERVIDOR', r.server, cMg),
          _row('TIPO', r.streamType.toUpperCase(), cDg),
          const SizedBox(height: 10),
          _sec('ESTADO'),
          if (r.expira.isNotEmpty) _row('VENCIMIENTO', r.expira, r.expira == 'Ilimitado' ? cG : cYe),
          if (r.creado.isNotEmpty) _row('CREADO', r.creado, cDg),
          if (r.conex.isNotEmpty) _row('CONEXIONES', '\${r.activ}/\${r.conex}', cCy),
          if (r.timezone.isNotEmpty) _row('TIMEZONE', r.timezone, cMg),
          if (r.error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cRe.withOpacity(0.08), borderRadius: BorderRadius.circular(3),
                border: Border.all(color: cRe.withOpacity(0.2))),
              child: Text(r.error, style: const TextStyle(fontSize: 9, color: cRe, fontFamily: 'monospace'))),
          ],
          if (r.panelVerified) ...[
            const SizedBox(height: 10),
            _sec('CONTENIDO DEL PANEL'),
            Row(children: [
              Expanded(child: _pbox('📺', 'CANALES', _fn(r.live), cG)),
              const SizedBox(width: 8),
              Expanded(child: _pbox('🎬', 'VOD', _fn(r.vod), cCy)),
              const SizedBox(width: 8),
              Expanded(child: _pbox('📺', 'SERIES', _fn(r.series), cMg)),
            ]),
          ] else if (r.status == 'ACTIVA') ...[
            const SizedBox(height: 10),
            Row(children: [
              const SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: cG)),
              const SizedBox(width: 8),
              Text('Verificando contenido...', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
            ]),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _btn('📋 COPIAR TODO', cCy, () {
              var t = 'STATUS: \${r.status}\nUSER: \${r.username}\nPASS: \${r.password}\nSERVER: \${r.server}\n';
              if (r.expira.isNotEmpty) t += 'EXP: \${r.expira}\n';
              if (r.conex.isNotEmpty) t += 'CONEX: \${r.activ}/\${r.conex}\n';
              if (r.timezone.isNotEmpty) t += 'TZ: \${r.timezone}\n';
              if (r.panelVerified) t += 'CANALES: \${r.live}\nVOD: \${r.vod}\nSERIES: \${r.series}\n';
              t += 'M3U: \${r.m3u}';
              Clipboard.setData(ClipboardData(text: t));
              _toast('Copiado');
            })),
            const SizedBox(width: 8),
            Expanded(child: _btn('📺 M3U', cG, () {
              Clipboard.setData(ClipboardData(text: r.m3u));
              _toast('M3U copiado');
            })),
          ]),
          const SizedBox(height: 6),
          _btn('🔄 NUEVA VERIFICACION', cMg, () {
            setState(() { _result = null; _ctrl.clear(); });
          }),
        ])),
      ]));
  }

  Widget _historySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(width: 2, height: 12, color: cDg, margin: const EdgeInsets.only(right: 8)),
          Text('HISTORIAL', style: TextStyle(fontSize: 10, color: cDg,
            letterSpacing: 3, fontWeight: FontWeight.bold)),
        ])),
      for (final h in _history) GestureDetector(
        onTap: () { _ctrl.text = h.rawUrl; _check(); },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cBg2.withOpacity(0.8), borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(
              color: h.status == 'ACTIVA' ? cG : h.status == 'VENCIDA' ? cOr : cRe, width: 3))),
          child: Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: h.status == 'ACTIVA' ? cG : h.status == 'VENCIDA' ? cOr : cRe)),
            const SizedBox(width: 8),
            Expanded(child: Text(h.server.isNotEmpty ? h.server : h.rawUrl,
              style: const TextStyle(fontSize: 10, color: cCy, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis)),
            Text(h.status, style: TextStyle(fontSize: 9,
              color: h.status == 'ACTIVA' ? cG : h.status == 'VENCIDA' ? cOr : cRe,
              fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ]))),
    ]);
  }

  Widget _sec(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Row(children: [
        Container(width: 2, height: 10, color: cG, margin: const EdgeInsets.only(right: 6)),
        Text(t, style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.8),
          letterSpacing: 2, fontWeight: FontWeight.bold))]));
  }

  Widget _row(String k, String v, Color c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 100, child: Text('$k:', style: TextStyle(fontSize: 9,
          color: cDg.withOpacity(0.7), fontFamily: 'monospace'))),
        Expanded(child: Text(v, style: TextStyle(fontSize: 10, color: c,
          fontFamily: 'monospace', fontWeight: FontWeight.w500,
          shadows: [Shadow(color: c.withOpacity(0.4), blurRadius: 4)]),
          overflow: TextOverflow.ellipsis))]));
  }

  Widget _pbox(String icon, String label, String val, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.06), borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: c.withOpacity(0.08), blurRadius: 8)]),
      child: Column(children: [
        Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c,
          fontFamily: 'monospace', shadows: [Shadow(color: c, blurRadius: 12)])),
        const SizedBox(height: 2),
        Text('$icon $label', style: TextStyle(fontSize: 8, color: c.withOpacity(0.7), letterSpacing: 1))]));
  }

  Widget _btn(String label, Color c, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.withOpacity(0.06), c.withOpacity(0.12)]),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: c.withOpacity(0.45)),
          boxShadow: [BoxShadow(color: c.withOpacity(0.1), blurRadius: 10)]),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold,
            letterSpacing: 2, fontFamily: 'monospace',
            shadows: [Shadow(color: c, blurRadius: 6)]))));
  }
}

class _MP extends CustomPainter {
  final List<List<double>> drops;
  final List<List<String>> chars;
  _MP(this.drops, this.chars);
  @override
  void paint(Canvas canvas, Size size) {
    for (var c = 0; c < drops.length; c++) {
      for (var r = 0; r < drops[c].length; r++) {
        final a = drops[c][r];
        if (a <= 0) continue;
        final tp = TextPainter(
          text: TextSpan(text: chars[c][r],
            style: TextStyle(color: cG.withOpacity(a * 0.3), fontSize: 11, fontFamily: 'monospace')),
          textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(c * 14.0, r * 14.0));
      }
    }
  }
  @override
  bool shouldRepaint(_MP old) => true;
}
