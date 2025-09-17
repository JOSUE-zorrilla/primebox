// recolectar_recoleccion_page.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'recolectados_centros_page.dart';

// Importa las variables globales definidas en login_page.dart
import 'login_page.dart' show globalNombre, globalUserId, globalIdCiudad;

class PaqueteLocal {
  final String idGuiaPB;
  final String idGuiaProveedor;
  final String tnReference;
  final int fechaSolicitudMs;

  PaqueteLocal({
    required this.idGuiaPB,
    required this.idGuiaProveedor,
    required this.tnReference,
    required this.fechaSolicitudMs,
  });

  Map<String, dynamic> toJson() => {
        'idGuiaPB': idGuiaPB,
        'idGuiaProveedor': idGuiaProveedor,
        'tnReference': tnReference,
        'fechaSolicitudMs': fechaSolicitudMs,
      };

  factory PaqueteLocal.fromMap(Map data) => PaqueteLocal(
        idGuiaPB: (data['idGuiaPB'] ?? data['IdGuiaPB'] ?? '').toString(),
        idGuiaProveedor:
            (data['idGuiaProveedor'] ?? data['IdGuiaProveedor'] ?? '')
                .toString(),
        tnReference:
            (data['tnReference'] ?? data['tn_reference'] ?? '').toString(),
        fechaSolicitudMs: int.tryParse(
              (data['FechaSolicitud'] ?? data['fechaSolicitudMs'] ?? '0')
                  .toString(),
            ) ??
            0,
      );
}

class RecolectarRecoleccionPage extends StatefulWidget {
  final String idTienda;
  final String nombreCentro;
  final String direccionCentro;
  final String iconUrl;

  /// Timestamp en milisegundos que viene de la pantalla anterior (Embarque)
  final int embarqueMs;

  const RecolectarRecoleccionPage({
    super.key,
    required this.idTienda,
    required this.nombreCentro,
    required this.direccionCentro,
    required this.iconUrl,
    required this.embarqueMs,
  });

  @override
  State<RecolectarRecoleccionPage> createState() =>
      _RecolectarRecoleccionPageState();
}

class _RecolectarRecoleccionPageState extends State<RecolectarRecoleccionPage> {
  // ===== Estados de datos y UI =====
  bool _loadingData = true;

  // Índice de guías válidas para este centro
  final Map<String, PaqueteLocal> _indexPorCodigo = {}; // código normalizado → paquete
  List<PaqueteLocal> _seleccionados = [];

  final TextEditingController _buscarCtrl = TextEditingController();

  // ====== Scanner embebido ======
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;
  bool _permissionGranted = false;
  final Set<String> _codesProcesados = {}; // evita duplicados por “rebote”

  // ====== Ubicación precargada ======
  bool _locLoading = true;
  String? _locError;
  double? _lat;
  double? _lng;

  // ====== Firma en tiempo real ======
  StreamSubscription<DatabaseEvent>? _firmaSub;
  bool _firmadoEnviado = false;

  static const String _urlWebhook =
      'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_1Cw2TxVBj45xu2nA1EdBgq';

  @override
  void initState() {
    super.initState();
    _syncFirebaseToLocal();
    _checkCameraPermission(); // permiso de cámara para QR
    _initLocation(); // obtener lat/lng al cargar la pantalla
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    _qrController?.dispose();
    _firmaSub?.cancel();
    super.dispose();
  }

  // Hot reload: pausar/reanudar cámara
  @override
  void reassemble() {
    super.reassemble();
    _qrController?.pauseCamera();
    _qrController?.resumeCamera();
  }

  String get _prefsKey => 'pb_guias_${widget.idTienda}';

  String _norm(String s) =>
      s.trim().toUpperCase().replaceAll(' ', '').replaceAll('#', '');

