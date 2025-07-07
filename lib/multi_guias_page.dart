import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

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
      if (!guias.contains(code)) {
        setState(() {
          guias.add(code);
        });
      }
    });
  }

  void _agregarGuiaManual() {
    final texto = _manualController.text.trim();
    if (texto.isNotEmpty && !guias.contains(texto)) {
      setState(() {
        guias.add(texto);
        _manualController.clear();
      });
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
                // Escáner en 25% superior
                SizedBox(
                  height: screenHeight * 0.25,
                  child: QRView(
                    key: qrKey,
                    onQRViewCreated: _onQRViewCreated,
                  ),
                ),
                const SizedBox(height: 10),

                // Campo para ingreso manual
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
                        // Aquí puedes enviar las guías a Firebase u otra pantalla
                        Navigator.pop(context);
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
