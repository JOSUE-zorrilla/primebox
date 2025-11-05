import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class FallidasMultiEntregaPage extends StatefulWidget {
  const FallidasMultiEntregaPage({
    super.key,
    this.initialGuias, // Puede contener idPBs o tnReference
  });

  final List<String>? initialGuias;

  @override
  State<FallidasMultiEntregaPage> createState() => _FallidasMultiEntregaPageState();
}

class _FallidasMultiEntregaPageState extends State<FallidasMultiEntregaPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;
  StreamSubscription<Barcode>? _scanSub;

  /// Usamos Set para evitar duplicados de forma O(1)
  final LinkedHashSet<String> _guiasFallidas = LinkedHashSet<String>();

  final TextEditingController _manualController = TextEditingController();

  bool _permissionGranted = false;

  /// Cola de trabajos de escaneo para procesar 1 por vez
  final List<String> _scanQueue = [];
  bool _isProcessing = false;

  /// Caches para acelerar:
  /// - Mapeo tnReference -> idPB resuelto
  final Map<String, String> _cacheResolved = {};
  /// - Existencia de idPB en la ruta asignada al driver
  final Map<String, bool> _cacheAssigned = {};

  /// Control simple para SnackBars (evita spam)
  void _showSnack(BuildContext context, String msg, {Color? bg}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
  }

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
    _precargarGuias(); // precarga usando initialGuias
  }

  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _qrController?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  /// Precargamos iniciales de forma secuencial para no saturar RTDB ni UI
  Future<void> _precargarGuias() async {
    final init = widget.initialGuias ?? const [];
    for (final raw in init) {
      final idPB = await _resolveToIdPB(raw);
      if (idPB != null) {
        await _validarYAgregarGuiaFallida(idPB, alreadyIdPB: true);
      } else {
        _showSnack(context, '❌ No se pudo resolver la guía inicial', bg: Colors.red);
      }
    }
  }

  /// Listener del QR
  void _onQRViewCreated(QRViewController controller) {
    _qrController = controller;

    // Cancelamos si ya había un sub (por hot reload o navegación)
    _scanSub?.cancel();
    _scanSub = controller.scannedDataStream.listen((scanData) async {
      final raw = scanData.code ?? '';
      if (raw.trim().isEmpty) return;

      // Encolamos y lanzamos el procesador si está libre
      _scanQueue.add(raw);
      _drainQueue(); // no await; se auto-controla
    });
  }

  /// Procesa la cola de lecturas de a una por vez, pausando la cámara para estabilidad
  Future<void> _drainQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_scanQueue.isNotEmpty) {
      final item = _scanQueue.removeAt(0);

      try {
        // Pausamos la cámara para evitar ráfagas y duplicados del plugin
        await _qrController?.pauseCamera();

        // Procesamos el código leído
        await _validarYAgregarGuiaFallida(item);

      } catch (e) {
        _showSnack(context, 'Error procesando lectura: $e', bg: Colors.red);
      } finally {
        // Pequeño respiro y reanudar cámara
        await Future.delayed(const Duration(milliseconds: 120));
        await _qrController?.resumeCamera();
      }
    }

    _isProcessing = false;
  }

  /// Decodifica seguro (evita FormatException por % inválidos) y recorta
  String _safeDecode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    try {
      return Uri.decodeFull(trimmed);
    } catch (_) {
      // Si falla la decodificación, usamos el original
      return trimmed;
    }
  }

  DatabaseReference _refPaquete(String uid, String idPB) {
    return FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$uid/Paquetes/$idPB',
    );
  }

  DatabaseReference _refHistoralIdPB(String tnReference) {
    return FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$tnReference/idPB',
    );
  }

  /// Resuelve un valor (tnReference o idPB) a un idPB válido
  Future<String?> _resolveToIdPB(String raw) async {
    final s = _safeDecode(raw);
    if (s.isEmpty) return null;

    // Cache ya resuelto
    if (_cacheResolved.containsKey(s)) return _cacheResolved[s];

    final user = FirebaseAuth.instance.currentUser;
    final String? uid = user?.uid;

    // Si parece idPB y existe como key en Paquetes/{idPB}, úsalo tal cual
    if (uid != null) {
      try {
        final refPaquete = _refPaquete(uid, s);
        final snap = await refPaquete.get();
        if (snap.exists) {
          _cacheResolved[s] = s;
          return s;
        }
      } catch (_) {
        // seguimos al mapeo tnReference -> idPB
      }
    }

    // Intento tnReference -> idPB
    try {
      final refIdPB = _refHistoralIdPB(s);
      final snapId = await refIdPB.get();
      final idPB = snapId.value?.toString().trim();
      if (snapId.exists && (idPB ?? '').isNotEmpty) {
        _cacheResolved[s] = idPB!;
        return idPB;
      }
    } catch (_) {
      // noop: devolveremos null si no se logra
    }

    return null;
  }

  Future<bool> _isAssignedToDriver(String uid, String idPB) async {
    // Cache de existencia
    final cacheKey = '$uid|$idPB';
    if (_cacheAssigned.containsKey(cacheKey)) {
      return _cacheAssigned[cacheKey]!;
    }
    try {
      final snap = await _refPaquete(uid, idPB).get();
      final exists = snap.exists;
      _cacheAssigned[cacheKey] = exists;
      return exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> _validarYAgregarGuiaFallida(String input, {bool alreadyIdPB = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Resolver a idPB si llega tnReference o no se sabe
    final idPB = alreadyIdPB ? _safeDecode(input) : (await _resolveToIdPB(input));
    if (idPB == null || idPB.isEmpty) {
      _showSnack(context, '❌ No se pudo resolver la guía a un id válido', bg: Colors.red);
      return;
    }

    // Evitar duplicados
    if (_guiasFallidas.contains(idPB)) {
      _showSnack(context, 'Ya estaba agregada: $idPB', bg: Colors.black87);
      return;
    }

    // Confirmar asignación
    final assigned = await _isAssignedToDriver(user.uid, idPB);
    if (!assigned) {
      _showSnack(context, '❌ Paquete no asignado', bg: Colors.red);
      return;
    }

    if (!mounted) return;
    setState(() {
      _guiasFallidas.add(idPB);
    });
  }

  void _agregarGuiaManual() {
    final texto = _manualController.text;
    if (texto.trim().isEmpty) return;
    _manualController.clear();

    // Encolamos igual que un scan (aprovecha la misma ruta optimizada)
    _scanQueue.add(texto);
    _drainQueue();
  }

  void _eliminarGuia(String idPB) {
    setState(() {
      _guiasFallidas.remove(idPB);
    });
  }

  /// Badge del contador para el AppBar
  Widget _counterBadge() {
    final count = _guiasFallidas.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.35)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Fallidas MultiEntrega'),
            const SizedBox(width: 8),
            _counterBadge(), // ← Contador en vivo al lado del título
          ],
        ),
      ),
      body: _permissionGranted
          ? Column(
              children: [
                SizedBox(
                  height: screenHeight * 0.25,
                  child: QRView(
                    key: qrKey,
                    onQRViewCreated: _onQRViewCreated,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualController,
                          decoration: const InputDecoration(
                            hintText: 'Ingresar ID (idPB o tnReference)',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _agregarGuiaManual(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _agregarGuiaManual,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '📋 Guías fallidas (idPB) agregadas:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _guiasFallidas.length,
                    itemBuilder: (_, index) {
                      final idPB = _guiasFallidas.elementAt(index);
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.qr_code),
                          title: Text(idPB),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _eliminarGuia(idPB),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, _guiasFallidas.toList());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.all(16),
                      ),
                      child: const Text(
                        'Siguiente',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: Text('Se requiere permiso de cámara para escanear.'),
            ),
    );
  }
}
