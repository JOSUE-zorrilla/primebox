import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'login_page.dart';

// donde esté declarada globalUserId



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
  String? _idEmpresa;
  String? _urlImagen1;
  String? _urlImagen2;
  String? _urlImagen3;



  final List<String> _opciones = [
    'Titular',
    'Familiar',
    'Amigo',
    'Vecino',
    'Vigilante',
    'Otro',
  ];

  final List<File?> _imagenes = [null, null, null];
  List<String> _guiasMulti = []; // Guías escaneadas desde MultiGuiasPage

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
     _obtenerIdEmpresa();
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
  final ref = Uri.decodeFull(widget.id); // asegurarte que el id no esté codificado
 final snapshot = await FirebaseDatabase.instance
    .ref('projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$ref')
    .get();


  if (snapshot.exists) {
    final idEmpresa = snapshot.child('idEmpresa').value?.toString();
    setState(() {
      _idEmpresa = idEmpresa ?? 'No existe el código de empresa';
    });
  } else {
    setState(() {
      _idEmpresa = 'No existe el código de empresa';
    });
  }
}


  Future<void> _obtenerDireccionDesdeCoordenadas(double lat, double lng) async {
    final apiKey = 'AIzaSyDPvwJ5FfLTSE8iL4E4VWmkVmj6n4CvXok';
    final url = 'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$apiKey';

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
                  File imageFile = File(picked.path);
                  await _subirImagenAFirebase(imageFile, index);
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
                  File imageFile = File(picked.path);
                  await _subirImagenAFirebase(imageFile, index);
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _subirImagenAFirebase(File image, int index) async {
  try {
    final fileName = path.basename(image.path);
    final ref = FirebaseStorage.instance
        .ref()
        .child('imagenesaplicacion')
        .child('${DateTime.now().millisecondsSinceEpoch}_$fileName');

    final uploadTask = await ref.putFile(image);
    final url = await ref.getDownloadURL();

    setState(() {
      _imagenes[index] = image;
      if (index == 0) {
        _urlImagen1 = url;
      } else if (index == 1) {
        _urlImagen2 = url;
      } else if (index == 2) {
        _urlImagen3 = url;
      }
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



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Paquete'),
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MultiGuiasPage()),
              );
              if (resultado != null && resultado is List<String>) {
                setState(() {
                  _guiasMulti = resultado;
                });
              }
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
            if (_direccionActual != null) ...[
              const SizedBox(height: 12),
              Text('📍 Dirección actual: $_direccionActual'),
            ],
            if (_idEmpresa != null) ...[
          const SizedBox(height: 8),
          Text('🏢 Empresa: $_idEmpresa'),
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
            if (_guiasMulti.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('📋 Guías asociadas:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Column(
                children: _guiasMulti
                    .map((id) => ListTile(
                          leading: const Icon(Icons.qr_code),
                          title: Text(id),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
         ElevatedButton(
  onPressed: () async {
    final timestamp = DateTime.now();
    final yyyyMMdd = "${timestamp.year.toString().padLeft(4, '0')}"
        "${timestamp.month.toString().padLeft(2, '0')}"
        "${timestamp.day.toString().padLeft(2, '0')}";
    final yyyyMMddHHmmss = "${timestamp.year.toString().padLeft(4, '0')}"
        "${timestamp.month.toString().padLeft(2, '0')}"
        "${timestamp.day.toString().padLeft(2, '0')}"
        "${timestamp.hour.toString().padLeft(2, '0')}"
        "${timestamp.minute.toString().padLeft(2, '0')}"
        "${timestamp.second.toString().padLeft(2, '0')}";

    final recibe = _quienRecibeController.text.trim();
    final parentesco = _opcionSeleccionada;
    final nota = _notaController.text.trim();
    final alMenosUnaFoto = _urlImagen1 != null || _urlImagen2 != null || _urlImagen3 != null;
    final estadoFoto = alMenosUnaFoto ? "el usuario dejó tomarse la foto" : "el usuario no se dejó tomar la foto";

    final textoNota = "Recibe: $parentesco con nombre $recibe, $estadoFoto"
        "${nota.isNotEmpty ? ', $nota' : ''}";

// Asigna NombreEmpresa dinámicamente según idEmpresa
String nombreEmpresa;
if (_idEmpresa == "001000000000000001") {
  nombreEmpresa = "Primebox";
} else if (_idEmpresa == "j9Zgq4PzAYiFzJfPMrrccY") {
  nombreEmpresa = "Liverpol";
} else {
  nombreEmpresa = "Primebox";
}

final body = {
  "Direccion": _direccionActual ?? "",
  "FechaEstatus": timestamp.millisecondsSinceEpoch,
  "Foto1": _urlImagen1 ?? "",
  "Foto2": _urlImagen2 ?? "",
  "Foto3": _urlImagen3 ?? "",
  "Latitude": _posicionActual?.latitude.toString() ?? "",
  "Longitude": _posicionActual?.longitude.toString() ?? "",
  "NombreDriver": globalNombre ?? "SinNombre", // ← se asigna el nombre del conductor
  "NombreEmpresa": nombreEmpresa,
  "NombrePaquete": widget.id,
  "Nota": textoNota,
  "Parentesco": _opcionSeleccionada,
  "Recibe": _quienRecibeController.text.trim(),
  "YYYYMMDD": yyyyMMdd,
  "YYYYMMDDHHmmss": yyyyMMddHHmmss,
  "idCiudad": globalIdCiudad ?? "SinCiudad", // ← se asigna el ID de ciudad
  "idDriver": globalUserId ?? "",
  "idEmpresa": _idEmpresa ?? "",
  "idMovimiento": DateTime.now().millisecondsSinceEpoch.toString(),
  "idPaquete": widget.id,
  "Data": _guiasMulti,
};



    try {
      final response = await http.post(
  Uri.parse("https://editor.apphive.io/hook/ccp_5LWiKvLL1QnGygESVmGXFV"),
  headers: {
    HttpHeaders.contentTypeHeader: 'application/json',
  },
  body: jsonEncode(body),
);

print('STATUS: ${response.statusCode}');
print('BODY: ${response.body}');


      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Información enviada exitosamente')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: ${response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de red: $e')),
      );
    }

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
