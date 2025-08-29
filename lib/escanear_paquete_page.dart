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

  // para deduplicar ráfagas del mismo código
  String? _ultimoCodigoProcesado;
  DateTime? _ultimoMomentoProcesado;

  // para cerrar el diálogo si sigue abierto al navegar
  bool _dialogAbierto = false;

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

  // Mostrar alert con el contenido escaneado; lo recordamos para poder cerrarlo al navegar
  void _showScannedAlert(String code) {
    if (!mounted) return;
    _dialogAbierto = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text('Código detectado'),
        content: SelectableText(code),
        actions: [
          TextButton(
            onPressed: () {
              _dialogAbierto = false;
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      _dialogAbierto = false;
    });
  }

  void _cerrarDialogSiAbierto() {
    if (!mounted) return;
    if (_dialogAbierto) {
      _dialogAbierto = false;
      Navigator.of(context, rootNavigator: true).pop(); // cierra el AlertDialog
    }
  }

  Future<void> _handleCode(String code) async {
    if (_procesando) return;
    setState(() => _procesando = true);

    // corta frames lo antes posible
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
        _cerrarDialogSiAbierto();
        await showDialog(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('No asignado'),
            content: Text('El paquete no lo tienes asignado'),
          ),
        );
        Navigator.pop(context); // volver a la pantalla anterior
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
        direccionEntrega: (m['DireccionEntrega'] ?? '').toString(),
        telefono: (m['Telefono'] ?? '').toString(),
        tnReference: (m['Referencia'] ?? '').toString(),
      );

      // Limpia la cámara ANTES de navegar
// Limpia la cámara ANTES de navegar
try {
  _controller?.pauseCamera();
  _controller?.dispose();
} catch (_) {}
_controller = null;


      // Cierra el diálogo del escaneo si sigue abierto y navega
      _cerrarDialogSiAbierto();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => GuiaEncontradaPage(data: data)),
      );
    } catch (e) {
      if (!mounted) return;
      _cerrarDialogSiAbierto();
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
      if (code.isEmpty || _procesando) return;

      // Deduplicación simple en ráfaga de < 800ms
      final ahora = DateTime.now();
      if (_ultimoCodigoProcesado == code &&
          _ultimoMomentoProcesado != null &&
          ahora.difference(_ultimoMomentoProcesado!).inMilliseconds < 800) {
        return;
      }
      _ultimoCodigoProcesado = code;
      _ultimoMomentoProcesado = ahora;

      _showScannedAlert(code); // muestra el diálogo
      _handleCode(code);       // y sigue el flujo
    });
  }

  @override
  void dispose() {
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
                QRView(
                  key: qrKey,
                  onQRViewCreated: _onQRViewCreated,
                ),
                if (_procesando)
                  Container(
                    color: Colors.black45,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}
