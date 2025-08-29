import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'guia_data.dart';
import 'paqueteDetallePage.dart';
import 'entrega_fallida_page.dart';

class GuiaEncontradaPage extends StatelessWidget {
  final GuiaData data;
  const GuiaEncontradaPage({super.key, required this.data});

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
      // Quitamos AppBar para construir la cabecera custom como en tu diseño
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== CABECERA CUSTOM (como en la imagen) =====
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Botón volver: cuadrado azul con esquinas redondeadas
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
                // Título centrado relativo
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
                // Espaciador para balancear la fila (mismo ancho que el botón)
                const SizedBox(width: 36),
              ],
            ),
            const SizedBox(height: 16),
            // ===== FIN CABECERA =====

            _campo('Nombre del cliente:', data.nombreDestinatario),
            _campo('Domicilio:', data.direccionEntrega),
            _campo('Teléfono:', data.telefono),
            _campo('Referencia:', data.tnReference),

            const SizedBox(height: 16),

            // Tarjeta 1: solo texto + botón WhatsApp
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

            // Tarjeta 2: solo texto + botón WhatsApp
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

            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F63D3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaqueteDetallePage(
                        id: data.id,
                        telefono: data.telefono,
                        destinatario: data.nombreDestinatario,
                        tnReference: data.tnReference,
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
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EntregaFallidaPage(
                        telefono: data.telefono,
                        tnReference: data.tnReference,
                        destinatario: data.nombreDestinatario,
                      ),
                    ),
                  );
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
