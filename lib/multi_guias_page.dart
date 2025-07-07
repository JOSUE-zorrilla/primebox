import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class MultiGuiasPage extends StatefulWidget {
  const MultiGuiasPage({super.key});

  @override
  State<MultiGuiasPage> createState() => _MultiGuiasPageState();
}

class _MultiGuiasPageState extends State<MultiGuiasPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  final List<String> guias = [];
  final TextEditingController _manualController = TextEditingController();
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    setState(() {
      _permissionGranted = status.isGranted;
    });
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      final code = scanData.code ?? '';
      _validarYAgregarGuia(code);
    });
  }

  Future<void> _validarYAgregarGuia(String id) async {
    if (guias.contains(id)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/$id',
    );

    final snapshot = await ref.get();

    if (snapshot.exists) {
      setState(() {
        guias.add(id);
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Paquete no asignado'),
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
                // Escáner QR
                SizedBox(
                  height: screenHeight * 0.25,
                  child: QRView(
                    key: qrKey,
                    onQRViewCreated: _onQRViewCreated,
                  ),
                ),
                const SizedBox(height: 10),

                // Campo de ingreso manual
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

                // Lista de guías
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

                // Botón Siguiente
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Por ahora solo cerrar
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