  // ====== Permisos ======
  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
    }
  }

  // ====== Cargar lista de paquetes de Firebase a local ======
  Future<void> _syncFirebaseToLocal() async {
    setState(() => _loadingData = true);

    final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/idGuiasSolicitadas/${widget.idTienda}/PaquetesSolicitados');

    try {
      final snap = await ref.get();
      final List<PaqueteLocal> lista = [];

      if (snap.value is Map) {
        final map = snap.value as Map;
        for (final entry in map.entries) {
          final val = entry.value;
          if (val is Map) {
            final pk = PaqueteLocal.fromMap(val);
            if (pk.idGuiaPB.isNotEmpty ||
                pk.idGuiaProveedor.isNotEmpty ||
                pk.tnReference.isNotEmpty) {
              lista.add(pk);
            }
          }
        }
      } else if (snap.value is List) {
        for (final v in (snap.value as List)) {
          if (v is Map) {
            final pk = PaqueteLocal.fromMap(v);
            if (pk.idGuiaPB.isNotEmpty ||
                pk.idGuiaProveedor.isNotEmpty ||
                pk.tnReference.isNotEmpty) {
              lista.add(pk);
            }
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(lista.map((e) => e.toJson()).toList()));
      await prefs.setInt('${_prefsKey}_lastSync',
          DateTime.now().millisecondsSinceEpoch);

      _indexPorCodigo.clear();
      for (final p in lista) {
        if (p.idGuiaPB.isNotEmpty) _indexPorCodigo[_norm(p.idGuiaPB)] = p;
        if (p.idGuiaProveedor.isNotEmpty) {
          _indexPorCodigo[_norm(p.idGuiaProveedor)] = p;
        }
        if (p.tnReference.isNotEmpty) {
          _indexPorCodigo[_norm(p.tnReference)] = p;
        }
      }
    } catch (_) {
      // Si falla red, intenta cargar de local
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final m in decoded) {
            final p = PaqueteLocal.fromMap(m as Map);
            if (p.idGuiaPB.isNotEmpty) _indexPorCodigo[_norm(p.idGuiaPB)] = p;
            if (p.idGuiaProveedor.isNotEmpty) {
              _indexPorCodigo[_norm(p.idGuiaProveedor)] = p;
            }
            if (p.tnReference.isNotEmpty) {
              _indexPorCodigo[_norm(p.tnReference)] = p;
            }
          }
        }
      }
    }

    if (mounted) setState(() => _loadingData = false);
  }

  // ====== Ubicación al cargar ======
  Future<void> _initLocation() async {
    setState(() {
      _locLoading = true;
      _locError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locError = 'Servicio de ubicación desactivado.';
          _locLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locError = 'Permiso de ubicación denegado.';
            _locLoading = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locError =
              'Permiso de ubicación denegado permanentemente. Habilita desde Ajustes.';
          _locLoading = false;
        });
        return;
      }

      // Intento principal con timeout
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );
      } on TimeoutException {
        // Fallback a última conocida
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) {
          setState(() {
            _locError =
                'No fue posible obtener la ubicación. Intenta actualizar.';
            _locLoading = false;
          });
          return;
        }
        pos = last;
      }

      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locLoading = false;
        _locError = null;
      });
    } catch (e) {
      setState(() {
        _locError = e.toString();
        _locLoading = false;
      });
    }
  }

  // ====== Helpers de fecha requeridos ======
  String _two(int n) => n.toString().padLeft(2, '0');

  /// Convierte un timestamp en milisegundos a "YYYY-MM-DD"
  String _fmtYYYYMMDD(int ms, {bool useUtc = false}) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: useUtc);
    final y = dt.year.toString();
    final m = _two(dt.month);
    final d = _two(dt.day);
    return '$y-$m-$d';
  }

  /// Convierte un timestamp en milisegundos a "YYYY-MM-DD HH:MM:SS"
  String _fmtYYYYMMDDHHMMSS(int ms, {bool useUtc = false}) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: useUtc);
    final base = _fmtYYYYMMDD(ms, useUtc: useUtc);
    final hh = _two(dt.hour);
    final mm = _two(dt.minute);
    final ss = _two(dt.second);
    return '$base $hh:$mm:$ss';
  }

  // ====== Manejo de códigos ======
  void _handleAddCode(String rawCode) {
    final code = _norm(rawCode);
    if (code.isEmpty) return;

    if (_codesProcesados.contains(code)) return; // evita rebote
    _codesProcesados.add(code);

    final p = _indexPorCodigo[code];
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Este paquete no está asignado a este centro de recolección.'),
        ),
      );
      return;
    }

    final yaExiste = _seleccionados.any((e) => e.idGuiaPB == p.idGuiaPB);
    if (yaExiste) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este paquete ya fue añadido.')),
      );
      return;
    }

    setState(() {
      _seleccionados = [..._seleccionados, p];
    });
  }

  void _agregarPorInput() {
    final txt = _buscarCtrl.text;
    if (txt.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un código en el buscador.')),
      );
      return;
    }
    _handleAddCode(txt);
    _buscarCtrl.clear();
  }

  void _eliminarDeLista(PaqueteLocal p) {
    setState(() {
      _seleccionados.removeWhere((e) => e.idGuiaPB == p.idGuiaPB);
    });
  }

  // ====== Construcción y envío al Webhook ======
  Future<void> _postWebhook({String? urlFirma}) async {
    if (_seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes escanear al menos 1 paquete.')),
      );
      return;
    }
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ubicación no disponible. Actualiza el GPS.')),
      );
      return;
    }

    try {
      final fechaMs = DateTime.now().millisecondsSinceEpoch;
      final yyyyMMdd = _fmtYYYYMMDD(fechaMs);
      final yyyyMMddHHmmss = _fmtYYYYMMDDHHMMSS(fechaMs);

      final Map<String, dynamic> dataRecolectados = {};
      for (final p in _seleccionados) {
        final key = (p.idGuiaPB.isNotEmpty
                ? p.idGuiaPB
                : (p.tnReference.isNotEmpty ? p.tnReference : p.idGuiaProveedor))
            .toString();
        dataRecolectados[key] = {
          'idGuia': p.idGuiaPB,
          'idGuiaProveedor': p.idGuiaProveedor,
          'tnReference': p.tnReference,
        };
      }

      final payload = {
        'FechaTimestamp': fechaMs,
        'YYYYMMDD': yyyyMMdd,
        'YYYYMMDDHHMMSS': yyyyMMddHHmmss,
        'Latitude': _lat,
        'Longitude': _lng,
        'NombreCentro': widget.nombreCentro,
        'dataRecolectados': dataRecolectados,
        'idCentroRecoleccion': widget.idTienda,
        'NombreDriver': globalNombre ?? '',
        'idDriver': globalUserId ?? '',
        'idCiudad': globalIdCiudad ?? '',
        'Embarque': widget.embarqueMs,
        if (urlFirma != null && urlFirma.trim().isNotEmpty)
          'UrlFirma': urlFirma.trim(),
      };

      final resp = await http.post(
        Uri.parse(_urlWebhook),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Información enviada')),
        );

        setState(() {
          _seleccionados = [];
          _codesProcesados.clear();
        });

        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const RecolectadosCentrosPage(),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al enviar (${resp.statusCode}). ${resp.body.isNotEmpty ? resp.body : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  // ====== FINALIZAR (manual) ======
  Future<void> _finalizarRecoleccion() async {
    if (_seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes escanear al menos 1 paquete.')),
      );
      return;
    }
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Ubicación aún no disponible. Pulsa el botón de actualizar GPS.'),
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Recolección'),
        content: Text(
            '¿Deseas confirmar la recolección de ${_seleccionados.length} paquete(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await _postWebhook();
  }

  // ====== Listener de firma y Bottom Sheet con WebView ======
  Future<void> _abrirCerrarConFirma() async {
    final hoyYYYYMMDD = _fmtYYYYMMDD(DateTime.now().millisecondsSinceEpoch);

    // Ruta RTDB a escuchar:
    final firmaRef = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/FirmasProveedor/$hoyYYYYMMDD/Embarque/${widget.embarqueMs}',
    );

    // Reset y escucha
    _firmaSub?.cancel();
    _firmadoEnviado = false;
    _firmaSub = firmaRef.onValue.listen((event) async {
      final val = event.snapshot.value;
      String? urlFirma;

      if (val is Map) {
        final m = Map<String, dynamic>.from(val as Map);
        final dynamic candidate = m['Url'] ?? m['url'] ?? m['URL'];
        if (candidate != null) urlFirma = candidate.toString();
      } else if (val is String) {
        // por si el nodo es directamente la URL
        urlFirma = val;
      }

      if (urlFirma != null &&
          urlFirma.trim().isNotEmpty &&
          !_firmadoEnviado) {
        _firmadoEnviado = true;

        // cerrar el sheet si está abierto
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // cierra el bottom sheet
        }

        // Enviar al webhook con UrlFirma
        await _postWebhook(urlFirma: urlFirma);
      }
    });

    // Abrir el WebView en un bottom sheet
    final urlWeb =
        'https://primebox.mx/dashboard/app/Views/view_firma_embarque?idEmbarque=${widget.embarqueMs}&idFecha=$hoyYYYYMMDD';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,        // para permitir dibujar en el canvas de firma
      isDismissible: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final ctrl = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(Uri.parse(urlWeb));
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.95,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Cerrar con firma',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: WebViewWidget(controller: ctrl)),
              ],
            ),
          ),
        );
      },
    );

    // Al cerrar el sheet, cancelar la suscripción
    _firmaSub?.cancel();
    _firmaSub = null;
  }

  // ======== UI ========
  @override
  Widget build(BuildContext context) {
    if (_loadingData) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.icecream_outlined, size: 64),
                SizedBox(height: 16),
                Text(
                  'Obteniendo paquetes solicitados\na recolección...',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      );
    }

    const headerColor = Color(0xFF1955CC);
    final count = _seleccionados.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            // ===== Encabezado con QR embebido =====
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              decoration: const BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 40,
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Material(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () => Navigator.pop(context),
                              borderRadius: BorderRadius.circular(10),
                              child: const SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(Icons.arrow_back_ios_new_rounded,
                                    size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        const Align(
                          alignment: Alignment.center,
                          child: Text(
                            'Recolección de paquetes',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ====== Escáner embebido ======
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: _permissionGranted
                          ? QRView(
                              key: _qrKey,
                              onQRViewCreated: _onQRViewCreated,
                              overlay: QrScannerOverlayShape(
                                borderColor: Colors.white,
                                borderRadius: 8,
                                borderLength: 20,
                                borderWidth: 6,
                                cutOutHeight: 140,
                                cutOutWidth: 280,
                              ),
                            )
                          : _buildPermissionPlaceholder(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Dirección del centro
                  Text(
                    widget.nombreCentro,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.direccionCentro,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // ====== GPS mostrado como texto (precargado) ======
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location_outlined,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locLoading
                                ? 'GPS: obteniendo...'
                                : (_lat != null && _lng != null)
                                    ? 'GPS: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}'
                                    : 'GPS: ${_locError ?? 'no disponible'}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Actualizar GPS',
                          onPressed: _initLocation,
                          icon: const Icon(Icons.refresh,
                              color: Colors.white70, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Buscador + botón 3 puntos (agrega por texto)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buscarCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _agregarPorInput(),
                          decoration: InputDecoration(
                            hintText: 'Buscar o escanear',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: _agregarPorInput,
                          borderRadius: BorderRadius.circular(10),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(Icons.more_horiz, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ===== Lista de seleccionados =====
            Expanded(
              child: _seleccionados.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'Escanea o busca un código para añadirlo a la lista.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                      itemCount: _seleccionados.length,
                      itemBuilder: (_, i) {
                        final p = _seleccionados[i];
                        final titulo = p.idGuiaPB.isNotEmpty
                            ? p.idGuiaPB
                            : (p.idGuiaProveedor.isNotEmpty
                                ? p.idGuiaProveedor
                                : p.tnReference);
                        return Card(
                          elevation: 1.5,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFEFF3FF),
                              child: Icon(Icons.inventory_2_outlined,
                                  color: Color(0xFF1955CC)),
                            ),
                            title: Text('Orden\n#$titulo',
                                style: const TextStyle(height: 1.2)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _eliminarDeLista(p),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // ===== Botones inferiores =====
      bottomSheet: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          color: const Color(0xFFF2F3F7),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _abrirCerrarConFirma,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF2B59F2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cerrar con firma',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2B59F2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _seleccionados.isEmpty ? null : _finalizarRecoleccion,
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: _seleccionados.isEmpty
                        ? Colors.black26
                        : const Color(0xFF2B59F2),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Finalizar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====== helpers UI ======
  Widget _buildPermissionPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_camera_front, color: Colors.white70, size: 40),
            const SizedBox(height: 8),
            const Text(
              'Se requiere permiso de cámara',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _checkCameraPermission,
              child: const Text('Conceder permiso'),
            ),
          ],
        ),
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrController = controller;
    _qrController!.scannedDataStream.listen((scanData) async {
      final raw = scanData.code ?? '';
      if (raw.isEmpty) return;
      _handleAddCode(raw);
    });
  }
}
