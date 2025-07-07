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
  List<String> guias = [];
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
        // No pausamos ni mostramos diálogo
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MultiGuias'),
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
                const Text(
                  '📋 Guías escaneadas:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                // Lista de códigos QR
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: guias.length,
                    itemBuilder: (_, index) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.qr_code),
                        title: Text(guias[index]),
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
                        Navigator.pop(context); // Por ahora, solo regresar
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.all(16),
                      ),
                      child: const Text('Siguiente'),
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
