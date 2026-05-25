import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AnalyzerApp());

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

final _httpClient = HttpClient()..badCertificateCallback = (_, __, ___) => true;

class ServerInfo {
  String host = '';
  String ip = '';
  String country = '';
  String city = '';
  String isp = '';
  String org = '';
  bool isProxy = false;
  bool isHosting = false;
  int ping = -1;
  String panelType = 'Unknown';
  String panelVersion = '';
  String timezone = '';
  List<String> subdomains = [];
  List<String> relatedIPs = [];
  String difficulty = '';
  String proxyRecommendation = '';
  bool isActive = false;
  int port = 0;
  Map<String, dynamic> raw = {};
}

Future<String?> httpGet(String url, {int timeout = 8}) async {
  try {
    final req = await _httpClient.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'Mozilla/5.0 (compatible; ServerAnalyzer/1.0)');
    final res = await req.close().timeout(Duration(seconds: timeout));
    return await res.transform(utf8.decoder).join();
  } catch (_) { return null; }
}

Future<ServerInfo> analyzeServer(String input) async {
  final info = ServerInfo();
  
  // Normalize URL
  var url = input.trim();
  if (!url.startsWith('http')) url = 'http://$url';
  url = url.replaceAll(RegExp(r'/+$'), '');
  
  try {
    final uri = Uri.parse(url);
    info.host = uri.host;
    info.port = uri.port != 0 ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  } catch (_) {
    info.host = url;
    return info;
  }

  // Run all checks in parallel
  await Future.wait([
    _checkPanel(info, url),
    _getIPInfo(info),
    _getSubdomains(info),
    _measurePing(info, url),
  ]);

  _analyzeDifficulty(info);
  return info;
}

Future<void> _checkPanel(ServerInfo info, String url) async {
  try {
    final body = await httpGet('$url/player_api.php?username=test&password=test');
    if (body == null) { info.isActive = false; return; }
    info.isActive = true;
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final si = data['server_info'] as Map? ?? {};
      info.panelType = si['server_protocol'] != null ? 'Xtream Codes' : 'Xtream Compatible';
      info.panelVersion = si['rtmp_port']?.toString() ?? '';
      info.timezone = si['timezone']?.toString() ?? '';
      info.raw = Map<String, dynamic>.from(si);
    } catch (_) {
      if (body.contains('Xtream')) info.panelType = 'Xtream Codes';
      else if (body.contains('stalker')) info.panelType = 'Stalker Middleware';
      else info.panelType = 'Custom Panel';
    }
  } catch (_) { info.isActive = false; }
}

Future<void> _getIPInfo(ServerInfo info) async {
  try {
    // First resolve IP via DNS
    try {
      final addresses = await InternetAddress.lookup(info.host).timeout(const Duration(seconds: 5));
      if (addresses.isNotEmpty) info.ip = addresses.first.address;
    } catch (_) {}
    
    final target = info.ip.isNotEmpty ? info.ip : info.host;
    final body = await httpGet('http://ip-api.com/json/$target?fields=status,country,city,isp,org,proxy,hosting,as');
    if (body == null) return;
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['status'] == 'success') {
      info.country = data['country'] ?? '';
      info.city = data['city'] ?? '';
      info.isp = data['isp'] ?? '';
      info.org = data['org'] ?? '';
      info.isProxy = data['proxy'] ?? false;
      info.isHosting = data['hosting'] ?? false;
    }
  } catch (_) {}
}

Future<void> _getSubdomains(ServerInfo info) async {
  try {
    // HackerTarget subdomain lookup
    final body = await httpGet(
      'https://api.hackertarget.com/hostsearch/?q=${info.host}',
      timeout: 10);
    if (body == null || body.contains('error') || body.contains('API count')) return;
    final lines = body.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final subs = <String>{};
    final ips = <String>{};
    for (final line in lines) {
      final parts = line.split(',');
      if (parts.length >= 2) {
        final sub = parts[0].trim();
        final ip = parts[1].trim();
        if (sub != info.host && sub.isNotEmpty) subs.add(sub);
        if (ip != info.ip && ip.isNotEmpty && RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) {
          ips.add(ip);
        }
      }
    }
    info.subdomains = subs.take(10).toList();
    info.relatedIPs = ips.take(5).toList();
  } catch (_) {}
}

Future<void> _measurePing(ServerInfo info, String url) async {
  try {
    final t0 = DateTime.now();
    await httpGet('$url/player_api.php?username=test&password=test', timeout: 10);
    info.ping = DateTime.now().difference(t0).inMilliseconds;
  } catch (_) { info.ping = -1; }
}

void _analyzeDifficulty(ServerInfo info) {
  int score = 0;
  
  if (info.isHosting) score += 2;
  if (info.isProxy) score += 3;
  if (info.ping > 500) score += 2;
  if (info.ping > 1000) score += 2;
  if (!info.isActive) score += 5;
  
  if (score <= 2) {
    info.difficulty = 'FÁCIL';
    info.proxyRecommendation = 'Sin proxy necesario — conexión directa óptima';
  } else if (score <= 4) {
    info.difficulty = 'MEDIO';
    info.proxyRecommendation = 'Proxy HTTP recomendado para mayor anonimato';
  } else if (score <= 6) {
    info.difficulty = 'DIFÍCIL';
    info.proxyRecommendation = 'Usa proxies rotativos HTTP/SOCKS5 — alta protección';
  } else {
    info.difficulty = 'MUY DIFÍCIL';
    info.proxyRecommendation = 'Proxies residenciales obligatorios — servidor muy protegido';
  }
}

