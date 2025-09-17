import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

class RecogerAlmacenScanPage extends StatefulWidget {
  final String idAlmacen;
  final String nombreAlmacen;
  final String direccionAlmacen;

  const RecogerAlmacenScanPage({
    super.key,
    required this.idAlmacen,
    required this.nombreAlmacen,
    required this.direccionAlmacen,
  });

  @override
  State<RecogerAlmacenScanPage> createState() => _RecogerAlmacenScanPageState();
}

class _RecogerAlmacenScanPageState extends State<RecogerAlmacenScanPage> {
  // Escáner
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR_ALMACEN');
  QRViewController? _qrController;
  bool _permissionGranted = false;
  final Set<String> _codesProcesados = {};

  // Lista de códigos aceptados (existentes en Firebase)
  final List<String> _seleccionados = [];

  // Buscador manual
  final TextEditingController _buscarCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  @override
  void dispose() {
    _qrController?.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _qrController?.pauseCamera();
    _qrController?.resumeCamera();
  }

  // ====== permisos cámara ======
  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
    }
  }

  String _norm(String s) =>
      s.trim().toUpperCase().replaceAll(' ', '').replaceAll('#', '');

  // ====== verificación en Firebase ======
  Future<void> _tryAddFromFirebase(String rawCode) async {
    final code = _norm(rawCode);
    if (code.isEmpty) return;

    // evita “rebote” del lector
    if (_codesProcesados.contains(code)) return;
    _codesProcesados.add(code);

    try {
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Almacen/${widget.idAlmacen}/Paquetes/$code',
      );
      final snap = await ref.get();

      if (snap.exists) {
        final yaEsta = _seleccionados.contains(code);
        if (yaEsta) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Este paquete ya fue añadido.')),
          );
        } else {
          setState(() => _seleccionados.add(code));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El código no pertenece a este almacén.'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al validar: $e')),
      );
    }
  }

  void _agregarPorInput() {
    final txt = _buscarCtrl.text;
    if (txt.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un código en el buscador.')),
      );
      return;
    }
    _tryAddFromFirebase(txt);
    _buscarCtrl.clear();
  }

  void _eliminar(String code) {
    setState(() {
      _seleccionados.remove(code);
    });
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    const headerColor = Color(0xFF1955CC);
    final count = _seleccionados.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado azul + escáner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              decoration: const BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 40,
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
                                width: 36,
                                height: 36,
                                child: Icon(Icons.arrow_back_ios_new_rounded,
                                    size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        const Align(
                          alignment: Alignment.center,
                          child: Text(
                            'Recolección de paquetes',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Escáner QR
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: _permissionGranted
                          ? QRView(
                              key: _qrKey,
                              onQRViewCreated: (c) {
                                _qrController = c;
                                _qrController!.scannedDataStream.listen((scan) {
                                  final raw = scan.code ?? '';
                                  if (raw.isEmpty) return;
                                  _tryAddFromFirebase(raw);
                                });
                              },
                              overlay: QrScannerOverlayShape(
                                borderColor: Colors.white,
                                borderRadius: 8,
                                borderLength: 20,
                                borderWidth: 6,
                                cutOutHeight: 140,
                                cutOutWidth: 280,
                              ),
                            )
                          : _buildPermissionPlaceholder(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Nombre y dirección del almacén
                  Text(
                    widget.nombreAlmacen,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.direccionAlmacen,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // Buscador manual
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buscarCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _agregarPorInput(),
                          decoration: InputDecoration(
                            hintText: 'Buscar o escanear',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: _agregarPorInput,
                          borderRadius: BorderRadius.circular(10),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(Icons.more_horiz, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Lista
            Expanded(
              child: _seleccionados.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'Escanea o ingresa un código para añadirlo a la lista.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                      itemCount: _seleccionados.length,
                      itemBuilder: (_, i) {
                        final code = _seleccionados[i];
                        return Card(
                          elevation: 1.5,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFEFF3FF),
                              child: Icon(Icons.inventory_2_outlined,
                                  color: Color(0xFF1955CC)),
                            ),
                            title: Text('Orden\n#$code',
                                style: const TextStyle(height: 1.2)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _eliminar(code),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // Botón inferior (estético, puedes conectar a firma si lo necesitas)
      bottomSheet: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          color: const Color(0xFFF2F3F7),
          child: ElevatedButton(
            onPressed: () {
              // Aquí puedes abrir un flujo de "Firma Digital" si lo deseas
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Acción de firma pendiente de integrar.')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2B59F2),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Firma Digital',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  // Placeholder si la cámara no tiene permiso
  Widget _buildPermissionPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_camera_front, color: Colors.white70, size: 40),
            const SizedBox(height: 8),
            const Text(
              'Se requiere permiso de cámara',
              style: TextStyle(color: Colors.white70),
            ),
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
