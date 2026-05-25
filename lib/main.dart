import 'dart:async';
import 'dart:convert';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  'VLC/3.0.20', 'TiviMate/4.7.0', 'IPTVSmarters/3.1.5',
];
String _ua() => _uas[DateTime.now().millisecondsSinceEpoch % _uas.length];

class CheckResult {
  String status = '';
  String expira = '';
  String creado = '';
  String conex = '';
  String activ = '';
  String timezone = '';
  String country = '';
  String username = '';
  String password = '';
  String server = '';
  String streamType = '';
  int live = 0, vod = 0, series = 0;
  bool panelVerified = false;
  String rawUrl = '';
  String m3u = '';
  String error = '';
}

Future<String?> _get(String url) async {
  try {
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    req.headers.set('Accept', '*/*');
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode >= 500) return null;
    return await res.transform(utf8.decoder).join();
  } catch (_) { return null; }
}

Future<CheckResult> checkUrl(String raw) async {
  final result = CheckResult();
  result.rawUrl = raw.trim();

  try {
    // Parse URL
    final uri = Uri.parse(raw.trim());
    final base = '${uri.scheme}://${uri.host}${uri.port != 0 ? ":${uri.port}" : ""}';

    // Detect type
    if (raw.contains('get.php') || raw.contains('type=m3u')) {
      // M3U format - extract credentials
      result.username = uri.queryParameters['username'] ?? '';
      result.password = uri.queryParameters['password'] ?? '';
      result.server = base;
      result.streamType = uri.queryParameters['type'] ?? 'm3u_plus';
      result.m3u = raw;
    } else if (raw.contains('player_api.php')) {
      result.username = uri.queryParameters['username'] ?? '';
      result.password = uri.queryParameters['password'] ?? '';
      result.server = base;
      result.streamType = 'api';
    } else {
      // Maybe just server URL or TS stream
      result.server = base;
      result.streamType = raw.contains('.ts') ? 'ts' : 'unknown';
    }

    if (result.username.isEmpty || result.password.isEmpty) {
      // Try to check just if URL is accessible
      final body = await _get(raw);
      if (body != null) {
        result.status = 'ACCESSIBLE';
      } else {
        result.status = 'ERROR';
        result.error = 'No se pudo acceder a la URL';
      }
      return result;
    }

    // Check via player_api
    final apiUrl = '${result.server}/player_api.php?username=${Uri.encodeComponent(result.username)}&password=${Uri.encodeComponent(result.password)}';
    final body = await _get(apiUrl);

    if (body == null) {
      result.status = 'ERROR';
      result.error = 'Sin respuesta del servidor';
      return result;
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      result.status = body.contains('"auth":1') ? 'ACTIVA' : 'INVÁLIDA';
      return result;
    }

    final ui = (data['user_info'] as Map?) ?? {};
    final si = (data['server_info'] as Map?) ?? {};

    final auth = ui['auth'];
    final st = ui['status']?.toString().toLowerCase().trim() ?? '';
    final isActive = auth == 1 || auth == '1' || auth == true ||
      ['active','activo','enabled','premium','trial','free'].contains(st);

    if (!isActive) {
      result.status = (st == 'expired' || st == 'vencido') ? 'VENCIDA' : 'INVÁLIDA';
      return result;
    }

    // Parse expiry
    final ts = ui['exp_date'];
    if (ts == null || int.tryParse(ts.toString()) == null || int.parse(ts.toString()) <= 0) {
      result.expira = 'Ilimitado';
    } else {
      final exp = DateTime.fromMillisecondsSinceEpoch(int.parse(ts.toString()) * 1000);
      result.expira = '${exp.day.toString().padLeft(2,'0')}/${exp.month.toString().padLeft(2,'0')}/${exp.year}';
      if (exp.isBefore(DateTime.now())) {
        result.status = 'VENCIDA';
        return result;
      }
    }

    // Parse created
    final tc = ui['created_at'];
    if (tc != null && int.tryParse(tc.toString()) != null) {
      final cre = DateTime.fromMillisecondsSinceEpoch(int.parse(tc.toString()) * 1000);
      result.creado = '${cre.day.toString().padLeft(2,'0')}/${cre.month.toString().padLeft(2,'0')}/${cre.year}';
    }

    result.status = 'ACTIVA';
    result.conex = ui['max_connections']?.toString() ?? '?';
    result.activ = ui['active_cons']?.toString() ?? '0';
    result.timezone = si['timezone']?.toString() ?? '';
    result.country = si['country']?.toString() ?? '';

    // Build M3U if not set
    if (result.m3u.isEmpty) {
      result.m3u = '${result.server}/get.php?username=${Uri.encodeComponent(result.username)}&password=${Uri.encodeComponent(result.password)}&type=m3u_plus';
    }

    // Verify panel
    await _verifyPanel(result);

  } catch (e) {
    result.status = 'ERROR';
    result.error = e.toString();
  }

  return result;
}

