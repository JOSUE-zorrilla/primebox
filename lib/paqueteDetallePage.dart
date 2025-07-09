import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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
  final TextEditingController _notaController = TextEditingController();
  String _opcionSeleccionada = 'Titular';
  String? _direccionActual;
  Position? _posicionActual;

  final List<String> _opciones = [
    'Titular',
    'Familiar',
    'Amigo',
    'Vecino',
    'Vigilante',
    'Otro',
  ];

  final List<File?> _imagenes = [null, null, null];

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
  }

  Future<void> _obtenerUbicacion() async {
    final status = await Permission.location.request();

    if (status.isGranted) {
      bool servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor activa el GPS del dispositivo.')),
        );
        return;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        setState(() {
          _posicionActual = position;
        });

        await _obtenerDireccionDesdeCoordenadas(position.latitude, position.longitude);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener ubicación: $e')),
        );
      }
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Permiso de ubicación denegado permanentemente. Por favor habilítalo en ajustes.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación denegado')),
      );
    }
  }

  Future<void> _obtenerDireccionDesdeCoordenadas(double lat, double lng) async {
    final apiKey = 'AIzaSyDPvwJ5FfLTSE8iL4E4VWmkVmj6n4CvXok';
    final url =
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['results'] != null && data['results'].isNotEmpty) {
        final direccion = data['results'][0]['formatted_address'];
        setState(() {
          _direccionActual = direccion;
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener dirección')),
      );
    }
  }

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
                final status = await Permission.photos.request();
                if (status.isGranted) {
                  final picked = await picker.pickImage(source: ImageSource.gallery);
                  if (picked != null) {
                    setState(() {
                      _imagenes[index] = File(picked.path);
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
                      _imagenes[index] = File(picked.path);
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
        title: const Text('Detalle del Paquete'),
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MultiGuiasPage()),
              );
            },
            child: const Text(
              'MultiGuía',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
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
            if (_direccionActual != null) ...[
              const SizedBox(height: 12),
              Text('📍 Dirección actual: $_direccionActual'),
            ],
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
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Cerrar sin firma',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
