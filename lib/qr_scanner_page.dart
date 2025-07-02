import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key}); // Constructor con `const` obligatorio

  @override
  QRScannerPageState createState() => QRScannerPageState();
}

class QRScannerPageState extends State<QRScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  String? qrResult;
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

  @override
  void reassemble() {
    super.reassemble();
    controller?.pauseCamera();
    controller?.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: _permissionGranted
          ? Column(
              children: [
                Expanded(
                  flex: 4,
                  child: QRView(
                    key: qrKey,
                    onQRViewCreated: _onQRViewCreated,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Center(
                    child: Text(qrResult ?? 'Escanea un código QR'),
                  ),
                ),
              ],
            )
          : const Center(
              child: Text('Se requiere permiso de cámara para escanear.'),
            ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
controller.scannedDataStream.listen((scanData) {
  if (qrResult == null && mounted) {
    setState(() {
      qrResult = scanData.code;
    });

    controller.pauseCamera();

    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Código QR Escaneado'),
        content: Text(scanData.code ?? 'Sin datos'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              controller.resumeCamera();
            },
            child: const Text('Escanear otro'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Volver a pantalla anterior
            },
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
});

  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