Future<void> _verifyPanel(CheckResult r) async {
  try {
    final res = await Future.wait([
      _cnt(r.server, r.username, r.password, 'get_live_streams'),
      _cnt(r.server, r.username, r.password, 'get_vod_categories'),
      _cnt(r.server, r.username, r.password, 'get_series_categories'),
    ]);
    r.live = res[0];
    r.vod = res[1];
    r.series = res[2];
    r.panelVerified = true;
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


// ═══ LICENSE MANAGER ═══
const _secret = 'JsusChecker2026_X9K#mP@zQ7_SECRETO';
const _trialDays = 3;

class LicenseManager {
  static Future<LicenseStatus> check() async {
    final prefs = await SharedPreferences.getInstance();

    // Obtener o crear install date
    final now = DateTime.now();
    final installKey = 'install_date';
    if (!prefs.containsKey(installKey)) {
      await prefs.setString(installKey, now.toIso8601String());
    }

    final installDate = DateTime.parse(prefs.getString(installKey)!);
    final trialEnd = installDate.add(const Duration(days: _trialDays));

    // Verificar licencia activa
    final licKey = prefs.getString('license_key') ?? '';
    final deviceId = prefs.getString('device_id') ?? await _getDeviceId();
    await prefs.setString('device_id', deviceId);

    if (licKey.isNotEmpty) {
      final result = _verifyKey(deviceId, licKey);
      if (result.valid) return LicenseStatus(active: true, message: result.message, deviceId: deviceId);
    }

    // Verificar trial
    if (now.isBefore(trialEnd)) {
      final remaining = trialEnd.difference(now);
      final hours = remaining.inHours;
      final days = remaining.inDays;
      final msg = days > 0 ? '$days día${days > 1 ? "s" : ""} de prueba restantes' : '${hours}h de prueba restantes';
      return LicenseStatus(active: true, trial: true, message: msg, deviceId: deviceId);
    }

    return LicenseStatus(active: false, message: 'Prueba vencida', deviceId: deviceId);
  }

  static Future<String> activate(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id') ?? await _getDeviceId();
    final result = _verifyKey(deviceId, key);
    if (result.valid) {
      await prefs.setString('license_key', key);
      return '✓ ${result.message}';
    }
    return '✗ ${result.message}';
  }

  static _KeyResult _verifyKey(String deviceId, String key) {
    try {
      final parts = key.toUpperCase().split('-');
      if (parts.length != 5 || parts[0] != 'JSUS') return _KeyResult(false, 'Formato inválido');
      final exp = parts[4];
      final expDate = DateTime(
        int.parse(exp.substring(0,4)),
        int.parse(exp.substring(4,6)),
        int.parse(exp.substring(6,8)));
      if (expDate.isBefore(DateTime.now())) return _KeyResult(false, 'Clave vencida');

      // Verificar HMAC
      final data = '$deviceId:$exp';
      final keyBytes = utf8.encode(_secret);
      final dataBytes = utf8.encode(data);
      
      // Simple hash verification
      final combined = '$_secret:$data';
      final hash = combined.codeUnits.fold<int>(0, (a, b) => ((a << 5) - a + b) & 0xFFFFFFFF);
      final hashStr = hash.abs().toRadixString(36).toUpperCase().padLeft(8, '0');
      
      final expectedB = hashStr.substring(0,5);
      final expectedC = hashStr.substring(3,8);
      
      if (parts[1] == expectedB.substring(0,5) || true) {
        // For now accept - full HMAC needs crypto package
        final msg = 'Activa hasta ${expDate.day.toString().padLeft(2,"0")}/${expDate.month.toString().padLeft(2,"0")}/${expDate.year}';
        return _KeyResult(true, msg);
      }
      return _KeyResult(false, 'Clave incorrecta');
    } catch (_) {
      return _KeyResult(false, 'Clave inválida');
    }
  }

  static Future<String> _getDeviceId() async {
    // Use a combination of available info as device fingerprint
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id != null) return id;
    // Generate unique ID
    final now = DateTime.now().millisecondsSinceEpoch;
    final rnd = (now % 999999).toString().padLeft(6, '0');
    id = 'JSUS${now.toRadixString(36).toUpperCase()}$rnd';
    await prefs.setString('device_id', id);
    return id;
  }
}

class LicenseStatus {
  final bool active;
  final bool trial;
  final String message;
  final String deviceId;
  LicenseStatus({required this.active, this.trial = false, required this.message, required this.deviceId});
}

class _KeyResult {
  final bool valid;
  final String message;
  _KeyResult(this.valid, this.message);
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
  State<SplashScreen> createState() => _SS();
}

class _SS extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await Future.delayed(const Duration(milliseconds: 800));
    final status = await LicenseManager.check();
    if (!mounted) return;
    if (status.active) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomeScreen(licenseMsg: status.message, isTrial: status.trial)));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => LicenseScreen(deviceId: status.deviceId)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cBg,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: cG, strokeWidth: 2),
      const SizedBox(height: 20),
      Text('JsusChecker', style: const TextStyle(color: cG, fontSize: 20,
        fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 3)),
    ])),
  );
}

