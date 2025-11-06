import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';

// Globals
import 'login_page.dart' show globalNombre, globalUserId, globalIdCiudad;

// NUEVO: página de la lista de fila virtual
import 'fila_virtual_lista_page.dart';

class RecogerAlmacenScanPage extends StatefulWidget {
  final String idAlmacen;        // IMPORTANTE: aquí se espera el KEY del nodo de AlmacenPicker
  final String nombreAlmacen;
  final String direccionAlmacen;
  final String idFirma;          // viene de la pantalla anterior

  const RecogerAlmacenScanPage({
    super.key,
    required this.idAlmacen,
    required this.nombreAlmacen,
    required this.direccionAlmacen,
    required this.idFirma,
  });

  @override
  State<RecogerAlmacenScanPage> createState() => _RecogerAlmacenScanPageState();
}

class _RecogerAlmacenScanPageState extends State<RecogerAlmacenScanPage> {
  // Escáner
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR_ALMACEN');
  QRViewController? _qrController;
  bool _permissionGranted = false;
  final Set<String> _codesProcesados = {};

  // Lista de códigos aceptados (existentes en Firebase)
  final List<String> _seleccionados = [];

  // Buscador manual
  final TextEditingController _buscarCtrl = TextEditingController();

  // Firma realtime
  StreamSubscription<DatabaseEvent>? _firmaSub;
  bool _enviando = false;

  // NUEVO: bandera de proceso de fila virtual
  bool _procesandoFilaVirtual = false;

  static const String _webhookUrl =
      'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_eRV73rsuWkKSAGvQxyMJ75';

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  @override
  void dispose() {
    _qrController?.dispose();
    _buscarCtrl.dispose();
    _firmaSub?.cancel();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _qrController?.pauseCamera();
    _qrController?.resumeCamera();
  }

