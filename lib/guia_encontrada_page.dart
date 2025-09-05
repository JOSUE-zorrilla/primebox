import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// NUEVOS IMPORTS (si ya los añadiste, déjalos)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'guia_data.dart';
import 'paqueteDetallePage.dart';
import 'entrega_fallida_page.dart';

class GuiaEncontradaPage extends StatelessWidget {
  final GuiaData data;
  const GuiaEncontradaPage({super.key, required this.data});

  // ===== Helpers compartidos =====
  String _fmt(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);

  Future<void> _enviarWebhookRP({
    required String paqueteId,
    required String tnReference,
  }) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final estimada = DateTime.fromMillisecondsSinceEpoch(nowMs + 28800000); // +8h
    final url = Uri.parse(
        'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_woPgim5JFu1wFjHR21cHnK');

    final body = <String, String>{
      'Estatus': 'RP',
      'FechaEstimada': _fmt(estimada),
      'FechaPush': _fmt(now),
      'idGuiaLP': tnReference,
      'idGuiaPM': paqueteId,
    };

    await http.post(url, body: body);
  }

  Future<void> _limpiarNotificarRp({
    required String userId,
    required String paqueteId,
  }) async {
    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$userId/Paquetes/$paqueteId/NotificarRp',
    );
    await ref.set(''); // dejarlo vacío (no eliminar)
  }

  Future<bool> _estaConectado() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/${user.uid}/EstadoConexion',
    );
    final snap = await ref.get();
    final estado = snap.value?.toString() ?? 'Desconectado';
    return estado == 'Conectado';
  }

  

  Future<bool> _requerirConexion(BuildContext context) async {
    final ok = await _estaConectado();
    if (ok) return true;

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No estás conectado'),
          content: const Text('Debes conectarte para gestionar paquetes.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
    return false;
  }

  void _mostrarAlertaDevolucion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Paquete con múltiples intentos'),
        content: Text('Este paquete debe ser devuelto al proveedor.'),
      ),
    );
  }

  

  // ===== WhatsApp =====
  void _abrirWhatsapp(BuildContext context, {String? texto}) async {
    final tel = data.telefono.replaceAll(RegExp(r'[^0-9+]'), '');
    if (tel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay teléfono válido')),
      );
      return;
    }
    final msg = Uri.encodeComponent(texto ?? '');
    final uri = Uri.parse('https://wa.me/$tel${msg.isEmpty ? '' : '?text=$msg'}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardStyle = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== CABECERA CUSTOM =====
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F63D3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Guía encontrada',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF1955CC),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '(${data.id})',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 36),
              ],
            ),
            const SizedBox(height: 16),

            _campo('Nombre del cliente:', data.nombreDestinatario),
            _campo('Domicilio:', data.direccionEntrega),
            _campo('Teléfono:', data.telefono),
            _campo('Referencia:', data.tnReference),

            const SizedBox(height: 16),

            // Tarjeta 1
            Container(
              decoration: cardStyle,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Su paquete de Liverpool es el próximo a entregarse...',
                      maxLines: 2,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Enviar WhatsApp',
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366)),
                    onPressed: () => _abrirWhatsapp(
                      context,
                      texto: 'Su paquete de Liverpool es el próximo a entregarse...',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Tarjeta 2
            Container(
              decoration: cardStyle,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Estoy afuera de su domicilio para entregar su paquete de Liverpool...',
                      maxLines: 2,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Enviar WhatsApp',
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366)),
                    onPressed: () => _abrirWhatsapp(
                      context,
                      texto: 'Estoy afuera de su domicilio para entregar su paquete de Liverpool...',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ===== Entrega exitosa (misma lógica que onEntregar) =====
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F63D3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (!await _requerirConexion(context)) return;

                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sesión no válida. Inicia sesión nuevamente.')),
                      );
                    }
                    return;
                  }

                  final paqueteRef = FirebaseDatabase.instance.ref(
                    'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/${data.id}',
                  );

                  String tnReference = data.tnReference;
                  String telefono = data.telefono;

                  try {
                    final snap = await paqueteRef.get();
                    final notificarRp = snap.child('NotificarRp').value?.toString() ?? '';

                    if (notificarRp.toLowerCase() == 'si') {
                      tnReference = snap.child('TnReference').value?.toString() ?? tnReference;
                      await _enviarWebhookRP(paqueteId: data.id, tnReference: tnReference);
                      await _limpiarNotificarRp(userId: user.uid, paqueteId: data.id);
                    }

                    telefono = snap.child('Telefono').value?.toString() ?? telefono;
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al preparar entrega: $e')),
                      );
                    }
                  }

                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaqueteDetallePage(
                        id: data.id,
                        telefono: telefono,
                        destinatario: data.nombreDestinatario,
                        tnReference: tnReference,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Entrega exitosa',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ===== Entrega fallida (misma lógica que onRechazar) =====
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (!await _requerirConexion(context)) return;

                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;

                  final paqueteId = data.id;
                  final paqueteRef = FirebaseDatabase.instance.ref(
                    'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/$paqueteId',
                  );

                  try {
                    final snapshot = await paqueteRef.get();
                    final tnReference =
                        snapshot.child('TnReference').value?.toString() ?? data.tnReference;
                    final telefono =
                        snapshot.child('Telefono').value?.toString() ?? data.telefono;

                    // En onRechazar SIEMPRE enviamos RP y luego limpiamos NotificarRp
                    try {
                      await _enviarWebhookRP(
                        paqueteId: paqueteId,
                        tnReference: tnReference,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error al enviar webhook de rechazo: $e')),
                        );
                      }
                    } finally {
                      await _limpiarNotificarRp(
                        userId: user.uid,
                        paqueteId: paqueteId,
                      );
                    }

                    // Revisar intentos
                    final intentosRaw = snapshot.child('Intentos').value;
                    final int intentos = intentosRaw is int
                        ? intentosRaw
                        : int.tryParse(intentosRaw?.toString() ?? '') ?? 0;

                    if (intentos >= 3) {
                      _mostrarAlertaDevolucion(context);
                      return;
                    }

                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EntregaFallidaPage(
                          telefono: telefono,
                          tnReference: tnReference,
                          destinatario: data.nombreDestinatario,
                        ),
                      ),
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al preparar rechazo: $e')),
                      );
                    }
                  }
                },
                child: const Text(
                  'Entrega fallida',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(String titulo, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(valor.isEmpty ? '-' : valor),
          ],
        ),
      );
}