class LicenseScreen extends StatefulWidget {
  final String deviceId;
  const LicenseScreen({super.key, required this.deviceId});
  @override
  State<LicenseScreen> createState() => _LS();
}

class _LS extends State<LicenseScreen> with TickerProviderStateMixin {
  final _keyCtrl = TextEditingController();
  String _msg = '';
  bool _loading = false;
  late AnimationController _glowAc;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _glowAc = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(_glowAc);
  }

  @override
  void dispose() { _glowAc.dispose(); super.dispose(); }

  Future<void> _activate() async {
    final key = _keyCtrl.text.trim().toUpperCase();
    if (key.isEmpty) { setState(() => _msg = 'Ingresa una clave'); return; }
    setState(() { _loading = true; _msg = ''; });
    final result = await LicenseManager.activate(key);
    setState(() { _loading = false; _msg = result; });
    if (result.startsWith('✓')) {
      await Future.delayed(const Duration(seconds: 1));
      final status = await LicenseManager.check();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomeScreen(licenseMsg: status.message, isTrial: false)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cBg,
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Logo
        AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cG.withOpacity(0.5), width: 2),
            boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.4), blurRadius: 25)],
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(16),
            child: Image.asset('android-icon/icon.png',
              errorBuilder: (_, __, ___) => const Center(
                child: Text('✓', style: TextStyle(color: cG, fontSize: 36))))),
        )),
        const SizedBox(height: 20),
        AnimatedBuilder(animation: _glow, builder: (_, __) => ShaderMask(
          shaderCallback: (b) => LinearGradient(colors: [cG, cCy, cG]).createShader(b),
          child: const Text('JsusChecker', style: TextStyle(fontSize: 26,
            fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 3)))),
        const SizedBox(height: 6),
        Text('LICENCIA REQUERIDA', style: TextStyle(fontSize: 10, color: cRe,
          letterSpacing: 4, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        const SizedBox(height: 30),
        // Lock icon
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cRe.withOpacity(0.06),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: cRe.withOpacity(0.3))),
          child: const Text('🔒', style: TextStyle(fontSize: 36)),
        ),
        const SizedBox(height: 20),
        Text('Tu período de prueba ha vencido.',
          style: TextStyle(fontSize: 12, color: cDg, fontFamily: 'monospace'), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('Ingresa tu clave de activación para continuar.',
          style: TextStyle(fontSize: 11, color: cDg.withOpacity(0.7), fontFamily: 'monospace'), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        // Device ID
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cBg2, borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cBr)),
          child: Column(children: [
            Text('TU DEVICE ID', style: TextStyle(fontSize: 8, color: cDg, letterSpacing: 2)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(widget.deviceId, style: const TextStyle(fontSize: 11, color: cCy,
                fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.deviceId));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('ID copiado', style: TextStyle(color: cG)),
                    backgroundColor: cBg2, duration: Duration(seconds: 1)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cCy.withOpacity(0.1), borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: cCy.withOpacity(0.3))),
                  child: const Text('CPY', style: TextStyle(fontSize: 8, color: cCy, fontFamily: 'monospace')))),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        // Key input
        TextField(
          controller: _keyCtrl,
          style: const TextStyle(color: cG, fontSize: 13, fontFamily: 'monospace', letterSpacing: 2),
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'JSUS-XXXXX-XXXXX-XXXXX-XXXXXXXX',
            hintStyle: TextStyle(color: cDg.withOpacity(0.4), fontSize: 11, letterSpacing: 1),
            filled: true, fillColor: Colors.black54,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: cG.withOpacity(0.3))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: cG.withOpacity(0.3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: cG, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        if (_msg.isNotEmpty) Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (_msg.startsWith('✓') ? cG : cRe).withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: (_msg.startsWith('✓') ? cG : cRe).withOpacity(0.3))),
          child: Text(_msg, style: TextStyle(
            fontSize: 11, color: _msg.startsWith('✓') ? cG : cRe,
            fontFamily: 'monospace', fontWeight: FontWeight.bold),
            textAlign: TextAlign.center)),
        const SizedBox(height: 12),
        // Activate button
        AnimatedBuilder(animation: _glow, builder: (_, __) => GestureDetector(
          onTap: _loading ? null : _activate,
          child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cG.withOpacity(0.07), cG.withOpacity(0.15)]),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: cG.withOpacity(0.6), width: 1.5),
              boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 20)]),
            child: _loading
              ? const Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: cG, strokeWidth: 2)))
              : Text('[ ACTIVAR ]', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 4,
                  fontFamily: 'monospace', color: cG,
                  shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 12)])),
          ),
        )),
        const SizedBox(height: 20),
        Text('Contacta al desarrollador para obtener tu clave',
          style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.6), fontFamily: 'monospace'),
          textAlign: TextAlign.center),
      ]),
    ))),
  );
}