class AnalyzerApp extends StatelessWidget {
  const AnalyzerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JsusAnalyzer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: cBg,
      colorScheme: const ColorScheme.dark(primary: cG),
      fontFamily: 'monospace',
    ),
    home: const AnalyzerScreen(),
  );
}

class AnalyzerScreen extends StatefulWidget {
  const AnalyzerScreen({super.key});
  @override
  State<AnalyzerScreen> createState() => _AS();
}

class _AS extends State<AnalyzerScreen> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  String _groqKey = '';
  bool _useGroq = false;
  ServerInfo? _info;
  bool _loading = false;
  final _chatMessages = <Map<String, String>>[];
  final _chatCtrl = TextEditingController();
  bool _chatLoading = false;
  int _tab = 0;

  late AnimationController _glowAc, _pulseAc;
  late Animation<double> _glow, _pulse;
  final _rnd = Random();
  List<List<double>> _drops = [];
  List<List<String>> _chars = [];
  Timer? _matTimer;
  static const _mch = '01ABCDEFアイウエオ<>{}[]|/*#@';

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
          if (_drops[c][r] > 0) { _drops[c][r] -= 0.015; if (_rnd.nextDouble() < 0.08) _chars[c][r] = _mch[_rnd.nextInt(_mch.length)]; }
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

  Future<void> _analyze() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) { _toast('Ingresa un servidor'); return; }
    setState(() { _loading = true; _info = null; _chatMessages.clear(); });
    final info = await analyzeServer(input);
    setState(() { _info = info; _loading = false; _tab = 1; });
    // Auto welcome message
    _addBotMsg(_generateWelcome(info));
  }

  String _generateWelcome(ServerInfo info) {
    final buf = StringBuffer();
    buf.writeln('Análisis completado para ${info.host}');
    buf.writeln('');
    if (info.isActive) {
      buf.writeln('✓ Servidor ACTIVO — Panel: ${info.panelType}');
      buf.writeln('  Ping: ${info.ping}ms | País: ${info.country}');
      buf.writeln('  Dificultad: ${info.difficulty}');
    } else {
      buf.writeln('✗ Servidor NO RESPONDE');
      buf.writeln('  Puede estar caído o bloqueando conexiones');
    }
    buf.writeln('');
    buf.writeln('Puedes preguntarme cualquier cosa sobre este servidor.');
    return buf.toString();
  }

  void _addBotMsg(String msg) {
    setState(() => _chatMessages.add({'role': 'bot', 'text': msg}));
  }

  Future<void> _sendChat(String question) async {
    if (_info == null) { _toast('Analiza un servidor primero'); return; }
    final q = question.trim();
    if (q.isEmpty) return;
    setState(() {
      _chatMessages.add({'role': 'user', 'text': q});
      _chatLoading = true;
    });
    _chatCtrl.clear();

    String response;
    if (_useGroq && _groqKey.isNotEmpty) {
      response = await _groqResponse(q, _info!) ?? _generateResponse(q, _info!);
    } else {
      await Future.delayed(const Duration(milliseconds: 400));
      response = _generateResponse(q, _info!);
    }
    setState(() {
      _chatMessages.add({'role': 'bot', 'text': response});
      _chatLoading = false;
    });
  }

  Future<String?> _groqResponse(String question, ServerInfo info) async {
    try {
      final systemPrompt = '''Eres un experto en servidores IPTV y ciberseguridad.
Tienes acceso a esta información del servidor analizado:
- Host: \${info.host}
- IP: \${info.ip}
- País: \${info.country}, Ciudad: \${info.city}
- ISP: \${info.isp}
- Panel: \${info.panelType}
- Ping: \${info.ping}ms
- Activo: \${info.isActive}
- Dificultad escaneo: \${info.difficulty}
- Es datacenter: \${info.isHosting}
- Es proxy/VPN: \${info.isProxy}
- Subdominios: \${info.subdomains.join(", ")}
- IPs relacionadas: \${info.relatedIPs.join(", ")}
- Recomendación proxies: \${info.proxyRecommendation}

Responde de forma concisa y técnica en español.
Usa emojis y formato legible. Max 200 palabras.''';

      final body = jsonEncode({
        'model': 'llama3-8b-8192',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ..._chatMessages.map((m) => {
            'role': m['role'] == 'bot' ? 'assistant' : 'user',
            'content': m['text'],
          }),
          {'role': 'user', 'content': question},
        ],
        'max_tokens': 400,
        'temperature': 0.7,
      });

      final req = await _httpClient.postUrl(Uri.parse('https://api.groq.com/openai/v1/chat/completions'));
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Authorization', 'Bearer \$_groqKey');
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 15));
      final resBody = await res.transform(utf8.decoder).join();
      final data = jsonDecode(resBody) as Map<String, dynamic>;
      return data['choices'][0]['message']['content'] as String?;
    } catch (e) {
      return null;
    }
  }

  String _generateResponse(String q, ServerInfo info) {
    final ql = q.toLowerCase();

    if (ql.contains('dificil') || ql.contains('difícil') || ql.contains('dificultad') || ql.contains('escanear')) {
      return '''Dificultad de escaneo: ${info.difficulty}

${info.isHosting ? '⚠ Servidor en datacenter — puede tener rate limiting' : '✓ No parece datacenter protegido'}
${info.isProxy ? '⚠ Detectado como proxy/VPN' : '✓ IP residencial/comercial'}
Ping: ${info.ping > 0 ? '${info.ping}ms' : 'No medido'}

${info.proxyRecommendation}''';
    }

    if (ql.contains('proxy') || ql.contains('proxies')) {
      return '''Recomendación de proxies para ${info.host}:

${info.proxyRecommendation}

${info.difficulty == 'FÁCIL' ? '→ Conexión directa funcionará bien\n→ User-Agent aleatorio es suficiente' :
  info.difficulty == 'MEDIO' ? '→ Proxies HTTP gratuitos pueden funcionar\n→ Rotar cada 50-100 peticiones' :
  '→ Usa proxies SOCKS5 de pago\n→ Rotar cada 20-30 peticiones\n→ Prefiere IPs residenciales'}''';
    }

    if (ql.contains('subdomain') || ql.contains('subdominio') || ql.contains('servidor paralelo') || ql.contains('otros servidor')) {
      if (info.subdomains.isEmpty && info.relatedIPs.isEmpty) {
        return 'No se encontraron subdominios públicos para ${info.host}.\n\nEsto puede significar:\n→ El servidor usa una sola IP\n→ Los subdominios están ocultos\n→ Dominio registrado privadamente';
      }
      final buf = StringBuffer('Servidores relacionados encontrados:\n\n');
      if (info.subdomains.isNotEmpty) {
        buf.writeln('📡 Subdominios (${info.subdomains.length}):');
        for (final s in info.subdomains) buf.writeln('  → $s');
      }
      if (info.relatedIPs.isNotEmpty) {
        buf.writeln('\n🌐 IPs relacionadas:');
        for (final ip in info.relatedIPs) buf.writeln('  → $ip');
      }
      return buf.toString();
    }

    if (ql.contains('país') || ql.contains('pais') || ql.contains('ubicacion') || ql.contains('ubicación') || ql.contains('donde')) {
      return '''Ubicación del servidor:

📍 País: ${info.country.isNotEmpty ? info.country : 'Desconocido'}
🏙 Ciudad: ${info.city.isNotEmpty ? info.city : 'Desconocido'}
🏢 ISP: ${info.isp.isNotEmpty ? info.isp : 'Desconocido'}
🔧 Organización: ${info.org.isNotEmpty ? info.org : 'Desconocido'}
🌐 IP: ${info.ip.isNotEmpty ? info.ip : 'No resuelta'}
${info.isHosting ? '⚠ Servidor en hosting/datacenter' : '✓ No es datacenter conocido'}''';
    }

    if (ql.contains('panel') || ql.contains('software') || ql.contains('version') || ql.contains('versión')) {
      return '''Información del panel:

🔧 Tipo: ${info.panelType}
${info.timezone.isNotEmpty ? '🕐 Timezone: ${info.timezone}' : ''}
${info.panelVersion.isNotEmpty ? '📌 Puerto RTMP: ${info.panelVersion}' : ''}
${info.isActive ? '✓ Panel respondiendo correctamente' : '✗ Panel no responde'}

${info.panelType.contains('Xtream') ? 'Xtream Codes es el panel IPTV más común.\nSoporta API para verificar cuentas directamente.' : ''}''';
    }

    if (ql.contains('ping') || ql.contains('velocidad') || ql.contains('rapido') || ql.contains('rápido') || ql.contains('lento')) {
      final pingInfo = info.ping <= 0 ? 'No medido' :
        info.ping < 100 ? '${info.ping}ms ⚡ Excelente' :
        info.ping < 300 ? '${info.ping}ms ✓ Bueno' :
        info.ping < 600 ? '${info.ping}ms ⚠ Lento' :
        '${info.ping}ms ✗ Muy lento';
      return '''Velocidad del servidor:

⚡ Ping: $pingInfo

${info.ping > 0 && info.ping < 100 ? 'Servidor muy rápido — ideal para escanear con muchos bots' :
  info.ping > 0 && info.ping < 300 ? 'Velocidad normal — usa 20-50 bots' :
  info.ping > 0 ? 'Servidor lento — reduce bots a 10-20 máximo' :
  'No se pudo medir la velocidad'}''';
    }

    if (ql.contains('activ') || ql.contains('funcion') || ql.contains('caido') || ql.contains('caído')) {
      return '${info.isActive ? '✓ El servidor está ACTIVO y respondiendo' : '✗ El servidor NO responde'}\n\n${info.isActive ? 'Ping: ${info.ping}ms\nPanel: ${info.panelType}' : 'Posibles causas:\n→ Servidor caído temporalmente\n→ Bloqueando tu IP\n→ Puerto cerrado'}';
    }

    if (ql.contains('bots') || ql.contains('hilos') || ql.contains('threads') || ql.contains('cuantos')) {
      final recommended = info.ping <= 0 ? 20 :
        info.ping < 100 ? 50 :
        info.ping < 300 ? 30 :
        info.ping < 600 ? 15 : 10;
      return '''Bots recomendados para ${info.host}:

🤖 Recomendado: $recommended threads
⚡ Ping actual: ${info.ping > 0 ? '${info.ping}ms' : 'No medido'}
🛡 Dificultad: ${info.difficulty}

${info.difficulty == 'FÁCIL' ? '→ Puedes subir hasta 100 bots sin problema' :
  info.difficulty == 'MEDIO' ? '→ Mantén entre 20-50 para evitar bans' :
  '→ Usa máximo 10-20 bots con proxies'}''';
    }

    if (ql.contains('donde') && (ql.contains('proxy') || ql.contains('proxies') || ql.contains('encuentro'))) {
      return 'Fuentes GRATUITAS de proxies:\n\n'
        '🌐 GITHUB (actualizadas diario):\n'
        '→ TheSpeedX/PROXY-List\n'
        '   HTTP, SOCKS4, SOCKS5\n\n'
        '→ proxifly/free-proxy-list\n'
        '   Múltiples protocolos\n\n'
        '→ MuRongPIG/Proxy-Master\n'
        '   HTTP y SOCKS5\n\n'
        '→ monosans/proxy-list\n'
        '   Verificados automáticamente\n\n'
        '→ clarketm/proxy-list\n'
        '   Lista clásica confiable\n\n'
        '🔧 WEBS:\n'
        '→ proxy-list.download\n'
        '→ free-proxy-list.net\n'
        '→ hidemy.name/en/proxy-list\n'
        '→ spys.one/en/\n\n'
        '💡 Descarga el .txt y cárgalo\n'
        'en JsusIPTV Scanner tab PROXY';
    }

    if (ql.contains('socks') || ql.contains('tipo de proxy') || ql.contains('diferencia') || ql.contains('http proxy')) {
      return 'Tipos de proxies:\n\n'
        '🔵 HTTP:\n'
        '→ Solo tráfico web básico\n'
        '→ Más rápido pero menos seguro\n'
        '→ Para servidores FÁCIL\n\n'
        '🟡 SOCKS4:\n'
        '→ Más versátil que HTTP\n'
        '→ Soporta TCP\n'
        '→ Para servidores MEDIO\n\n'
        '🟢 SOCKS5:\n'
        '→ El mejor para IPTV scanning\n'
        '→ UDP + autenticación\n'
        '→ Para servidores DIFÍCIL\n\n'
        '🔴 RESIDENCIAL:\n'
        '→ IPs de usuarios reales\n'
        '→ Casi imposible de detectar\n'
        '→ De pago — para MUY DIFÍCIL\n\n'
        'Para \${info.host} (\${info.difficulty}):\n'
        '\${info.difficulty == "FÁCIL" ? "→ HTTP es suficiente" : info.difficulty == "MEDIO" ? "→ SOCKS4/5 recomendado" : "→ SOCKS5 o residencial obligatorio"}';
    }

    if (ql.contains('vpn') || ql.contains('anonimo') || ql.contains('anónimo') || ql.contains('detectar')) {
      return 'Cómo evitar ser detectado:\n\n'
        '🛡 TÉCNICAS:\n'
        '→ Rotar proxies cada 30-50 requests\n'
        '→ User-Agents aleatorios\n'
        '→ Delay entre peticiones (5-50ms)\n'
        '→ Max 1000 CPM en protegidos\n\n'
        '🔒 VPNs GRATUITAS:\n'
        '→ ProtonVPN — sin límite datos\n'
        '→ Windscribe — 10GB/mes\n'
        '→ Tunnelbear — 500MB/mes\n'
        '→ hide.me — 10GB/mes\n\n'
        '⚠ SEÑALES DE BAN:\n'
        '→ Muchos ERRORs seguidos\n'
        '→ Respuestas 429 o 403\n'
        '→ Timeout repentino\n\n'
        '\${info.host}: \${info.proxyRecommendation}';
    }

    if (ql.contains('m3u') || ql.contains('reproducir') || ql.contains('ver') || ql.contains('reproductor')) {
      return 'Reproductores recomendados:\n\n'
        '📺 TiviMate (Android TV) ⭐⭐⭐⭐⭐\n'
        '→ El mejor para IPTV\n'
        '→ EPG, grabación, grupos\n\n'
        '📱 IPTV Smarters Pro ⭐⭐⭐⭐\n'
        '→ Android/iOS/PC\n'
        '→ Soporte Xtream Codes directo\n\n'
        '🖥 VLC ⭐⭐⭐\n'
        '→ Gratis todas las plataformas\n'
        '→ Abre M3U directamente\n\n'
        '🎬 Kodi + PVR IPTV ⭐⭐⭐⭐\n'
        '→ Muy personalizable\n'
        '→ Gratis y open source\n\n'
        '💡 Con las cuentas del scanner:\n'
        'Copia el M3U y ábrelo en TiviMate';
    }

    if (ql.contains('timeout') || ql.contains('configurar') || ql.contains('ajustar') || ql.contains('parametros')) {
      final rec = info.ping <= 0 ? 10 : info.ping < 100 ? 8 : info.ping < 300 ? 10 : info.ping < 600 ? 15 : 20;
      final bots = info.ping < 100 ? '50-100' : info.ping < 300 ? '20-50' : '10-20';
      return 'Configuración óptima para \${info.host}:\n\n'
        '⚙ PARÁMETROS:\n'
        '→ Timeout: \${rec}s\n'
        '→ Bots: \$bots\n'
        '→ Delay: \${info.difficulty == "FÁCIL" ? "5ms" : info.difficulty == "MEDIO" ? "20ms" : "50ms"}\n'
        '→ Proxies: \${info.difficulty == "FÁCIL" ? "No necesario" : "Recomendado"}\n\n'
        '📊 BASADO EN:\n'
        '→ Ping: \${info.ping > 0 ? "\${info.ping}ms" : "No medido"}\n'
        '→ Dificultad: \${info.difficulty}\n\n'
        '💡 Si obtienes muchos ERROR:\n'
        '→ Reduce bots a la mitad\n'
        '→ Aumenta timeout 5s más\n'
        '→ Agrega proxies rotativos';
    }

    if (ql.contains('puerto') || ql.contains('port')) {
      return 'Puertos comunes en servidores IPTV:\n\n'
        '🔌 MÁS USADOS:\n'
        '→ :80    — HTTP estándar\n'
        '→ :443   — HTTPS\n'
        '→ :8080  — Alternativo HTTP\n'
        '→ :8880  — Xtream Codes clásico\n'
        '→ :2082  — Panel cPanel\n'
        '→ :25461 — Alternativo popular\n'
        '→ :1935  — RTMP streaming\n\n'
        '\${info.host} usa puerto: \${info.port}\n\n'
        '💡 Algunos servidores tienen el mismo\n'
        'contenido en múltiples puertos.';
    }

    // Default response
    return '''Sobre ${info.host}:

Estado: ${info.isActive ? 'ACTIVO' : 'INACTIVO'}
País: ${info.country.isNotEmpty ? info.country : 'Desconocido'}
Panel: ${info.panelType}
Ping: ${info.ping > 0 ? '${info.ping}ms' : 'No medido'}
Dificultad: ${info.difficulty}

Puedes preguntarme sobre:
→ Dificultad de escaneo
→ Proxies recomendados
→ Subdominios/servidores paralelos
→ Ubicación del servidor
→ Bots recomendados
→ Velocidad/ping''';
  }

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
        _inputBar(),
        if (_info != null) _tabBar(),
        Expanded(child: _loading ? _loadingView() : _info == null ? _emptyView() : _tabContent()),
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
              child: const Center(child: Text('🔍', style: TextStyle(fontSize: 20)))))),
      )),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedBuilder(animation: _glow, builder: (_, __) => ShaderMask(
          shaderCallback: (b) => LinearGradient(colors: [cG, cCy, cG]).createShader(b),
          child: const Text('JsusAnalyzer', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)))),
        Text('IPTV Server Intelligence v1.0',
          style: TextStyle(fontSize: 8, color: cDg.withOpacity(0.8), letterSpacing: 2)),
      ])),
      GestureDetector(
        onTap: _showGroqSetup,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: _useGroq ? cMg.withOpacity(0.1) : cBr,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: _useGroq ? cMg.withOpacity(0.5) : cBr)),
          child: Text(_useGroq ? '⚡ AI ON' : '⚡ AI',
            style: TextStyle(fontSize: 9, color: _useGroq ? cMg : cDg,
              fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ),
      ),
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (_info?.isActive == true ? cG : cDg).withOpacity(0.08),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: (_info?.isActive == true ? cG : cDg).withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _info?.isActive == true ? cG : cDg,
            boxShadow: [BoxShadow(color: (_info?.isActive == true ? cG : cDg).withOpacity(_pulse.value), blurRadius: 6)])),
          const SizedBox(width: 5),
          Text(_info?.isActive == true ? 'ONLINE' : 'IDLE',
            style: TextStyle(fontSize: 9, color: _info?.isActive == true ? cG : cDg,
              letterSpacing: 1.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ]),
      )),
    ]),
  );

  void _showGroqSetup() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: cBg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: cG)),
      title: const Text('⚡ Groq AI Config', style: TextStyle(color: cG, fontFamily: 'monospace', fontSize: 14)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Ingresa tu API Key de Groq\nconsole.groq.com',
          style: TextStyle(color: cDg, fontSize: 11, fontFamily: 'monospace')),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKeyCtrl,
          style: const TextStyle(color: cG, fontSize: 11, fontFamily: 'monospace'),
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'gsk_...',
            hintStyle: TextStyle(color: cDg.withOpacity(0.5)),
            filled: true, fillColor: Colors.black54,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: const BorderSide(color: cG)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCELAR', style: TextStyle(color: cRe, fontFamily: 'monospace'))),
        TextButton(
          onPressed: () {
            setState(() {
              _groqKey = _apiKeyCtrl.text.trim();
              _useGroq = _groqKey.isNotEmpty;
            });
            Navigator.pop(context);
            _toast(_groqKey.isNotEmpty ? '✓ Groq AI activado' : 'Key vacía');
          },
          child: Text('ACTIVAR', style: TextStyle(color: cG, fontFamily: 'monospace'))),
      ],
    ));
  }

  Widget _inputBar() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.9),
      border: Border(bottom: BorderSide(color: cBr)),
    ),
    child: Row(children: [
      Expanded(child: TextField(
        controller: _ctrl,
        style: const TextStyle(color: cG, fontSize: 12, fontFamily: 'monospace'),
        onSubmitted: (_) => _analyze(),
        decoration: InputDecoration(
          hintText: 'http://servidor.com:8080',
          hintStyle: TextStyle(color: cDg.withOpacity(0.5), fontSize: 11),
          filled: true, fillColor: Colors.black54,
          prefixText: '>> ', prefixStyle: const TextStyle(color: cG, fontFamily: 'monospace'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: cG.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: cG.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: const BorderSide(color: cG, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      )),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _analyze,
        child: AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [cG.withOpacity(0.08), cG.withOpacity(0.15)]),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: cG.withOpacity(0.6)),
            boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 12)],
          ),
          child: Text('SCAN', style: TextStyle(color: cG, fontSize: 11,
            fontWeight: FontWeight.bold, letterSpacing: 2,
            shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 8)])),
        )),
      ),
    ]),
  );

  Widget _tabBar() => Container(
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.9),
      border: Border(bottom: BorderSide(color: cBr)),
    ),
    child: Row(children: [
      _tabBtn('📊 INFO', 0),
      _tabBtn('💬 CHAT', 1),
      _tabBtn('📡 RED', 2),
    ]),
  );

  Widget _tabBtn(String label, int idx) => Expanded(child: GestureDetector(
    onTap: () => setState(() => _tab = idx),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: _tab == idx ? cG.withOpacity(0.07) : Colors.transparent,
        border: Border(bottom: BorderSide(color: _tab == idx ? cG : Colors.transparent, width: 2))),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1,
          color: _tab == idx ? cG : cDg, fontFamily: 'monospace',
          shadows: _tab == idx ? [const Shadow(color: cG, blurRadius: 8)] : null)),
    ),
  ));

  Widget _loadingView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cG.withOpacity(_glow.value), width: 2),
        boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 20)],
      ),
      child: const Center(child: CircularProgressIndicator(color: cG, strokeWidth: 2)),
    )),
    const SizedBox(height: 20),
    Text('ANALIZANDO SERVIDOR...', style: TextStyle(fontSize: 12, color: cG,
      fontFamily: 'monospace', letterSpacing: 3,
      shadows: [const Shadow(color: cG, blurRadius: 8)])),
    const SizedBox(height: 8),
    Text('Recopilando información...', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
  ]));

  Widget _emptyView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    AnimatedBuilder(animation: _pulse, builder: (_, __) => Text('[ JSUS ANALYZER ]',
      style: TextStyle(fontSize: 16, color: cG.withOpacity(_pulse.value * 0.7),
        fontFamily: 'monospace', letterSpacing: 3,
        shadows: [Shadow(color: cG.withOpacity(_pulse.value * 0.4), blurRadius: 20)]))),
    const SizedBox(height: 16),
    _infoLine('Ingresa un servidor IPTV para analizar'),
    _infoLine('Detecta panel, ubicación, subdominios'),
    _infoLine('Evalúa dificultad y recomienda proxies'),
    _infoLine('Chat inteligente sobre el servidor'),
    const SizedBox(height: 20),
    Text('Ej: http://starlatino.tv:8880',
      style: TextStyle(fontSize: 10, color: cDg.withOpacity(0.6), fontFamily: 'monospace')),
  ]));

  Widget _infoLine(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('→ ', style: const TextStyle(color: cG, fontFamily: 'monospace')),
      Text(t, style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')),
    ]),
  );

  Widget _tabContent() {
    switch (_tab) {
      case 0: return _infoTab();
      case 1: return _chatTab();
      case 2: return _networkTab();
      default: return _infoTab();
    }
  }

  // ═══ INFO TAB ═══
  Widget _infoTab() {
    final info = _info!;
    return ListView(padding: const EdgeInsets.all(10), children: [
      // Status card
      _card(accent: info.isActive ? cG : cRe, child: Column(children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: info.isActive ? cG : cRe,
            boxShadow: [BoxShadow(color: info.isActive ? cG : cRe, blurRadius: 8)])),
          const SizedBox(width: 8),
          Text(info.isActive ? 'SERVIDOR ACTIVO' : 'SERVIDOR INACTIVO',
            style: TextStyle(fontSize: 13, color: info.isActive ? cG : cRe,
              fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2,
              shadows: [Shadow(color: info.isActive ? cG : cRe, blurRadius: 8)])),
          const Spacer(),
          if (info.ping > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cCy.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: cCy.withOpacity(0.3))),
            child: Text('${info.ping}ms', style: const TextStyle(fontSize: 10, color: cCy,
              fontFamily: 'monospace', fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 10),
        _row('HOST', info.host, cCy),
        if (info.ip.isNotEmpty) _row('IP', info.ip, cCy),
        _row('PANEL', info.panelType, cMg),
        if (info.timezone.isNotEmpty) _row('TIMEZONE', info.timezone, cDg),
      ])),
      // Location card
      _card(accent: cYe, child: Column(children: [
        _cardTitle('📍 UBICACIÓN'),
        _row('PAÍS', info.country.isNotEmpty ? info.country : 'Desconocido', cYe),
        _row('CIUDAD', info.city.isNotEmpty ? info.city : 'Desconocido', cYe),
        _row('ISP', info.isp.isNotEmpty ? info.isp : 'Desconocido', cDg),
        _row('ORG', info.org.isNotEmpty ? info.org : 'Desconocido', cDg),
        const SizedBox(height: 6),
        Row(children: [
          _badge(info.isHosting ? '⚠ DATACENTER' : '✓ NO DATACENTER', info.isHosting ? cOr : cG),
          const SizedBox(width: 6),
          _badge(info.isProxy ? '⚠ PROXY/VPN' : '✓ IP DIRECTA', info.isProxy ? cOr : cG),
        ]),
      ])),
      // Difficulty card
      _card(accent: _diffColor(info.difficulty), child: Column(children: [
        _cardTitle('🛡 DIFICULTAD DE ESCANEO'),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedBuilder(animation: _glow, builder: (_, __) => Text(
            info.difficulty,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
              color: _diffColor(info.difficulty), fontFamily: 'monospace', letterSpacing: 2,
              shadows: [Shadow(color: _diffColor(info.difficulty).withOpacity(_glow.value), blurRadius: 15)]))),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: cBr)),
          child: Row(children: [
            const Text('💡 ', style: TextStyle(fontSize: 12)),
            Expanded(child: Text(info.proxyRecommendation,
              style: const TextStyle(fontSize: 10, color: cCy, fontFamily: 'monospace'))),
          ]),
        ),
      ])),
    ]);
  }

  // ═══ CHAT TAB ═══
  Widget _chatTab() => Column(children: [
    Expanded(child: _chatMessages.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('💬', style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text('Pregúntame sobre el servidor', style: TextStyle(fontSize: 11, color: cDg, fontFamily: 'monospace')),
          const SizedBox(height: 16),
          _quickBtn('¿Qué tan difícil es escanearlo?'),
          _quickBtn('¿Qué proxies recomiendas?'),
          _quickBtn('¿Tiene servidores paralelos?'),
          _quickBtn('¿Cuántos bots usar?'),
          _quickBtn('¿Dónde está ubicado?'),
        ]))
      : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _chatMessages.length + (_chatLoading ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == _chatMessages.length) return _typingIndicator();
            final m = _chatMessages[i];
            return _chatBubble(m['text']!, m['role'] == 'user');
          })),
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.95),
        border: Border(top: BorderSide(color: cBr)),
      ),
      child: Row(children: [
        Expanded(child: TextField(
          controller: _chatCtrl,
          style: const TextStyle(color: cG, fontSize: 12, fontFamily: 'monospace'),
          onSubmitted: _sendChat,
          decoration: InputDecoration(
            hintText: 'Pregunta sobre el servidor...',
            hintStyle: TextStyle(color: cDg.withOpacity(0.5), fontSize: 11),
            filled: true, fillColor: Colors.black54,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: cG.withOpacity(0.3))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: cG.withOpacity(0.3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: const BorderSide(color: cG)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _sendChat(_chatCtrl.text),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: cG.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: cG.withOpacity(0.5))),
            child: const Text('▶', style: TextStyle(color: cG, fontSize: 14)),
          ),
        ),
      ]),
    ),
  ]);

  Widget _quickBtn(String text) => GestureDetector(
    onTap: () => _sendChat(text),
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cG.withOpacity(0.06),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: cG.withOpacity(0.25))),
      child: Text(text, style: const TextStyle(fontSize: 10, color: cG, fontFamily: 'monospace')),
    ),
  );

  Widget _chatBubble(String text, bool isUser) => Container(
    margin: EdgeInsets.only(bottom: 8, left: isUser ? 40 : 0, right: isUser ? 0 : 40),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: isUser ? cG.withOpacity(0.08) : cBg2.withOpacity(0.9),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: isUser ? cG.withOpacity(0.3) : cBr),
    ),
    child: Text(text, style: TextStyle(
      fontSize: 11, color: isUser ? cG : cCy, fontFamily: 'monospace', height: 1.5)),
  );

  Widget _typingIndicator() => Container(
    margin: const EdgeInsets.only(bottom: 8, right: 40),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.9),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: cBr)),
    child: AnimatedBuilder(animation: _pulse, builder: (_, __) =>
      Text('Analizando...', style: TextStyle(fontSize: 11, color: cDg.withOpacity(_pulse.value),
        fontFamily: 'monospace'))),
  );

  // ═══ NETWORK TAB ═══
  Widget _networkTab() {
    final info = _info!;
    return ListView(padding: const EdgeInsets.all(10), children: [
      _card(accent: cCy, child: Column(children: [
        _cardTitle('📡 SUBDOMINIOS ENCONTRADOS'),
        if (info.subdomains.isEmpty)
          Padding(padding: const EdgeInsets.all(8),
            child: Text('No se encontraron subdominios públicos',
              style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')))
        else
          ...info.subdomains.map((s) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: cCy.withOpacity(0.05),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: cCy.withOpacity(0.2))),
            child: Row(children: [
              const Text('├ ', style: TextStyle(color: cCy, fontFamily: 'monospace')),
              Expanded(child: Text(s, style: const TextStyle(fontSize: 10, color: cCy, fontFamily: 'monospace'))),
              GestureDetector(
                onTap: () { Clipboard.setData(ClipboardData(text: s)); _toast('Copiado'); },
                child: const Text('[CPY]', style: TextStyle(color: cDg, fontSize: 9, fontFamily: 'monospace'))),
            ]),
          )),
      ])),
      _card(accent: cMg, child: Column(children: [
        _cardTitle('🌐 IPs RELACIONADAS'),
        if (info.relatedIPs.isEmpty)
          Padding(padding: const EdgeInsets.all(8),
            child: Text('No se encontraron IPs relacionadas',
              style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')))
        else
          ...info.relatedIPs.map((ip) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: cMg.withOpacity(0.05),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: cMg.withOpacity(0.2))),
            child: Row(children: [
              const Text('├ ', style: TextStyle(color: cMg, fontFamily: 'monospace')),
              Expanded(child: Text(ip, style: const TextStyle(fontSize: 10, color: cMg, fontFamily: 'monospace'))),
              GestureDetector(
                onTap: () { Clipboard.setData(ClipboardData(text: ip)); _toast('Copiado'); },
                child: const Text('[CPY]', style: TextStyle(color: cDg, fontSize: 9, fontFamily: 'monospace'))),
            ]),
          )),
      ])),
      _card(accent: cYe, child: Column(children: [
        _cardTitle('⚡ RESUMEN DE ESCANEO'),
        _row('SERVIDOR', info.host, cCy),
        _row('IP', info.ip.isNotEmpty ? info.ip : 'No resuelta', cCy),
        _row('PAÍS', info.country.isNotEmpty ? info.country : 'Desconocido', cYe),
        _row('PING', info.ping > 0 ? '${info.ping}ms' : 'No medido', cYe),
        _row('DIFICULTAD', info.difficulty, _diffColor(info.difficulty)),
        _row('PROXIES', info.proxyRecommendation.split('—').first.trim(), cG),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            final txt = '''SERVIDOR: ${info.host}
IP: ${info.ip}
PAÍS: ${info.country} - ${info.city}
ISP: ${info.isp}
PANEL: ${info.panelType}
PING: ${info.ping}ms
DIFICULTAD: ${info.difficulty}
PROXIES: ${info.proxyRecommendation}
SUBDOMINIOS: ${info.subdomains.join(', ')}''';
            Clipboard.setData(ClipboardData(text: txt));
            _toast('Reporte copiado');
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: cG.withOpacity(0.07),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: cG.withOpacity(0.4))),
            child: const Text('📋 COPIAR REPORTE COMPLETO', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: cG, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 2))),
        ),
      ])),
    ]);
  }

  Color _diffColor(String d) {
    switch (d) {
      case 'FÁCIL': return cG;
      case 'MEDIO': return cYe;
      case 'DIFÍCIL': return cOr;
      case 'MUY DIFÍCIL': return cRe;
      default: return cDg;
    }
  }

  Widget _card({Color accent = cBr, required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.88),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: cBr),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10)],
    ),
    child: Stack(children: [
      Positioned(left: -14, top: -12, bottom: -12, child: Container(width: 3,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [accent, accent.withOpacity(0.1)])))),
      child,
    ]),
  );

  Widget _cardTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Container(width: 2, height: 12, color: cG, margin: const EdgeInsets.only(right: 8)),
      Text(t, style: const TextStyle(fontSize: 11, color: cDg, letterSpacing: 2,
        fontWeight: FontWeight.bold, fontFamily: 'monospace',
        shadows: [Shadow(color: cG, blurRadius: 4)])),
    ]));

  Widget _row(String k, String v, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$k: ', style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.8), fontFamily: 'monospace')),
      Expanded(child: Text(v, style: TextStyle(fontSize: 10, color: c, fontFamily: 'monospace',
        shadows: [Shadow(color: c.withOpacity(0.4), blurRadius: 4)]),
        overflow: TextOverflow.ellipsis)),
    ]));

  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(2),
      border: Border.all(color: c.withOpacity(0.3))),
    child: Text(t, style: TextStyle(fontSize: 9, color: c, fontFamily: 'monospace', fontWeight: FontWeight.bold)));

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
