import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'multi_guias_page.dart';
import 'package:permission_handler/permission_handler.dart';


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
  final TextEditingController _notaController = TextEditingController();
  String _opcionSeleccionada = 'Titular';

  final List<String> _opciones = [
    'Titular',
    'Familiar',
    'Amigo',
    'Vecino',
    'Vigilante',
    'Otro',
  ];

  final List<File?> _imagenes = [null, null, null];

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
 Future<void> _seleccionarImagen(int index) async {
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
                    _imagenes[index] = File(picked.path);
                  });
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Permiso denegado para acceder a la galería.')),
                );
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
                    _imagenes[index] = File(picked.path);
                  });
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Permiso denegado para acceder a la cámara.')),
                );
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
            const SizedBox(height: 20),
            const Text('📷 Fotografías:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(3, (index) {
                return GestureDetector(
                  onTap: () => _seleccionarImagen(index),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      color: Colors.grey[200],
                    ),
                    child: _imagenes[index] != null
                        ? Image.file(_imagenes[index]!, fit: BoxFit.cover)
                        : const Icon(Icons.add_a_photo, size: 30),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            const Text('📝 Agregar alguna nota (opcional):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _notaController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Escribe tus observaciones...',
                border: OutlineInputBorder(),
              ),
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
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Aquí puedes agregar lógica de guardado o confirmación
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Cerrar sin firma'),
            ),
          ],
        ),
      ),
    );
  }
}
