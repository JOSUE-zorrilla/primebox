// recolectados_detalle_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

// Globales
import 'login_page.dart' show globalUserId, globalNombre;
// Redirección final
import 'paquetes_page.dart'; // Asegúrate que este archivo existe

class RecolectadosDetallePage extends StatefulWidget {
  final String idCentroRecoleccion;
  final String nombreCentro;

  const RecolectadosDetallePage({
    super.key,
    required this.idCentroRecoleccion,
    required this.nombreCentro,
  });

  @override
  State<RecolectadosDetallePage> createState() => _RecolectadosDetallePageState();
}

class _RecolectadosDetallePageState extends State<RecolectadosDetallePage> {
  late final DatabaseReference _refPaquetes;
  bool _loading = true;
  List<String> _ids = [];

  // Controller y loading del código (se conservan entre aperturas del sheet)
  late final TextEditingController _codeCtrl;
  late final ValueNotifier<bool> _loadingCode;

  static const String _webhook =
      'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_aK4f5Kjvn4Y7Mfs4jkLaWp';

  @override
  void initState() {
    super.initState();

    _codeCtrl = TextEditingController();
    _loadingCode = ValueNotifier<bool>(false);

    _refPaquetes = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RecolectadosConductor/${globalUserId ?? ''}/PaquetesRecolectados/${widget.idCentroRecoleccion}/Paquetes',
    );
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _loadingCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snap = await _refPaquetes.get();

    final List<String> tmp = [];
    if (snap.value is Map) {
      final map = (snap.value as Map);
      for (final e in map.entries) {
        final id = e.key.toString(); // ID del registro
        tmp.add(id);
      }
    } else if (snap.value is List) {
      final list = (snap.value as List);
      for (int i = 0; i < list.length; i++) {
        tmp.add(i.toString());
      }
    }

    if (!mounted) return;
    setState(() {
      _ids = tmp;
      _loading = false;
    });
  }

  // ==== Helpers de fecha ====
  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmtYYYYMMDD(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
  }

  String _fmtYYYYMMDDHHMMSS(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  // ==== Bottom sheet para código de autorización ====
  void _openAuthSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Autorización',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Para continuar, ingrese un código válido generado por un supervisor autorizado.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'Código',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (_) async {
                  if (_loadingCode.value) return;
                  _loadingCode.value = true;
                  await _validarCodigo(_codeCtrl.text, context); // 👈 contexto del Scaffold
                  if (mounted) _loadingCode.value = false;
                },
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<bool>(
                valueListenable: _loadingCode,
                builder: (_, isLoading, __) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              _loadingCode.value = true;
                              await _validarCodigo(_codeCtrl.text, context); // 👈 contexto del Scaffold
                              if (mounted) _loadingCode.value = false;
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF2B59F2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isLoading ? 'Validando…' : 'Validar',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _validarCodigo(String rawCode, BuildContext scaffoldCtx) async {
    final code = rawCode.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
        const SnackBar(content: Text('Ingresa un código.')),
      );
      return;
    }

    try {
      // 1) Verificar existencia del código
      final DatabaseReference refCode = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/CodigosAutorizacionDev/$code',
      );

      print('[VALIDAR] Consultando código: $code');
      final snap = await refCode.get();

      if (!snap.exists) {
        ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
          const SnackBar(content: Text('Código inválido o ya utilizado.')),
        );
        return;
      }

      // 2) Eliminar el código (marcar como usado)
      print('[VALIDAR] Código existe. Eliminando...');
      await refCode.remove();

      // 3) Enviar al webhook
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final payload = {
        'NombreDriver': globalNombre ?? '',
        'Timestamp': nowMs,
        'YYYYMMDD': _fmtYYYYMMDD(nowMs),
        'YYYYMMDDHHMMSS': _fmtYYYYMMDDHHMMSS(nowMs),
        'idCentro': widget.idCentroRecoleccion,
        'idDriver': globalUserId ?? '',
      };

      print('[VALIDAR] Enviando webhook: $payload');
      final resp = await http.post(
        Uri.parse(_webhook),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (!mounted) return;

        // Limpiar el input SOLO si todo salió bien
        _codeCtrl.clear();

        // Cerrar el bottom sheet (si sigue abierto)
        Navigator.of(scaffoldCtx).maybePop();

        await showDialog(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('Aviso'),
            content: Text(
              'Confirmar en 5 minutos que los paquetes hayan sido asignados en su totalidad.',
            ),
          ),
        );

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PaquetesPage()),
          (_) => false,
        );
      } else {
        print('[VALIDAR][WEBHOOK][ERROR] ${resp.statusCode} -> ${resp.body}');
        ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
          SnackBar(
            content: Text('Error webhook (${resp.statusCode}). ${resp.body}'),
          ),
        );
      }
    } catch (e) {
      print('[VALIDAR][EXCEPTION] $e');
      ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
                        Align(
                          alignment: Alignment.center,
                          child: Text(
                            'Centro de recolección\n(${widget.nombreCentro})',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
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
                                '${_ids.length}',
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
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                      itemCount: _ids.length,
                      itemBuilder: (_, i) {
                        final id = _ids[i];
                        return Card(
                          elevation: 1.5,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFEFF3FF),
                              child: Icon(
                                Icons.inventory_2_outlined,
                                color: Color(0xFF1955CC),
                              ),
                            ),
                            title: Text(
                              'Orden\n#$id',
                              style: const TextStyle(height: 1.2),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // Botón inferior "Autorización"
      bottomSheet: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          color: const Color(0xFF2B59F2),
          child: ElevatedButton(
            onPressed: _ids.isEmpty ? null : _openAuthSheet,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor:
                  _ids.isEmpty ? Colors.black26 : const Color(0xFF2B59F2),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Autorización',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
