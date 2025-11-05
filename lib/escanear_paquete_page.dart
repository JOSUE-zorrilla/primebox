import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'guia_data.dart';
import 'guia_encontrada_page.dart';
import 'login_page.dart'; // por si usas globalUserId/globalNombre

class EscanearPaquetePage extends StatefulWidget {
  const EscanearPaquetePage({super.key});

  @override
  State<EscanearPaquetePage> createState() => _EscanearPaquetePageState();
}

class _EscanearPaquetePageState extends State<EscanearPaquetePage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _controller;

  bool _permissionGranted = false;
  bool _procesando = false;

  // deduplicación
  String? _ultimoCodigoProcesado;
  DateTime? _ultimoMomentoProcesado;

  // feedback instantáneo
  String _scanTexto = '';
  bool _mostrarBanner = false;
  Timer? _ocultarBannerTimer;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();
    if (mounted) setState(() => _permissionGranted = status.isGranted);
  }

  @override
  void reassemble() {
    super.reassemble();
    if (!_permissionGranted || _controller == null) return;
    try {
      _controller!.pauseCamera();
      _controller!.resumeCamera();
    } catch (_) {}
  }

  // Helper para armar la dirección concatenada
  String _composeDireccion(Map m) {
    String _s(dynamic v) => (v ?? '').toString().trim();

    final base = _s(m['DireccionEntrega']);
    final exterior = _s(m['Exterior']);
    final interior = _s(m['Interior']);
    final colonia = _s(m['Colonia']);
    final cp = _s(m['CodigoPostal']).isEmpty ? _s(m['CódigoPostal']) : _s(m['CodigoPostal']);

    final parts = <String>[];
    if (base.isNotEmpty) parts.add(base);
    if (exterior.isNotEmpty) parts.add('Ext. $exterior');
    if (interior.isNotEmpty) parts.add('Int. $interior');
    if (colonia.isNotEmpty) parts.add(colonia);
    if (cp.isNotEmpty) parts.add('CP $cp');

    return parts.join(', ');
  }

  // Muestra banner con el contenido del QR inmediatamente
  void _mostrarContenidoInstantaneo(String code, {Duration visible = const Duration(seconds: 2)}) {
    _ocultarBannerTimer?.cancel();
    setState(() {
      _scanTexto = code;
      _mostrarBanner = true;
    });
    _ocultarBannerTimer = Timer(visible, () {
      if (!mounted) return;
      setState(() => _mostrarBanner = false);
    });
  }

  Future<void> _handleCode(String code) async {
    if (_procesando) return;
    setState(() => _procesando = true);

    // Pausa la cámara después de mostrar el contenido, para evitar ráfagas
    try { await _controller?.pauseCamera(); } catch (_) {}

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = (globalUserId?.toString().trim().isNotEmpty ?? false)
          ? globalUserId!
          : (user?.uid ?? '');

      if (uid.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay usuario autenticado.')),
        );
        Navigator.pop(context);
        return;
      }

      // 1) ¿Está asignado?
      final asignadoRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$uid/Paquetes/$code',
      );
      final asignadoSnap = await asignadoRef.get();

      if (!asignadoSnap.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El paquete no lo tienes asignado.')),
        );
        Navigator.pop(context);
        return;
      }

      // 2) Leer datos en Historal/{code}
      final histRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$code',
      );
      final snap = await histRef.get();
      final m = (snap.value is Map) ? (snap.value as Map) : {};

      final data = GuiaData(
        id: code,
        nombreDestinatario: (m['NombreDestinatario'] ?? '').toString(),
        direccionEntrega: _composeDireccion(m),
        telefono: (m['Telefono'] ?? '').toString(),
        tnReference: (m['Referencia'] ?? '').toString(),
      );

      // Limpia cámara y navega
      try {
         _controller?.dispose();
      } catch (_) {}
      _controller = null;

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => GuiaEncontradaPage(data: data)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al procesar el código: $e')),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    _controller = controller;

    controller.scannedDataStream.listen((scan) {
      final code = scan.code?.trim() ?? '';
      if (code.isEmpty) return;

      // feedback instantáneo (sin bloquear)
      _mostrarContenidoInstantaneo(code);

      // control de ráfagas / reprocesado
      if (_procesando) return;
      final ahora = DateTime.now();
      if (_ultimoCodigoProcesado == code &&
          _ultimoMomentoProcesado != null &&
          ahora.difference(_ultimoMomentoProcesado!).inMilliseconds < 800) {
        return;
      }
      _ultimoCodigoProcesado = code;
      _ultimoMomentoProcesado = ahora;

      // continúa con la lógica normal en segundo plano
      _handleCode(code);
    });
  }

  @override
  void dispose() {
    _ocultarBannerTimer?.cancel();
    try { _controller?.dispose(); } catch (_) {}
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear código')),
      body: !_permissionGranted
          ? const Center(child: Text('Se requiere permiso de cámara para escanear.'))
          : Stack(
              children: [
                // Vista de cámara
                QRView(
                  key: qrKey,
                  onQRViewCreated: _onQRViewCreated,
                ),

                // Indicador de procesamiento en overlay (no bloquea el banner)
                if (_procesando)
                  IgnorePointer(
                    child: Container(
                      color: Colors.black26,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    ),
                  ),

                // Banner superior con el contenido del QR (aparece al instante)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  left: 0,
                  right: 0,
                  top: _mostrarBanner ? 0 : -80,
                  child: SafeArea(
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(color: Colors.white),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.qr_code, color: Colors.white),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Código detectado',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _scanTexto,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
