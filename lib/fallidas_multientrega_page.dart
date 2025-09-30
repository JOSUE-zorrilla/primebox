import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class FallidasMultiEntregaPage extends StatefulWidget {
  const FallidasMultiEntregaPage({
    super.key,
    this.initialGuias, // ← Debe contener idPBs (aunque igual resolvemos si llega tnReference)
  });

  final List<String>? initialGuias;

  @override
  State<FallidasMultiEntregaPage> createState() => _FallidasMultiEntregaPageState();
}

class _FallidasMultiEntregaPageState extends State<FallidasMultiEntregaPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  final List<String> guiasFallidas = []; // <-- guardamos idPBs
  final TextEditingController _manualController = TextEditingController();
  bool _permissionGranted = false;
  bool _busyScan = false; // evita duplicados durante validación

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
    _precargarGuias(); // precarga usando initialGuias
  }

  /// Resuelve un valor (tnReference o idPB) a un idPB válido
  Future<String?> _resolveToIdPB(String raw) async {
    final s = Uri.decodeFull(raw).trim();
    if (s.isEmpty) return null;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Si ya luce como idPB y existe como key en Paquetes, úsalo tal cual
      final refPaquete = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/$s',
      );
      try {
        final snap = await refPaquete.get();
        if (snap.exists) return s; // es un idPB válido
      } catch (_) {}
    }

    // De lo contrario, intenta mapear tnReference -> idPB en Historal
    try {
      final refIdPB = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$s/idPB',
      );
      final snapId = await refIdPB.get();
      final idPB = snapId.value?.toString().trim();
      if (snapId.exists && (idPB ?? '').isNotEmpty) {
        return idPB;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _precargarGuias() async {
    final init = widget.initialGuias ?? const [];
    for (final raw in init) {
      final idPB = await _resolveToIdPB(raw);
      if (idPB != null) {
        await _validarYAgregarGuiaFallida(idPB, alreadyIdPB: true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ No se pudo resolver la guía inicial'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (mounted) {
      setState(() {
        _permissionGranted = status.isGranted;
      });
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) async {
      if (_busyScan) return;
      _busyScan = true;
      final code = scanData.code ?? '';
      await _validarYAgregarGuiaFallida(code); // puede llegar tnReference; se resuelve adentro
      _busyScan = false;
    });
  }

  Future<void> _validarYAgregarGuiaFallida(String input, {bool alreadyIdPB = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // resolver a idPB si llega tnReference o no se sabe
    final idPB = alreadyIdPB ? input.trim() : (await _resolveToIdPB(input))?.trim();
    if (idPB == null || idPB.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No se pudo resolver la guía a un id válido'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (guiasFallidas.contains(idPB)) return;

    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/$idPB',
    );

    try {
      final snapshot = await ref.get();
      if (snapshot.exists) {
        if (!mounted) return;
        setState(() => guiasFallidas.add(idPB)); // guardamos idPB
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Paquete no asignado'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error consultando RTDB: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _agregarGuiaManual() {
    final texto = _manualController.text;
    if (texto.trim().isNotEmpty) {
      _validarYAgregarGuiaFallida(texto); // puede ser tnReference; se resuelve a idPB
      _manualController.clear();
    }
  }

  void _eliminarGuia(String idPB) {
    setState(() {
      guiasFallidas.remove(idPB);
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
        title: const Text('Fallidas MultiEntrega'),
        backgroundColor: Colors.red,
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
                            hintText: 'Ingresar ID (idPB o tnReference)',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _agregarGuiaManual(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _agregarGuiaManual,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '📋 Guías fallidas (idPB) agregadas:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: guiasFallidas.length,
                    itemBuilder: (_, index) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.qr_code),
                        title: Text(guiasFallidas[index]), // idPB
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _eliminarGuia(guiasFallidas[index]),
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
                        Navigator.pop(context, guiasFallidas); // devuelve lista de idPBs
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
