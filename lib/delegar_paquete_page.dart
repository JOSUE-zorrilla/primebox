// delegar_paquete_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:firebase_database/firebase_database.dart';

// Usa las variables globales como en las otras pantallas
import 'login_page.dart' show globalNombre, globalUserId, globalIdCiudad;

// Segunda pantalla
import 'delegar_paquete_escanear_paquetes_page.dart';

class DelegarPaquetePage extends StatefulWidget {
  const DelegarPaquetePage({super.key});

  @override
  State<DelegarPaquetePage> createState() => _DelegarPaquetePageState();
}

class _DelegarPaquetePageState extends State<DelegarPaquetePage> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR_DELEGAR_COMPANERO');
  QRViewController? _qrController;
  bool _permissionGranted = false;
  bool _navegando = false;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  @override
  void dispose() {
    _qrController?.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    // requerido para hot reload en Android
    _qrController?.pauseCamera();
    _qrController?.resumeCamera();
  }

  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _permissionGranted = status.isGranted);
  }

  String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), '').replaceAll('#', '');

  Future<void> _onScan(String? raw) async {
  if (_navegando) return; // evitar doble navegación
  if (raw == null || raw.trim().isEmpty) return;

  final code = _norm(raw);
  if (code.isEmpty) return;

  _qrController?.pauseCamera();

  try {
    // Buscar nombre del compañero en Conductores/{code}
    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/$code',
    );
    final snap = await ref.get();

    // 👉🏼 Si NO existe, avisamos y NO navegamos
    if (!snap.exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El ID escaneado no existe en Conductores.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      // reanudar cámara para reintentar
      _qrController?.resumeCamera();
      return;
    }

    // Existe. Opcionalmente leemos el nombre (si es Map)
    String nombreCompanero = '—';
    if (snap.value is Map) {
      final map = Map<String, dynamic>.from(snap.value as Map);
      nombreCompanero = (map['Nombre'] ?? map['nombre'] ?? '—').toString();
    }

    if (!mounted) return;
    _navegando = true;

    // Ir a segunda pantalla para escanear paquetes
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DelegarPaqueteEscanearPaquetesPage(
          idCompanero: code,
          nombreCompanero: nombreCompanero,
        ),
      ),
    );
  } catch (e) {
    // Error inesperado: permitimos reintentar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error leyendo el ID: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } finally {
    if (!mounted) return;
    _navegando = false;
    // Si navegamos, al volver se reanuda; si no navegamos, ya reanudamos arriba
    _qrController?.resumeCamera();
  }
}

  @override
  Widget build(BuildContext context) {
    const headerColor = Color(0xFF1955CC);
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header minimal
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
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
                          width: 40, height: 40,
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Leer QR Driver',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Escáner a pantalla casi completa
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: media.size.height, // ocupa casi todo
                    child: _permissionGranted
                        ? QRView(
                            key: _qrKey,
                            onQRViewCreated: (controller) {
                              _qrController = controller;
                              controller.scannedDataStream.listen((scanData) {
                                final raw = scanData.code ?? '';
                                if (raw.isEmpty) return;
                                _onScan(raw);
                              });
                            },
                            overlay: QrScannerOverlayShape(
                              borderColor: Colors.white,
                              borderRadius: 12,
                              borderLength: 28,
                              borderWidth: 8,
                              cutOutWidth: media.size.width * 0.86,
                              cutOutHeight: media.size.width * 0.86,
                            ),
                          )
                        : _buildPermissionPlaceholder(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_camera_front, color: Colors.white70, size: 40),
            const SizedBox(height: 8),
            const Text('Se requiere permiso de cámara',
                style: TextStyle(color: Colors.white70)),
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
