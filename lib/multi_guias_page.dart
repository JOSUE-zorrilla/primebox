import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class MultiGuiasPage extends StatefulWidget {
  final List<String>? initialGuias; // 👈 nuevo

  const MultiGuiasPage({super.key, this.initialGuias});

  @override
  State<MultiGuiasPage> createState() => _MultiGuiasPageState();
}

class _MultiGuiasPageState extends State<MultiGuiasPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  final List<String> guias = [];
  final TextEditingController _manualController = TextEditingController();
  bool _permissionGranted = false;

  // Para evitar disparos duplicados muy rápidos del escáner
  bool _busyScan = false;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  /// Modifica tu _checkCameraPermission para cargar initialGuias cuando termine
  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    setState(() {
      _permissionGranted = status.isGranted;
    });

    // 👇 Precarga las guías iniciales (si las hay)
    if (widget.initialGuias != null && widget.initialGuias!.isNotEmpty) {
      for (final raw in widget.initialGuias!) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        await _validarYAgregarGuia(id, fromPreload: true);
      }
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) async {
      if (_busyScan) return;
      _busyScan = true;
      final code = scanData.code ?? '';
      await _validarYAgregarGuia(code);
      _busyScan = false;
    });
  }

  Future<void> _validarYAgregarGuia(String id, {bool fromPreload = false}) async {
    if (id.trim().isEmpty) {
      return;
    }

    if (guias.contains(id)) {
      // ya estaba, lo ignoramos
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/$id',
    );

    try {
      final snapshot = await ref.get();

      if (snapshot.exists) {
        setState(() {
          guias.add(id);
        });
      } else {
        if (mounted && !fromPreload) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Paquete no asignado'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && !fromPreload) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error consultando RTDB: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _agregarGuiaManual() {
    final texto = _manualController.text.trim();
    if (texto.isNotEmpty) {
      _validarYAgregarGuia(texto);
      _manualController.clear();
    }
  }

  void _eliminarGuia(String id) {
    setState(() {
      guias.remove(id);
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MultiGuías'),
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
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
                          onSubmitted: (_) => _agregarGuiaManual(), // opcional
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
                    itemCount: guias.length,
                    itemBuilder: (_, index) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.qr_code),
                        title: Text(guias[index]),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _eliminarGuia(guias[index]),
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
                        Navigator.pop(context, guias); // <-- retorna la lista
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
