import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

// Globals
import 'login_page.dart' show globalUserId, globalNombre;

class DevolverAlmacenScanPage extends StatefulWidget {
  final String idAlmacen;
  final String nombreAlmacen;
  final String direccionAlmacen;

  const DevolverAlmacenScanPage({
    super.key,
    required this.idAlmacen,
    required this.nombreAlmacen,
    required this.direccionAlmacen,
  });

  @override
  State<DevolverAlmacenScanPage> createState() =>
      _DevolverAlmacenScanPageState();
}

class _DevolverAlmacenScanPageState extends State<DevolverAlmacenScanPage> {
  static const String _webhookUrl =
      'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_v5AXwXcf8XcQoivrBH5CFW';

  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR_DEVOLVER_ALMACEN');
  QRViewController? _qrController;
  bool _permissionGranted = false;
  bool _validandoCodigo = false;

  String? _codigoValidado;
  String? _error;

  final TextEditingController _nombreRecibeCtrl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _fotoFile;

  bool _enviando = false;

  final DateFormat _fmtFecha = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  @override
  void dispose() {
    _qrController?.dispose();
    _nombreRecibeCtrl.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _qrController?.pauseCamera();
    _qrController?.resumeCamera();
  }

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

  Future<void> _onCodigoEscaneado(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return;
    if (_validandoCodigo) return;

    setState(() {
      _validandoCodigo = true;
      _error = null;
    });

    final code = _norm(raw);
    final driverId = (globalUserId ?? '').toString().trim();

    if (driverId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró el id del usuario (idDriver).'),
          ),
        );
      }
      setState(() => _validandoCodigo = false);
      return;
    }

    try {
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$driverId/Paquetes/$code',
      );

      final snap = await ref.get();

      if (!mounted) return;

      if (snap.exists) {
        // Pausar cámara para no seguir leyendo
        await _qrController?.pauseCamera();
        setState(() {
          _codigoValidado = code;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paquete $code válido en tu ruta. Completa los datos.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El paquete $code no pertenece a tu ruta actual.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Error al validar código: $e');
    } finally {
      if (mounted) setState(() => _validandoCodigo = false);
    }
  }

  Future<void> _tomarFoto() async {
    try {
      final img = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
      );
      if (img != null) {
        setState(() => _fotoFile = img);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al tomar foto: $e')),
      );
    }
  }

  bool get _formValido {
    return _codigoValidado != null &&
        _codigoValidado!.isNotEmpty &&
        _nombreRecibeCtrl.text.trim().isNotEmpty &&
        _fotoFile != null &&
        !_enviando;
  }

  /// Sube la foto a Firebase Storage y regresa la URL pública
  Future<String?> _subirFotoYObtenerUrl() async {
    if (_fotoFile == null) return null;

    try {
      final driverId = (globalUserId ?? '').toString().trim();
      final codigo = _codigoValidado ?? 'SIN_CODIGO';
      final ts = DateTime.now().millisecondsSinceEpoch;

      // Ruta sugerida en storage
      final path =
          'DevolucionesAlmacen/${widget.idAlmacen}/$driverId/$codigo/$ts.jpg';

      final file = File(_fotoFile!.path);
      final ref = FirebaseStorage.instance.ref().child(path);

      final uploadTask = await ref.putFile(file);
      final url = await uploadTask.ref.getDownloadURL();
      return url;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir la foto: $e')),
      );
      return null;
    }
  }

  Future<void> _enviarDevolucion() async {
    if (!_formValido) return;

    final codigo = _codigoValidado!;
    final driverId = (globalUserId ?? '').toString().trim();

    if (driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró el id del usuario (idDriver).'),
        ),
      );
      return;
    }

    setState(() => _enviando = true);

    try {
      // 1) Subir foto a Storage
      final urlFoto = await _subirFotoYObtenerUrl();
      if (urlFoto == null) {
        // ya se mostró el error en _subirFotoYObtenerUrl
        setState(() => _enviando = false);
        return;
      }

      // 2) Construir payload para webhook
      final ahora = DateTime.now();
      final fechaStr = _fmtFecha.format(ahora); // YYYY-MM-DD HH:mm

      final payload = {
        'idGuia': codigo,
        'idDriver': driverId,
        'idAlmacen': widget.idAlmacen,
        'Fecha': fechaStr,
        'Foto': urlFoto, // 👈 URL pública que viene de Storage
        // Opcional: también puedes mandar quién recibe
        'NombreRecibe': _nombreRecibeCtrl.text.trim(),
        'NombreDriver': (globalNombre ?? '').toString(),
      };

      final resp = await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        // Si quieres, aquí puedes guardar algún log en Realtime Database
        // final refDev = FirebaseDatabase.instance.ref(
        //   'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/DevolucionesAlmacen/${widget.idAlmacen}/$codigo',
        // );
        // await refDev.set({
        //   'NombreRecibe': _nombreRecibeCtrl.text.trim(),
        //   'Fecha': fechaStr,
        //   'Foto': urlFoto,
        // });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paquete devuelto correctamente al almacén.'),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al devolver (status ${resp.statusCode}): ${resp.body}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al llamar al webhook: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const headerColor = Color(0xFF1955CC);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                                child: Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Align(
                          alignment: Alignment.center,
                          child: Text(
                            'Devolver a almacén',
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
                  const SizedBox(height: 12),
                  Text(
                    widget.nombreAlmacen,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.direccionAlmacen,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  // Escáner
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
                                _qrController!.scannedDataStream.listen(
                                  (scan) => _onCodigoEscaneado(scan.code),
                                );
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
                ],
              ),
            ),

            // Contenido
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Datos de devolución',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Text(
                                  'Guía: ',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Expanded(
                                  child: Text(
                                    _codigoValidado ?? 'Escanea un paquete',
                                    style: TextStyle(
                                      color: _codigoValidado != null
                                          ? Colors.black87
                                          : Colors.black45,
                                      fontWeight: _codigoValidado != null
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nombreRecibeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nombre de quien recibe en el almacén',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _tomarFoto,
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: const Text('Tomar foto'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1955CC),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (_fotoFile != null)
                                  const Icon(Icons.check_circle,
                                      color: Colors.green),
                                if (_fotoFile != null)
                                  const SizedBox(width: 4),
                                if (_fotoFile != null)
                                  const Text(
                                    'Foto lista',
                                    style: TextStyle(color: Colors.green),
                                  ),
                              ],
                            ),
                            if (_fotoFile != null) ...[
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_fotoFile!.path),
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          color: const Color(0xFFF2F3F7),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _formValido ? _enviarDevolucion : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B59F2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _enviando ? 'Enviando...' : 'Devolver a Almacén',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
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
            const Icon(Icons.photo_camera_front,
                color: Colors.white70, size: 40),
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
