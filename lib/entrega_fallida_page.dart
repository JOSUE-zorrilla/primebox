import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class EntregaFallidaPage extends StatefulWidget {
  final String telefono;
  final String tnReference;
  final String destinatario;

  const EntregaFallidaPage({
    super.key,
    required this.telefono,
    required this.tnReference,
    required this.destinatario,
  });

  @override
  State<EntregaFallidaPage> createState() => _EntregaFallidaPageState();
}

class _EntregaFallidaPageState extends State<EntregaFallidaPage> {
  final TextEditingController _notaController = TextEditingController();
  final List<File?> _imagenes = [null];

  String _motivo = 'Titular ausente';

  final List<String> _motivos = [
    'Titular ausente',
    'Titular no localizado',
    'Domicilio incorrecto',
    'Paquete dañado',
    'Robo',
    'Extravío',
    'Otro',
  ];

  void _llamar() async {
    final uri = Uri(scheme: 'tel', path: widget.telefono);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _enviarWhatsApp() async {
    final mensaje = 'Hola, te saludamos de Primebox Driver';
    final telefono = widget.telefono.replaceAll('+', '').replaceAll(' ', '');
    final uri = Uri.parse('https://wa.me/$telefono?text=${Uri.encodeComponent(mensaje)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _seleccionarImagen() async {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Seleccionar de galería'),
              onTap: () async {
                Navigator.pop(context);
                final status = await Permission.storage.request();
                if (status.isGranted) {
                  final picked = await picker.pickImage(source: ImageSource.gallery);
                  if (picked != null) {
                    setState(() {
                      _imagenes[0] = File(picked.path);
                    });
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tomar foto'),
              onTap: () async {
                Navigator.pop(context);
                final status = await Permission.camera.request();
                if (status.isGranted) {
                  final picked = await picker.pickImage(source: ImageSource.camera);
                  if (picked != null) {
                    setState(() {
                      _imagenes[0] = File(picked.path);
                    });
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrega Fallida'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(child: Text('📞 Teléfono: ${widget.telefono}')),
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

            const Text('Motivo de entrega fallida:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _motivo,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _motivos.map((mot) => DropdownMenuItem(value: mot, child: Text(mot))).toList(),
              onChanged: (value) {
                setState(() {
                  _motivo = value!;
                });
              },
            ),

            const SizedBox(height: 20),
            const Text('📷 Captura de evidencia fallida:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _seleccionarImagen,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  color: Colors.grey[200],
                ),
                child: _imagenes[0] != null
                    ? Image.file(_imagenes[0]!, fit: BoxFit.cover)
                    : const Icon(Icons.add_a_photo, size: 40),
              ),
            ),

            const SizedBox(height: 20),
            const Text('📝 Nota extra:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _notaController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Observaciones adicionales...',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // Guardar lógica aquí
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
