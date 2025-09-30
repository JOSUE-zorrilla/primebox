// devoluciones_scan_page.dart
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_database/firebase_database.dart';
import 'devolucion_formulario_page.dart';

class DevolucionesScanPage extends StatefulWidget {
  const DevolucionesScanPage({super.key});

  @override
  State<DevolucionesScanPage> createState() => _DevolucionesScanPageState();
}

class _DevolucionesScanPageState extends State<DevolucionesScanPage> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR_DEVOLUCION');
  QRViewController? _controller;

  bool _permissionGranted = false;
  bool _busyScan = false; // evita lecturas múltiples
  bool _pausedForNavigation = false;

  final TextEditingController _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  /// Pide permiso de cámara y habilita el escáner
  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _permissionGranted = status.isGranted;
    });
  }

  /// Lógica cuando el QRView está listo
  void _onQRViewCreated(QRViewController controller) {
    _controller = controller;

    _controller?.scannedDataStream.listen((scanData) async {
      if (_busyScan || _pausedForNavigation) return;
      final code = scanData.code ?? '';
      await _procesarQR(code.trim());
    });
  }

  /// Verifica si Historal/<idGuia> existe.
  Future<void> _procesarQR(String idGuia) async {
    if (idGuia.isEmpty) return;

    setState(() => _busyScan = true);
    try {
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$idGuia',
      );
      final snap = await ref.get();

      if (!mounted) return;

      if (snap.exists) {
        // Pausamos cámara para evitar que siga leyendo
        _pausedForNavigation = true;
        await _controller?.pauseCamera();

        // Reemplazamos esta pantalla por el formulario (atrás -> Paquetes)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DevolucionFormularioPage(idGuia: idGuia),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró el paquete en Historal con ese QR.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error verificando QR: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyScan = false);
    }
  }

  /// Agregar por input manual (fallback)
  Future<void> _agregarManual() async {
    final texto = _manualController.text.trim();
    if (texto.isEmpty) return;
    await _procesarQR(texto);
    _manualController.clear();
  }

  @override
  void reassemble() {
    // Manejo recomendado por qr_code_scanner para hot-reload
    super.reassemble();
    if (_controller != null && !_pausedForNavigation) {
      if (Theme.of(context).platform == TargetPlatform.android) {
        _controller!.pauseCamera();
      }
      _controller!.resumeCamera();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final Color? amarillo = Colors.amber[700];

    return Scaffold(
      backgroundColor: Colors.amber[50],
      appBar: AppBar(
        title: const Text('Devoluciones - Escanear'),
        backgroundColor: amarillo,
        foregroundColor: Colors.black,
      ),
      body: !_permissionGranted
          ? const Center(
              child: Text(
                'Se requiere permiso de cámara para escanear.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : Column(
              children: [
                const SizedBox(height: 10),
                const Text(
                  'Escanea el QR del paquete a devolver',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // Visor del escáner
                SizedBox(
                  height: screenHeight * 0.35,
                  child: Stack(
                    children: [
                      QRView(
                        key: _qrKey,
                        onQRViewCreated: _onQRViewCreated,
                        overlay: QrScannerOverlayShape(
                          borderColor: Colors.black,
                          borderRadius: 12,
                          borderLength: 28,
                          borderWidth: 8,
                          cutOutSize: screenHeight * 0.27,
                        ),
                      ),
                      if (_busyScan)
                        Container(
                          color: Colors.black.withOpacity(0.35),
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualController,
                          decoration: const InputDecoration(
                            hintText: 'Ingresar ID manualmente',
                            filled: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _agregarManual(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _agregarManual,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: amarillo,
                          foregroundColor: Colors.black,
                        ),
                        child: const Icon(Icons.check),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Apunta la cámara al código QR del paquete o ingresa el ID manualmente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[800]),
                  ),
                ),
                const SizedBox(height: 12),

                // Controles básicos por si deseas pausar/reanudar
                

                const SizedBox(height: 12),
              ],
            ),
    );
  }
}
