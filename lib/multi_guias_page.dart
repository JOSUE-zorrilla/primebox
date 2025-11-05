import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class MultiGuiasPage extends StatefulWidget {
  final List<String>? initialGuias;

  const MultiGuiasPage({super.key, this.initialGuias});

  @override
  State<MultiGuiasPage> createState() => _MultiGuiasPageState();
}

class _MultiGuiasPageState extends State<MultiGuiasPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;
  StreamSubscription<Barcode>? _scanSub;

  /// Usamos Set (LinkedHashSet por defecto) para evitar duplicados manteniendo orden de inserción
  final Set<String> _guias = <String>{};
  final TextEditingController _manualController = TextEditingController();

  bool _permissionGranted = false;

  /// Cola de lecturas (escáner y entrada manual) para procesar 1 por vez
  final List<String> _scanQueue = [];
  bool _isProcessing = false;

  /// Cache para evitar repetir lecturas a RTDB (uid|id -> asignado?)
  final Map<String, bool> _cacheAssigned = {};

  void _showSnack(String msg, {Color? bg}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
  }

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _qrController?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (!mounted) return;
    setState(() => _permissionGranted = status.isGranted);

    // Precarga inicial usando la misma cola/procesador
    final init = widget.initialGuias ?? const [];
    for (final raw in init) {
      final v = raw.trim();
      if (v.isEmpty) continue;
      _enqueue(v);
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrController = controller;

    // Cancelar subscripción previa (hot reload o reapertura)
    _scanSub?.cancel();

    _scanSub = controller.scannedDataStream.listen((scanData) {
      final code = (scanData.code ?? '').trim();
      if (code.isEmpty) return;
      _enqueue(code);
    });
  }

  /// Encola la lectura y arranca el procesado si está libre
  void _enqueue(String value) {
    _scanQueue.add(value);
    _drainQueue(); // no await; corre en background controlado
  }

  /// Procesa la cola secuencialmente, pausando la cámara para estabilidad
  Future<void> _drainQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_scanQueue.isNotEmpty) {
      final current = _scanQueue.removeAt(0);

      try {
        // Evitar duplicados aquí temprano (ahorra red y UI)
        if (_guias.contains(current)) {
          _showSnack('Ya agregada: $current', bg: Colors.black87);
          continue;
        }

        // Pausar cámara para evitar ráfagas del plugin
        await _qrController?.pauseCamera();

        // Validar con RTDB y agregar si corresponde
        await _validarYAgregarGuia(current);
      } catch (e) {
        _showSnack('Error procesando: $e', bg: Colors.red);
      } finally {
        // Pequeño respiro + reanudar cámara
        await Future.delayed(const Duration(milliseconds: 120));
        await _qrController?.resumeCamera();
      }
    }

    _isProcessing = false;
  }

  DatabaseReference _refPaquete(String uid, String id) {
    return FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$uid/Paquetes/$id',
    );
  }

  Future<bool> _isAssignedToDriver(String uid, String id) async {
    final key = '$uid|$id';
    final cached = _cacheAssigned[key];
    if (cached != null) return cached;

    try {
      final snap = await _refPaquete(uid, id).get();
      final exists = snap.exists;
      _cacheAssigned[key] = exists;
      return exists;
    } catch (_) {
      _cacheAssigned[key] = false;
      return false;
    }
  }

  Future<void> _validarYAgregarGuia(String id) async {
    final candidate = id.trim();
    if (candidate.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final assigned = await _isAssignedToDriver(user.uid, candidate);
    if (!assigned) {
      _showSnack('❌ Paquete no asignado', bg: Colors.red);
      return;
    }

    if (!mounted) return;
    setState(() {
      _guias.add(candidate);
    });
  }

  void _agregarGuiaManual() {
    final texto = _manualController.text.trim();
    if (texto.isEmpty) return;
    _manualController.clear();
    _enqueue(texto);
  }

  void _eliminarGuia(String id) {
    setState(() {
      _guias.remove(id);
    });
  }

  /// Badge/contador junto al título
  Widget _buildCounterBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade600,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Text(
          '${_guias.length}',
          key: ValueKey<int>(_guias.length),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          semanticsLabel: 'Cantidad de guías: ${_guias.length}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final guiasList = _guias.toList(); // mantener orden de inserción

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('MultiGuías'),
            const SizedBox(width: 8),
            _buildCounterBadge(), // ⬅️ contador al lado del título
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
                            hintText: 'Ingresar ID manualmente',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _agregarGuiaManual(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _agregarGuiaManual,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '📋 Guías escaneadas:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: guiasList.length,
                    itemBuilder: (_, index) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.qr_code),
                        title: Text(guiasList[index]),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _eliminarGuia(guiasList[index]),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, guiasList); // retorna la lista
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