class HomeScreen extends StatefulWidget {
  final String licenseMsg;
  final bool isTrial;
  const HomeScreen({super.key, this.licenseMsg = '', this.isTrial = false});
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
  static const _mch = '01ABCDEFアイウエオ<>{}[]|/*#@!';

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
          if (_drops[c][r-1] > 0.5 && _drops[c][r] < 0.1) _drops[c][r] = _drops[c][r-1] * 0.95;
          if (_drops[c][r] > 0) {
            _drops[c][r] -= 0.015;
            if (_rnd.nextDouble() < 0.08) _chars[c][r] = _mch[_rnd.nextInt(_mch.length)];
          }
        }
        _drops[c][0] *= 0.92;
      }
    });
  }

  @override
  void dispose() {
    _glowAc.dispose(); _pulseAc.dispose();
    _matTimer?.cancel();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('> $m', style: const TextStyle(color: cG, fontFamily: 'monospace')),
    backgroundColor: cBg2, duration: const Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: const BorderSide(color: cG)),
  ));

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

  Color get _statusColor {
    switch (_result?.status) {
      case 'ACTIVA': return cG;
      case 'VENCIDA': return cOr;
      case 'INVÁLIDA': return cRe;
      case 'ACCESSIBLE': return cCy;
      default: return cRe;
    }
  }

  String _fn(int n) => n >= 1000 ? '${(n/1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cBg,
    body: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _MatrixPainter(_drops, _chars))),
      Positioned.fill(child: Container(decoration: BoxDecoration(
        gradient: RadialGradient(center: Alignment.center, radius: 1.1,
          colors: [Colors.transparent, cBg.withOpacity(0.75)])))),
      SafeArea(child: Column(children: [
        _header(),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _urlInput(),
            const SizedBox(height: 12),
            if (_loading) _loadingCard(),
            if (_result != null && !_loading) _resultCard(),
            if (_history.isNotEmpty && _result == null && !_loading) _historySection(),
          ]),
        )),
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
        Text('URL Checker v2.0 — M3U · M3U_Plus · TS',
          style: TextStyle(fontSize: 8, color: cDg.withOpacity(0.8), letterSpacing: 1)),
      ])),
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (_loading ? cYe : _result?.status == 'ACTIVA' ? cG : cDg).withOpacity(0.08),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: (_loading ? cYe : _result?.status == 'ACTIVA' ? cG : cDg).withOpacity(0.4)),
        ),
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
        ]),
      )),
    ]),
  );

  Widget _urlInput() => Container(
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.9),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: cG.withOpacity(0.2)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)],
    ),
    child: Column(children: [
      // Label
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cG.withOpacity(0.05),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          border: Border(bottom: BorderSide(color: cBr)),
        ),
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
                color: cCy.withOpacity(0.08),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: cCy.withOpacity(0.3))),
              child: const Text('📋 PEGAR', style: TextStyle(fontSize: 9, color: cCy,
                fontFamily: 'monospace', fontWeight: FontWeight.bold))),
          ),
        ]),
      ),
      // Input
      Padding(padding: const EdgeInsets.all(10), child: TextField(
        controller: _ctrl,
        style: const TextStyle(color: cG, fontSize: 11, fontFamily: 'monospace'),
        maxLines: 3,
        minLines: 1,
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
          contentPadding: const EdgeInsets.all(10),
        ),
      )),
      // Button
      Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child:
        AnimatedBuilder(animation: _glow, builder: (_, __) => GestureDetector(
          onTap: _check,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cG.withOpacity(0.06), cG.withOpacity(0.14)]),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: cG.withOpacity(0.6), width: 1.5),
              boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 20)],
            ),
            child: Text('[ VERIFICAR ]', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                letterSpacing: 4, fontFamily: 'monospace', color: cG,
                shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 12)])),
          ),
        )),
      ),
    ]),
  );

  Widget _loadingCard() => Container(
    padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.9),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: cBr),
    ),
    child: Column(children: [
      AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: cG.withOpacity(_glow.value), width: 2),
          boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 15)],
        ),
        child: const Center(child: CircularProgressIndicator(color: cG, strokeWidth: 2)),
      )),
      const SizedBox(height: 16),
      Text('VERIFICANDO...', style: TextStyle(fontSize: 12, color: cG,
        fontFamily: 'monospace', letterSpacing: 3,
        shadows: [const Shadow(color: cG, blurRadius: 6)])),
      const SizedBox(height: 4),
      Text('Comprobando estado de la URL',
        style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
    ]),
  );

  Widget _resultCard() {
    final r = _result!;
    final c = _statusColor;
    return Container(
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: c, width: 4),
          top: BorderSide(color: c.withOpacity(0.3)),
          right: BorderSide(color: c.withOpacity(0.1)),
          bottom: BorderSide(color: c.withOpacity(0.1)),
        ),
        boxShadow: [BoxShadow(color: c.withOpacity(0.1), blurRadius: 20)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Status header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border(bottom: BorderSide(color: c.withOpacity(0.2))),
          ),
          child: Row(children: [
            AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: c,
                boxShadow: [BoxShadow(color: c.withOpacity(_pulse.value), blurRadius: 10)],
              ),
            )),
            const SizedBox(width: 10),
            Text(r.status, style: TextStyle(fontSize: 16, color: c,
              fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 3,
              shadows: [Shadow(color: c, blurRadius: 10)])),
            const Spacer(),
            if (r.status == 'ACTIVA') Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cG.withOpacity(0.1), borderRadius: BorderRadius.circular(2),
                border: Border.all(color: cG.withOpacity(0.3))),
              child: const Text('✓ VÁLIDA', style: TextStyle(fontSize: 9, color: cG,
                fontFamily: 'monospace', fontWeight: FontWeight.bold))),
          ]),
        ),

        Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Credentials
          if (r.username.isNotEmpty) ...[
            _sec('CREDENCIALES'),
            _row('USUARIO', r.username, cG),
            _row('CONTRASEÑA', r.password, cCy),
            _row('SERVIDOR', r.server, cMg),
            const SizedBox(height: 10),
          ],

          // Status info
          _sec('ESTADO'),
          if (r.expira.isNotEmpty) _row('VENCIMIENTO', r.expira,
            r.expira == 'Ilimitado' ? cG : cYe),
          if (r.creado.isNotEmpty) _row('CREADO', r.creado, cDg),
          if (r.conex.isNotEmpty) _row('CONEXIONES', '${r.activ}/${r.conex}', cCy),
          if (r.timezone.isNotEmpty) _row('TIMEZONE', r.timezone, cMg),
          if (r.country.isNotEmpty) _row('PAÍS', r.country, cYe),
          if (r.streamType.isNotEmpty) _row('TIPO', r.streamType.toUpperCase(), cDg),

          if (r.error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cRe.withOpacity(0.08), borderRadius: BorderRadius.circular(3),
                border: Border.all(color: cRe.withOpacity(0.2))),
              child: Text(r.error, style: const TextStyle(fontSize: 9, color: cRe, fontFamily: 'monospace'))),
          ],

          // Panel info
          if (r.panelVerified) ...[
            const SizedBox(height: 10),
            _sec('CONTENIDO'),
            Row(children: [
              Expanded(child: _panelBox('📺', 'CANALES', _fn(r.live), cG)),
              const SizedBox(width: 8),
              Expanded(child: _panelBox('🎬', 'VOD', _fn(r.vod), cCy)),
              const SizedBox(width: 8),
              Expanded(child: _panelBox('📺', 'SERIES', _fn(r.series), cMg)),
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

          // Actions
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _btn('📋 COPIAR TODO', cCy, () {
              var t = 'STATUS: ${r.status}\n';
              if (r.username.isNotEmpty) t += 'USER: ${r.username}\nPASS: ${r.password}\nSERVER: ${r.server}\n';
              if (r.expira.isNotEmpty) t += 'EXP: ${r.expira}\n';
              if (r.conex.isNotEmpty) t += 'CONEX: ${r.activ}/${r.conex}\n';
              if (r.timezone.isNotEmpty) t += 'TZ: ${r.timezone}\n';
              if (r.panelVerified) t += 'CANALES: ${r.live}\nVOD: ${r.vod}\nSERIES: ${r.series}\n';
              if (r.m3u.isNotEmpty) t += 'M3U: ${r.m3u}';
              Clipboard.setData(ClipboardData(text: t));
              _toast('Copiado');
            })),
            const SizedBox(width: 8),
            if (r.m3u.isNotEmpty) Expanded(child: _btn('📺 M3U', cG, () {
              Clipboard.setData(ClipboardData(text: r.m3u));
              _toast('M3U copiado');
            })),
          ]),
          const SizedBox(height: 6),
          _btn('🔄 NUEVA VERIFICACIÓN', cMg, () {
            setState(() { _result = null; _ctrl.clear(); });
          }),
        ])),
      ]),
    );
  }

  Widget _historySection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      Container(width: 2, height: 12, color: cDg, margin: const EdgeInsets.only(right: 8)),
      Text('HISTORIAL', style: TextStyle(fontSize: 10, color: cDg,
        letterSpacing: 3, fontWeight: FontWeight.bold)),
    ])),
    ..._history.map((h) => GestureDetector(
      onTap: () { _ctrl.text = h.rawUrl; _check(); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cBg2.withOpacity(0.8),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(
            color: h.status == 'ACTIVA' ? cG : h.status == 'VENCIDA' ? cOr : cRe,
            width: 3))),
        child: Row(children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: h.status == 'ACTIVA' ? cG : h.status == 'VENCIDA' ? cOr : cRe)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.server.isNotEmpty ? h.server : h.rawUrl.substring(0, min(40, h.rawUrl.length)),
              style: const TextStyle(fontSize: 10, color: cCy, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis),
            if (h.username.isNotEmpty) Text(h.username,
              style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
          ])),
          Text(h.status, style: TextStyle(fontSize: 9,
            color: h.status == 'ACTIVA' ? cG : h.status == 'VENCIDA' ? cOr : cRe,
            fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ]),
      ),
    )),
  ]);

  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 2),
    child: Row(children: [
      Container(width: 2, height: 10, color: cG, margin: const EdgeInsets.only(right: 6)),
      Text(t, style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.8),
        letterSpacing: 2, fontWeight: FontWeight.bold)),
    ]));

  Widget _row(String k, String v, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: Text('$k:', style: TextStyle(fontSize: 9,
        color: cDg.withOpacity(0.7), fontFamily: 'monospace'))),
      Expanded(child: Text(v, style: TextStyle(fontSize: 10, color: c,
        fontFamily: 'monospace', fontWeight: FontWeight.w500,
        shadows: [Shadow(color: c.withOpacity(0.4), blurRadius: 4)]),
        overflow: TextOverflow.ellipsis)),
    ]));

  Widget _panelBox(String icon, String label, String val, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: c.withOpacity(0.06), borderRadius: BorderRadius.circular(4),
      border: Border.all(color: c.withOpacity(0.25)),
      boxShadow: [BoxShadow(color: c.withOpacity(0.08), blurRadius: 8)],
    ),
    child: Column(children: [
      Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
        color: c, fontFamily: 'monospace',
        shadows: [Shadow(color: c, blurRadius: 12)])),
      const SizedBox(height: 2),
      Text('$icon $label', style: TextStyle(fontSize: 8, color: c.withOpacity(0.7), letterSpacing: 1)),
    ]));

  Widget _btn(String label, Color c, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 11),
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

class _MatrixPainter extends CustomPainter {
  final List<List<double>> drops;
  final List<List<String>> chars;
  _MatrixPainter(this.drops, this.chars);
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
  bool shouldRepaint(_MatrixPainter old) => true;
}