  // ====== permisos cámara ======
  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
    }
  }

  String _norm(String s) =>
      s.trim().toUpperCase().replaceAll(' ', '').replaceAll('#', '');

  // ====== verificación en Firebase ======
  Future<void> _tryAddFromFirebase(String rawCode) async {
    final code = _norm(rawCode);
    if (code.isEmpty) return;

    // Si ya se procesó antes, no vuelvas a consultar Firebase, pero
    // si ya está en la lista, súbelo al tope.
    if (_codesProcesados.contains(code)) {
      if (_seleccionados.contains(code)) {
        setState(() {
          _seleccionados.remove(code);
          _seleccionados.insert(0, code); // mover al tope
        });
      } else {
        // Ya fue procesado pero no está en la lista (p.ej. se eliminó)
        // Permitimos re-insertarlo al tope sin volver a consultar.
        setState(() => _seleccionados.insert(0, code));
      }
      return;
    }

    // Marcar como procesado para evitar consultas concurrentes repetidas
    _codesProcesados.add(code);

    try {
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Almacen/${widget.idAlmacen}/Paquetes/$code',
      );
      final snap = await ref.get();

      if (snap.exists) {
        if (_seleccionados.contains(code)) {
          // Ya estaba: lo llevamos al tope
          setState(() {
            _seleccionados.remove(code);
            _seleccionados.insert(0, code);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Este paquete ya estaba en la lista. Se movió arriba.')),
          );
        } else {
          // Nuevo: insertar al inicio
          setState(() => _seleccionados.insert(0, code));
        }
      } else {
        // <<<<< CAMBIO: SnackBar con duración máxima de 2 segundos >>>>>
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('El código no pertenece a este almacén.'),
            duration: const Duration(seconds: 2),
          ),
        );
        // Si no existe en Firebase, desmarcamos para permitir intentarlo nuevamente si fue un error de lectura
        _codesProcesados.remove(code);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al validar: $e')),
      );
      _codesProcesados.remove(code);
    }
  }

  void _agregarPorInput() {
    final txt = _buscarCtrl.text;
    if (txt.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un código en el buscador.')),
      );
      return;
    }
    _tryAddFromFirebase(txt);
    _buscarCtrl.clear();
  }

  void _eliminar(String code) {
    setState(() {
      _seleccionados.remove(code);
      // Permitir volver a añadirlo si se elimina
      _codesProcesados.remove(code);
    });
  }

  // ====== formatos de fecha ======
  String _two(int n) => n.toString().padLeft(2, '0');

  String _fmtYYYYMMDD(DateTime dt) {
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
  }

  String _fmtYYYYMMDDHHMMSS(DateTime dt) {
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  // ====== util: parseo robusto a double ======
  double? _toDoubleLoose(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  // ====== construir payload y enviar webhook ======
  Future<void> _enviarWebhook({String? urlFirma}) async {
    if (_seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes escanear al menos 1 paquete.')),
      );
      return;
    }
    if (_enviando) return;

    setState(() => _enviando = true);

    try {
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;
      final ymd = _fmtYYYYMMDD(now);
      final ymdhms = _fmtYYYYMMDDHHMMSS(now);

      final Map<String, dynamic> data = {};
      for (final code in _seleccionados) {
        data[code] = {'idPaquetePB': code};
      }

      final payload = {
        'NombreUsuario': (globalNombre ?? '').toString(),
        'Timestamp': ts,
        'YYYYMMDD': ymd,
        'YYYYMMDDHHMMSS': ymdhms, // según tu requerimiento exacto
        'idAlmacen': widget.idAlmacen,
        'idCiudad': (globalIdCiudad ?? '').toString(),
        'idUsuario': (globalUserId ?? '').toString(),
        'data': data,
        if (urlFirma != null && urlFirma.trim().isNotEmpty) 'UrlFirma': urlFirma,
      };

      final resp = await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Información enviada.')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar (${resp.statusCode}). ${resp.body}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // ====== Finalizar ======
  Future<void> _onFinalizar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Desea finalizar la recolección de los paquetes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
        ],
      ),
    );
    if (ok == true) {
      await _enviarWebhook();
    }
  }

  // ====== Con Firma (BottomSheet + WebView + escucha RTDB) ======
  Future<void> _onConFirma() async {
    final idFirma = (widget.idFirma).trim();
    if (idFirma.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay idFirma configurado para este almacén.')),
      );
      return;
    }

    final hoy = _fmtYYYYMMDD(DateTime.now());
    final firmaPath =
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/FirmasDriversAlmacen/$hoy/Firmas/$idFirma';

    // Suscripción antes de abrir el sheet
    _firmaSub?.cancel();
    _firmaSub = FirebaseDatabase.instance.ref(firmaPath).onValue.listen(
      (event) async {
        String? urlFirma;
        final val = event.snapshot.value;

        if (val is Map) {
          final m = Map<String, dynamic>.from(val as Map);
          final dynamic candidate = m['UrlFirma'] ?? m['urlFirma'] ?? m['url'];
          if (candidate != null) urlFirma = candidate.toString();
        } else if (val is String) {
          urlFirma = val;
        }

        if (urlFirma != null && urlFirma!.trim().isNotEmpty) {
          // Cerrar el sheet si está abierto
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          _firmaSub?.cancel();
          _firmaSub = null;

          // Enviar con UrlFirma
          await _enviarWebhook(urlFirma: urlFirma);
        }
      },
      onError: (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error escuchando firma: $e')),
        );
      },
    );

    final urlWeb =
        'https://primebox.mx/dashboard/app/Views/view_firma_driver?id=$idFirma&Fecha=$hoy';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
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
                          'Firma Digital',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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

    // Al cerrar manualmente el sheet
    _firmaSub?.cancel();
    _firmaSub = null;
  }

  // ====== NUEVO: Fila Virtual ======

  Future<void> _onFilaVirtual() async {
    if (_procesandoFilaVirtual) return;
    setState(() => _procesandoFilaVirtual = true);

    try {
      final userId = (globalUserId ?? '').toString().trim();
      final nombre = (globalNombre ?? '').toString().trim();

      if (userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró el id del usuario (idDriver).')),
        );
        return;
      }

      final basePath =
          'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/FilaVirtualAlmacen/${widget.idAlmacen}/FilaVirtual';
      final miNodoRef = FirebaseDatabase.instance.ref('$basePath/$userId');

      // 1) ¿Ya existe?
      final miNodoSnap = await miNodoRef.get();
      if (miNodoSnap.exists) {
        // Ya está en fila -> pasar a la lista
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FilaVirtualListaPage(idAlmacen: widget.idAlmacen, nombreAlmacen: widget.nombreAlmacen),
          ),
        );
        return;
      }

      // 2) Preguntar si desea unirse
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unirse a la fila virtual'),
          content: const Text(
            'Esta opción te agregará a la fila virtual del almacén para ser llamado y recibir tu ruta. '
            'Para poder unirte tienes que estar a 50 metros del almacén; de lo contrario no podrás unirte.\n\n'
            '¿Deseas unirte ahora?'
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, unirme')),
          ],
        ),
      );

      if (ok != true) return;

      // 3) Verificar permisos y obtener ubicación actual
      final canLocate = await _ensureLocationPermission();
      if (!canLocate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se otorgó permiso de ubicación.')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // ====== LECTURA POR KEY DEL NODO EN AlmacenPicker ======
      final ubicRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/AlmacenPicker/${widget.idAlmacen}',
      );
      final ubicSnap = await ubicRef.get();

      double? almacLat;
      double? almacLng;

      if (ubicSnap.exists) {
        // Usa child() para evitar problemas de casteo a Map<String, dynamic>
        almacLat = _toDoubleLoose(ubicSnap.child('Latitude').value)
                ?? _toDoubleLoose(ubicSnap.child('latitude').value)
                ?? _toDoubleLoose(ubicSnap.child('Lat').value)
                ?? _toDoubleLoose(ubicSnap.child('lat').value);

        almacLng = _toDoubleLoose(ubicSnap.child('Longitude').value)
                ?? _toDoubleLoose(ubicSnap.child('longitude').value)
                ?? _toDoubleLoose(ubicSnap.child('Lng').value)
                ?? _toDoubleLoose(ubicSnap.child('lng').value);
      }

      if (almacLat == null || almacLng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo verificar la distancia: el almacén no tiene ubicación configurada.'),
          ),
        );
        return;
      }

      final distanceMeters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        almacLat,
        almacLng,
      );

      if (distanceMeters > 50) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estás a ${distanceMeters.toStringAsFixed(1)} m del almacén. Debes estar a 50 m o menos para unirte.'),
          ),
        );
        return;
      }

      // 5) Guardar registro en fila virtual
      final ahora = _fmtYYYYMMDDHHMMSS(DateTime.now());
      final payload = {
        'HoraVinculacion': ahora,
        'NombreDriver': nombre,
        'idDriver': userId,
        // Extras opcionales por si quieres guardar posición de ingreso:
        'LatitudIngreso': pos.latitude,
        'LongitudIngreso': pos.longitude,
      };

      await miNodoRef.set(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Te uniste a la fila virtual.')),
      );

      // 6) Navegar a la lista
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FilaVirtualListaPage(idAlmacen: widget.idAlmacen, nombreAlmacen: widget.nombreAlmacen),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error en fila virtual: $e')),
      );
    } finally {
      if (mounted) setState(() => _procesandoFilaVirtual = false);
    }
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    const headerColor = Color(0xFF1955CC);
    final count = _seleccionados.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado azul + escáner
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
                            'Recolección de paquetes22',
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

                  // Escáner QR
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: _permissionGranted
                          ? QRView(
                              key: _qrKey,
                              onQRViewCreated: (c) {
                                _qrController = c;
                                _qrController!.scannedDataStream.listen((scan) {
                                  final raw = scan.code ?? '';
                                  if (raw.isEmpty) return;
                                  _tryAddFromFirebase(raw);
                                });
                              },
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

                  // Nombre y dirección del almacén
                  Text(
                    widget.nombreAlmacen,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.direccionAlmacen,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // Buscador manual
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
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
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

            // Lista
            Expanded(
              child: _seleccionados.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'Escanea o ingresa un código para añadirlo a la lista.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                      itemCount: _seleccionados.length,
                      itemBuilder: (_, i) {
                        final code = _seleccionados[i];
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
                            title: Text('Orden\n#$code',
                                style: const TextStyle(height: 1.2)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _eliminar(code),
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
              // Con Firma
              Expanded(
                child: OutlinedButton(
                  onPressed: _onConFirma,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF2B59F2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Con Firma',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2B59F2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // NUEVO: Fila Virtual (estilo Outlined como "Con Firma" pero con borde amarillo)
              Expanded(
                child: OutlinedButton(
                  onPressed: _procesandoFilaVirtual ? null : _onFilaVirtual,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.amber, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: Colors.amber, // color del texto y ripple
                  ),
                  child: Text(
                    _procesandoFilaVirtual ? 'Procesando...' : 'Fila Virtual',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Finalizar
              Expanded(
                child: ElevatedButton(
                  onPressed: _seleccionados.isEmpty || _enviando ? null : _onFinalizar,
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

  // Placeholder si la cámara no tiene permiso
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
}
