// delegar_paquete_escanear_paquetes_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

// Variables globales como en otras pantallas
import 'login_page.dart' show globalNombre, globalUserId, globalIdCiudad;

// Destino final tras enviar
import 'paquetes_page.dart';

class DelegarPaqueteEscanearPaquetesPage extends StatefulWidget {
  final String idCompanero;
  final String nombreCompanero;

  const DelegarPaqueteEscanearPaquetesPage({
    super.key,
    required this.idCompanero,
    required this.nombreCompanero,
  });

  @override
  State<DelegarPaqueteEscanearPaquetesPage> createState() =>
      _DelegarPaqueteEscanearPaquetesPageState();
}

class _DelegarPaqueteEscanearPaquetesPageState
    extends State<DelegarPaqueteEscanearPaquetesPage> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR_DELEGAR_PAQUETES');
  QRViewController? _qrController;
  bool _permissionGranted = false;
  bool _enviando = false;

  // Mapa requerido por el webhook: { "ABC123": {"idPaquete":"ABC123"}, ... }
  final Map<String, Map<String, String>> _paquetesData = {};
  // Orden visual: el último escaneo va en la posición 0 (arriba)
  final List<String> _paquetesOrden = [];

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
    _qrController?.pauseCamera();
    _qrController?.resumeCamera();
  }

  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _permissionGranted = status.isGranted);
  }

  String _norm(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), '').replaceAll('#', '');

  Future<void> _onScan(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return;

    final code = _norm(raw);
    if (code.isEmpty) return;

    // Pausamos para evitar múltiples lecturas del mismo frame
    await _qrController?.pauseCamera();

    try {
      final userId = (globalUserId ?? '').trim();
      if (userId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay usuario global (globalUserId) definido.')),
        );
        return;
      }

      // Validar existencia del paquete en la ruta indicada
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$userId/Paquetes/$code',
      );
      final snap = await ref.get();

      if (!mounted) return;

      if (snap.exists) {
        setState(() {
          if (_paquetesData.containsKey(code)) {
            _paquetesOrden.remove(code);
            _paquetesOrden.insert(0, code);
          } else {
            _paquetesData[code] = {"idPaquete": code};
            _paquetesOrden.insert(0, code);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paquete $code agregado.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('El paquete $code no existe en tu RepartoDriver.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al validar paquete: $e')),
      );
    } finally {
      await _qrController?.resumeCamera();
    }
  }

  // ==== Envío al webhook ====
  Future<void> _confirmarYEnviar() async {
    if (_paquetesData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escanea al menos un paquete.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Desea confirmar la entrega de paquetes al nuevo driver?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _enviando = true);

    try {
      final now = DateTime.now();
      final yyyy = now.year.toString().padLeft(4, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final hh = now.hour.toString().padLeft(2, '0');
      final mi = now.minute.toString().padLeft(2, '0');
      final ss = now.second.toString().padLeft(2, '0');

      final fechaCorta = '$yyyy-$mm-$dd';
      final fechaLarga = '$yyyy-$mm-$dd $hh:$mm:$ss';
      final timestampMs = now.millisecondsSinceEpoch;

      // id aleatorio (simple, suficiente para correlación)
      final rand = Random();
      final randomSuffix = List.generate(6, (_) => rand.nextInt(36))
          .map((n) => n < 10 ? n.toString() : String.fromCharCode(87 + n)) // 0-9,a-z
          .join();
      final idGeneralDelegar = 'DLG${timestampMs}_$randomSuffix';

      final payload = {
        "NombreCompanero": widget.nombreCompanero,
        "NombreUsuario": (globalNombre ?? '').toString(),
        "YYYYMMDD": fechaCorta,
        "YYYYMMDDHHMMSS": fechaLarga,
        "idCompanero": widget.idCompanero,
        "idGeneralDelegar": idGeneralDelegar,
        "idUsuario": (globalUserId ?? '').toString(),
        "paquetesdata": _paquetesData, // { "ABC": {"idPaquete":"ABC"}, ... }
        "timestamp": timestampMs,
      };

      final uri = Uri.parse(
        'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_pdcT8UcpZUMoigbMF7ZZdU',
      );
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delegación enviada correctamente.')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PaquetesPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error del servidor (${resp.statusCode}): ${resp.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const headerColor = Color(0xFF1955CC);
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado + escáner
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
                       Align(
  alignment: Alignment.center,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Delegar paquetes',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      const SizedBox(width: 8),
      if (_paquetesData.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${_paquetesData.length}',
            style: const TextStyle(
              color: Color(0xFF1955CC), // headerColor
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
    ],
  ),
),

                        const Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(width: 36, height: 36),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Escáner de paquetes
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: _permissionGranted
                          ? QRView(
                              key: _qrKey,
                              onQRViewCreated: (c) {
                                _qrController = c;
                                _qrController!.scannedDataStream.listen((scan) {
                                  final raw = scan.code ?? '';
                                  if (raw.isEmpty) return;
                                  _onScan(raw);
                                });
                              },
                              overlay: QrScannerOverlayShape(
                                borderColor: Colors.white,
                                borderRadius: 8,
                                borderLength: 20,
                                borderWidth: 6,
                                cutOutHeight: 180,
                                cutOutWidth: media.size.width * 0.86,
                              ),
                            )
                          : _buildPermissionPlaceholder(),
                    ),
                  ),
                ],
              ),
            ),

            // Lista de paquetes (nuevo diseño)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                child: _paquetesOrden.isEmpty
                    ? const Center(
                        child: Text(
                          'Escanea paquetes para agregarlos a la delegación.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _paquetesOrden.length,
                        itemBuilder: (context, idx) {
                          final code = _paquetesOrden[idx];
                          return _PaqueteTile(
                            code: code,
                            onRemove: () {
                              setState(() {
                                _paquetesData.remove(code);
                                _paquetesOrden.remove(code);
                              });
                            },
                          );
                        },
                      ),
              ),
            ),

            // Botón único inferior
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _enviando
                      ? null
                      : (_paquetesData.isEmpty ? null : _confirmarYEnviar),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B59F2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Siguiente'),
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
      child: const Center(
        child: Text(
          'Se requiere permiso de cámara',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

/// ---- UI: Tile para el listado con el estilo de la imagen ----
class _PaqueteTile extends StatelessWidget {
  final String code;
  final VoidCallback onRemove;

  const _PaqueteTile({
    required this.code,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    // Colores basados en la imagen
    const azulIcono = Color(0xFF2B59F2);
    const textoSuave = Color(0xFF9AA3B2); // gris claro para "Orden"
    const divider = Color(0xFFE6E8EE);

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Ícono dentro de un contenedor redondeado
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: azulIcono, width: 1.6),
                ),
                child: const Center(
                  child: Icon(
                    Icons.inventory_2_rounded,
                    size: 20,
                    color: azulIcono,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Texto "Orden" + código
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Orden',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textoSuave,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#$code',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF232B3A),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              // Botón X rojo
              IconButton(
                onPressed: onRemove,
                tooltip: 'Eliminar',
                icon: const Icon(Icons.close_rounded),
                color: Colors.redAccent,
              ),
            ],
          ),
        ),

        // Divisor inferior como en la referencia
        const SizedBox(height: 8),
        const Divider(
          color: divider,
          height: 1,
          thickness: 1,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
