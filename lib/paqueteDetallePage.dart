import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'multi_guias_page.dart'; 


class PaqueteDetallePage extends StatefulWidget {
  final String id;
  final String telefono;
  final String destinatario;
  final String tnReference;

  const PaqueteDetallePage({
    super.key,
    required this.id,
    required this.telefono,
    required this.destinatario,
    required this.tnReference,
  });

  @override
  State<PaqueteDetallePage> createState() => _PaqueteDetallePageState();
}

class _PaqueteDetallePageState extends State<PaqueteDetallePage> {
  final TextEditingController _quienRecibeController = TextEditingController();
  String _opcionSeleccionada = 'Titular';

  final List<String> _opciones = [
    'Titular',
    'Familiar',
    'Amigo',
    'Vecino',
    'Vigilante',
    'Otro',
  ];

  void _llamar() async {
    final uri = Uri.parse('tel:${widget.telefono}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _enviarWhatsApp() async {
    final uri = Uri.parse('https://wa.me/${widget.telefono}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Paquete'),
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('📞 Teléfono: ${widget.telefono}'),
                ),
                IconButton(
                  icon: const Icon(Icons.phone, color: Colors.green),
                  onPressed: _llamar,
                ),
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.green),
                  onPressed: _enviarWhatsApp,
                ),

              ],
            ),
            const SizedBox(height: 12),
            Text('👤 Titular: ${widget.destinatario}'),
            Text('🔢 TnReference: ${widget.tnReference}'),
            const SizedBox(height: 20),
            const Text('¿Quién recibe el paquete?',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _quienRecibeController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Nombre de quien recibe',
              ),
            ),
            const SizedBox(height: 20),
            const Text('Relación con el destinatario:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _opcionSeleccionada,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _opciones
                  .map((opcion) => DropdownMenuItem(
                        value: opcion,
                        child: Text(opcion),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _opcionSeleccionada = value!;
                });
              },
            ),
            const SizedBox(height: 30),
ElevatedButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MultiGuiasPage()),
    );
  },
  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
  child: const Text('MultiGuias'),
),

          ],
        ),
      ),
    );
  }
}
