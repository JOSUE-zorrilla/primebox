import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'login_page.dart'; // ya lo estás haciendo 👍
import 'package:firebase_database/firebase_database.dart';

import 'fallidas_multientrega_page.dart';

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
  String? _urlImagen;
  List<String> _guiasFallidas = [];
  String? _idEmpresa;

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

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion(); // Solo permisos y verificación de GPS; sin geocoding
    _obtenerIdEmpresa();
  }

  Future<void> _obtenerUbicacion() async {
    final status = await Permission.location.request();

    if (status.isGranted) {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activa el GPS del dispositivo.')),
        );
        return;
      }

      // Opcional: “calentar” la ubicación (no guardamos dirección)
      try {
        await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener ubicación: $e')),
        );
      }
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permiso de ubicación denegado permanentemente. Habilítalo en ajustes.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación denegado')),
      );
    }
  }

  Future<void> _obtenerIdEmpresa() async {
    final id = Uri.decodeFull(widget.tnReference);
    final snapshot = await FirebaseDatabase.instance
        .ref('projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$id')
        .get();

    if (snapshot.exists) {
      final empresa = snapshot.child('idEmpresa').value?.toString();
      setState(() {
        _idEmpresa = empresa ?? 'NoRegistrado';
      });
    } else {
      setState(() {
        _idEmpresa = 'NoRegistrado';
      });
    }
  }

  Future<void> _subirImagenAFirebase(File image) async {
    try {
      final fileName = path.basename(image.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('imagenesfallidas')
          .child('${DateTime.now().millisecondsSinceEpoch}_$fileName');

      await ref.putFile(image);
      final url = await ref.getDownloadURL();

      setState(() {
        _urlImagen = url;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagen subida correctamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir imagen: $e')),
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
                final status = await Permission.photos.request();
                if (status.isGranted) {
                  final picked = await picker.pickImage(source: ImageSource.gallery);
                  if (picked != null) {
                    final imageFile = File(picked.path);
                    setState(() {
                      _imagenes[0] = imageFile;
                    });
                    await _subirImagenAFirebase(imageFile);
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
                    final imageFile = File(picked.path);
                    setState(() {
                      _imagenes[0] = imageFile;
                    });
                    await _subirImagenAFirebase(imageFile);
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
        actions: [
          TextButton(
            onPressed: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FallidasMultiEntregaPage()),
              );

              if (resultado != null && resultado is List<String>) {
                setState(() {
                  _guiasFallidas = resultado;
                });
              }
            },
            child: const Text(
              'MultiEntrega',
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
            const Text('Motivo de entrega fallida:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _motivo,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _motivos
                  .map((mot) => DropdownMenuItem(value: mot, child: Text(mot)))
                  .toList(),
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
            if (_guiasFallidas.isNotEmpty) ...[
              const SizedBox(height: 30),
              const Text('📋 Guías fallidas registradas:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Column(
                children: _guiasFallidas
                    .map((id) => ListTile(
                          leading: const Icon(Icons.qr_code),
                          title: Text(id),
                        ))
                    .toList(),
              ),
            ],
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
              onPressed: () async {
                final idPaquete = widget.tnReference;
                final DatabaseReference ref = FirebaseDatabase.instance.ref(
                  "projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$idPaquete",
                );

                try {
                  final snapshot = await ref.child('Fallos').get();
                  int intento = 1;

                  if (snapshot.exists) {
                    final valor = snapshot.value;
                    intento = int.tryParse(valor.toString()) != null
                        ? int.parse(valor.toString()) + 1
                        : 1;
                  }

                  final codigoFalla = 'FL$intento';
                  final fechaAhora = DateTime.now();
                  final yyyyMMddHHmmss =
                      '${fechaAhora.year.toString().padLeft(4, '0')}'
                      '${fechaAhora.month.toString().padLeft(2, '0')}'
                      '${fechaAhora.day.toString().padLeft(2, '0')}'
                      '${fechaAhora.hour.toString().padLeft(2, '0')}'
                      '${fechaAhora.minute.toString().padLeft(2, '0')}'
                      '${fechaAhora.second.toString().padLeft(2, '0')}';

                  // 🔸 UPDATE parcial en Firebase
                  await ref.update({
                    'Estatus': codigoFalla,
                    'Fallos': intento,
                    'FechaEstatus': snapshot.exists ? ServerValue.timestamp : yyyyMMddHHmmss,
                  });

                  // 🔸 Ubicación (lat/lng) sin geocoding
                  final Position posicion = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.high,
                  );

                  final now = DateTime.now();
                  final yyyyMMdd =
                      '${now.year.toString().padLeft(4, '0')}-'
                      '${now.month.toString().padLeft(2, '0')}-'
                      '${now.day.toString().padLeft(2, '0')}';

                  final Map<String, dynamic> body = {
                    "CodigoFalla": codigoFalla,
                    "Direccion": "", // Se elimina geocoding, va vacío
                    "FotoEvidencia": _urlImagen ?? "",
                    "Intentos": intento,
                    "Latitude": posicion.latitude.toString(),
                    "Longitude": posicion.longitude.toString(),
                    "MotivoFallo": _motivo,
                    "NombreDriver": globalNombre ?? "SinNombre",
                    "NombrePaquete": idPaquete,
                    "tnReference": widget.tnReference,
                    "idPaquete": idPaquete,
                    "Timestamp": DateTime.now().millisecondsSinceEpoch,
                    "idConductor": globalUserId ?? "",
                    "idEmpresa": _idEmpresa ?? "",
                    "data": _guiasFallidas,
                    "YYYYMMDD": yyyyMMdd,
                    "YYYYMMDDHHmmss": int.parse(yyyyMMddHHmmss),
                  };

                  final response = await http.post(
                    Uri.parse('https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_bzSiG1tauvQ5us7gtyQKEd'),
                    headers: {HttpHeaders.contentTypeHeader: 'application/json'},
                    body: jsonEncode(body),
                  );

                  if (response.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Entrega fallida registrada correctamente')),
                    );
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al enviar webhook: ${response.body}')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ocurrió un error: $e')),
                  );
                }
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
