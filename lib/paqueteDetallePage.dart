import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data'; // NUEVO: bytes para preview y subida
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:intl/intl.dart';
import 'multi_guias_page.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart'; // NUEVO

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
  // Marca
  static const Color brand = Color(0xFF2F63D3);

  // Controllers
  final TextEditingController _quienRecibeController = TextEditingController();
  final TextEditingController _notaController = TextEditingController();

  // Estado
  String _opcionSeleccionada = 'Titular';
  Position? _posicionActual;
  String? _idEmpresa;

  String? _urlImagen1;
  String? _urlImagen2;
  String? _urlImagen3;
  String? _urlImagen4; // NUEVO: INE

  // Ahora 4 posiciones (0..2: evidencias normales, 3: INE opcional)
  final List<File?> _imagenes = [null, null, null, null];

  // NUEVO: previews comprimidos (lo que realmente subimos) – ahora 4
  final List<Uint8List?> _previewsComprimidos = [null, null, null, null];

  // NUEVO: switch para habilitar INE
  bool _ineHabilitado = false;

  List<String> _guiasMulti = [];

  final List<String> _opciones = const [
    'Titular',
    'Familiar',
    'Amigo',
    'Vecino',
    'Vigilante',
    'Otro',
  ];

  // 🔒 Actualizado: ahora cuenta también la Evidencia4 (INE) si está presente
  bool get _tieneAlMenosUnaImagen =>
      _urlImagen1 != null ||
      _urlImagen2 != null ||
      _urlImagen3 != null ||
      _urlImagen4 != null;

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
    _obtenerIdEmpresa();
    final idBase = Uri.decodeFull(widget.id).trim();
    _guiasMulti = [idBase];
  }

  // ---------------- LÓGICA ----------------
  Future<void> _obtenerUbicacion() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        _snack('Por favor activa el GPS del dispositivo.');
        return;
      }
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        setState(() => _posicionActual = position);
      } catch (e) {
        _snack('Error al obtener ubicación: $e');
      }
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
      _snack('Permiso de ubicación denegado permanentemente. Habilítalo en ajustes.');
    } else {
      _snack('Permiso de ubicación denegado');
    }
  }

  Future<void> _obtenerIdEmpresa() async {
    final ref = Uri.decodeFull(widget.id);
    final snapshot = await FirebaseDatabase.instance
        .ref('projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$ref')
        .get();

    if (snapshot.exists) {
      final idEmpresa = snapshot.child('idEmpresa').value?.toString();
      setState(() => _idEmpresa = idEmpresa ?? 'No existe el código de empresa');
    } else {
      setState(() => _idEmpresa = 'No existe el código de empresa');
    }
  }

  void _llamar() async {
    final tel = _normalizePhone(widget.telefono, forWhatsApp: false);

    // Validación simple: al menos 7 dígitos
    final digits = tel.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      _snack('Número de teléfono inválido');
      return;
    }

    final uri = Uri(scheme: 'tel', path: tel); // soporta '+'
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('No se pudo abrir la app de llamadas.');
    }
  }

  Future<void> _enviarWhatsApp() async {
    final String mensaje = 'Hola...';

    // Quita separadores y el '+'; wa.me exige SOLO dígitos en formato internacional
    String tel = _normalizePhone(widget.telefono, forWhatsApp: true);

    // Valida que tenga de 7 a 15 dígitos
    if (!RegExp(r'^\d{7,15}$').hasMatch(tel)) {
      _snack('Número inválido. Debe incluir el código de país y solo dígitos. Recibido: "$tel"');
      return;
    }

    final uriWa = Uri.parse(
      'https://wa.me/$tel?text=${Uri.encodeComponent(mensaje)}',
    );

    final ok = await launchUrl(uriWa, mode: LaunchMode.externalApplication);
    if (!ok) _snack('No se pudo abrir WhatsApp.');
  }

  // ===== COMPRESIÓN =====

  /// Comprime una imagen a JPEG con lado largo máx. 1600px y calidad 75.
  /// Devuelve bytes listos para subir con putData.
  Future<Uint8List> _compressImage(File file) async {
    final originalBytes = await file.readAsBytes();
    final result = await FlutterImageCompress.compressWithList(
      originalBytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 75, // baja más si quieres menor peso (60–70)
      rotate: 0,
      keepExif: true,
      format: CompressFormat.jpeg,
    );
    return Uint8List.fromList(result);
  }

  Future<void> _seleccionarImagen(int index) async {
    final picker = ImagePicker();

    // Selector de origen
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Captura de evidencia',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Seleccionar de galería'),
              onTap: () async {
                Navigator.pop(context);
                final status = await Permission.photos.request(); // iOS
                if (status.isGranted) {
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 2000,
                    maxHeight: 2000,
                    imageQuality: 90,
                  );
                  if (picked != null) {
                    await _subirImagenAFirebase(File(picked.path), index);
                  }
                } else {
                  _snack('Permiso de galería denegado');
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
                  final picked = await picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1600,
                    maxHeight: 1600,
                    imageQuality: 85,
                  );
                  if (picked != null) {
                    await _subirImagenAFirebase(File(picked.path), index);
                  }
                } else {
                  _snack('Permiso de cámara denegado');
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---- Subida comprimida con UN solo SnackBar de 2s ----
  Future<void> _subirImagenAFirebase(File image, int index) async {
    final messenger = ScaffoldMessenger.of(context);

    // Un único mensaje de 2s apenas inicia la acción
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Cargando imagen...'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // 1) Comprimir a JPEG
      final Uint8List compressed = await _compressImage(image);

      // 2) Subir a Firebase Storage con putData (bytes) y metadata
      final fileName = path.basename(image.path).replaceAll(RegExp(r'\s+'), '_');
      final ref = FirebaseStorage.instance
          .ref()
          .child('imagenesaplicacion')
          .child('${DateTime.now().millisecondsSinceEpoch}_$fileName.jpg');

      await ref.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await ref.getDownloadURL();

      // 3) Actualizar estado: file local + preview comprimido + URL
      if (!mounted) return;
      setState(() {
        // Asegura que los arreglos tengan índice suficiente (0..3)
        if (index >= 0 && index < _imagenes.length) {
          _imagenes[index] = image;
        }
        if (index >= 0 && index < _previewsComprimidos.length) {
          _previewsComprimidos[index] = compressed;
        }

        if (index == 0) {
          _urlImagen1 = url;
        } else if (index == 1) {
          _urlImagen2 = url;
        } else if (index == 2) {
          _urlImagen3 = url;
        } else if (index == 3) {
          _urlImagen4 = url; // INE
        }
      });
    } catch (e) {
      // Silencioso como pediste (solo un snack al inicio).
      // debugPrint('Error al subir imagen: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Normaliza números de teléfono.
  /// - Quita espacios, guiones, paréntesis, puntos, etc.
  /// - Conserva un '+' solo si está al inicio.
  /// - Para WhatsApp devuelve SIN '+', como requiere wa.me.
  String _normalizePhone(String input, {bool forWhatsApp = false}) {
    if (input.isEmpty) return input;

    // Quitar separadores comunes
    var s = input.replaceAll(RegExp(r'[\s\-\(\)\.\_\/]'), '');

    // Mantener '+' solo al inicio (si existía)
    final hadPlus = s.startsWith('+');
    s = s.replaceAll('+', '');
    if (hadPlus) s = '+$s';

    // Para wa.me el número debe ir sin '+'
    if (forWhatsApp && s.startsWith('+')) {
      s = s.substring(1);
    }

    return s;
  }

  // -------------- ESTILOS / UI HELPERS --------------
  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: brand, width: 1.2),
        ),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      );

  Widget _chipButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color ?? brand,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoSlot(int index, {String? label}) {
    // label opcional para diferenciar el INE visualmente
    final child = Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      child: _previewsComprimidos[index] != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_previewsComprimidos[index]!, fit: BoxFit.cover),
            )
          : (_imagenes[index] != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_imagenes[index]!, fit: BoxFit.cover),
                )
              : const Icon(Icons.add_a_photo_outlined, size: 26, color: Colors.black45)),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _seleccionarImagen(index),
          child: child,
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ]
      ],
    );
  }

  // ---------- Painter para borde punteado ----------
  Widget _dashedBox({required Widget child}) {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: const Color(0xFFCBD5E1),
        strokeWidth: 1.2,
        dashWidth: 6.0,
        dashSpace: 4.0,
        radius: 12.0,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
  // -------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // FONDO BLANCO
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,             // fondo blanco en status bar
          statusBarIconBrightness: Brightness.dark, // íconos oscuros (Android)
          statusBarBrightness: Brightness.light,    // iOS: texto oscuro
        ),
        backgroundColor: Colors.white,              // APPBAR BLANCO
        foregroundColor: brand,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Entrega Exitosa',
          style: TextStyle(fontWeight: FontWeight.w700, color: brand),
        ),
        leadingWidth: 58,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: brand,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final idBase = Uri.decodeFull(widget.id).trim();

              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MultiGuiasPage(
                    initialGuias: {idBase, ..._guiasMulti}.toList(), // 👈 ya marcadas
                  ),
                ),
              );

              if (resultado != null && resultado is List<String>) {
                final idBase2 = Uri.decodeFull(widget.id).trim();
                setState(() {
                  _guiasMulti = {idBase2, ...resultado}.toList(); // aseguras id base y evitas duplicados
                });
              }
            },
            child: Text('MultiGuía', style: TextStyle(color: brand, fontWeight: FontWeight.w600)),
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // --- SECCIÓN PRINCIPAL (sin card, todo blanco) ---
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Teléfono + acciones
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Teléfono:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 2),
                            Text(widget.telefono, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      _chipButton(icon: Icons.phone, label: 'Llamar', onTap: _llamar, color: brand),
                      const SizedBox(width: 8),
                      _chipButton(
                        icon: FontAwesomeIcons.whatsapp,
                        label: '',
                        onTap: _enviarWhatsApp,
                        color: const Color(0xFF25D366),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Guía / Titular
                  const Text('No. Guía:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text(widget.tnReference, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),

                  const Text('Titular:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text(widget.destinatario, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),

                  if (_idEmpresa != null)
                    Text('Empresa: ${_idEmpresa!}', style: const TextStyle(fontSize: 12, color: Colors.black54)),

                  const SizedBox(height: 16),

                  _sectionTitle('¿Quién lo recibió?'),
                  DropdownButtonFormField<String>(
                    value: _opcionSeleccionada,
                    decoration: _input('Parentesco'),
                    items: _opciones
                        .map((opcion) => DropdownMenuItem(value: opcion, child: Text(opcion)))
                        .toList(),
                    onChanged: (v) => setState(() => _opcionSeleccionada = v!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _quienRecibeController,
                    decoration: _input('Nombre de quien recibe'),
                  ),

                  const SizedBox(height: 16),
                  _sectionTitle('Captura de Evidencia'),

                  // Caja punteada con 3 cuadritos (sin botones)
                  _dashedBox(
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        const Icon(Icons.cloud_upload_outlined, size: 42, color: Colors.black87),
                        const SizedBox(height: 6),
                        const Text(
                          'Selecciona o arrastra tus imágenes o video',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '(Png y Jpg máx 1gb)',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(3, (i) => _photoSlot(i)),
                        ),

                        // 🔒 Aviso visual cuando NO hay imágenes aún
                        if (!_tieneAlMenosUnaImagen) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Debes adjuntar al menos 1 imagen para poder guardar.',
                            style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 10),
                        // NUEVO: Switch para INE
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Adjuntar INE (opcional)',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          value: _ineHabilitado,
                          onChanged: (v) => setState(() => _ineHabilitado = v),
                        ),

                        // Si el switch está activo, mostramos un cuarto slot para INE
                        if (_ineHabilitado) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _photoSlot(3, label: 'INE'),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  _sectionTitle('Nota Extra'),
                  TextField(
                    controller: _notaController,
                    maxLines: 4,
                    decoration: _input('Escribe tus observaciones...'),
                  ),

                  if (_guiasMulti.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionTitle('Guías asociadas'),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE6E6E6)),
                      ),
                      child: Column(
                        children: _guiasMulti
                            .map((id) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.qr_code_2_outlined),
                                  title: Text(id),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 14),

              // ---- BOTÓN PRIMARIO (Guardar) ----
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  // 🔒 Deshabilitar si no hay al menos 1 imagen
                  onPressed: _tieneAlMenosUnaImagen
                      ? () async {
                          // 🔒 Doble chequeo por seguridad (evita condiciones de carrera)
                          if (!_tieneAlMenosUnaImagen) {
                            _snack('Debes adjuntar al menos 1 imagen para poder guardar.');
                            return;
                          }

                          // ---------- LÓGICA ORIGINAL + INE ----------
                          final timestamp = DateTime.now();
                          final yyyyMMdd = DateFormat('yyyy-MM-dd').format(timestamp);
                          final yyyyMMddHHmmss = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);

                          final recibe = _quienRecibeController.text.trim();
                          final parentesco = _opcionSeleccionada;
                          final nota = _notaController.text.trim();

                          final alMenosUnaFoto =
                              _urlImagen1 != null || _urlImagen2 != null || _urlImagen3 != null || _urlImagen4 != null;

                          final estadoFoto = alMenosUnaFoto
                              ? "el usuario dejó tomarse la foto"
                              : "el usuario no se dejó tomar la foto";

                          final tieneIne = (_urlImagen4 != null && _urlImagen4!.isNotEmpty);
                          final estadoIne = tieneIne ? "con INE" : "sin INE";

                          final textoNota =
                              "Recibe: $parentesco con nombre $recibe, $estadoFoto, $estadoIne${nota.isNotEmpty ? ', $nota' : ''}";

                          // Transforma la lista de guías en un objeto { guia: { idGuia: guia }, ... }
                          final String idRegistro = Uri.decodeFull(widget.id).trim();
                          final List<String> fuentes = _guiasMulti.isNotEmpty ? _guiasMulti : [idRegistro];

                          // Opcional: deduplicar por si se repite algo
                          final Set<String> unicas = fuentes.map((e) => e.trim()).toSet();

                          final Map<String, dynamic> dataPayload = {
                            for (final guia in unicas) guia: {'idGuia': guia}
                          };

                          final body = {
                            "Evidencia1": _urlImagen1 ?? "",
                            "Evidencia2": _urlImagen2 ?? "",
                            "Evidencia3": _urlImagen3 ?? "",
                            "Evidencia4": _urlImagen4 ?? "", // NUEVO: INE
                            "Latitude": _posicionActual?.latitude.toString() ?? "",
                            "Longitude": _posicionActual?.longitude.toString() ?? "",
                            "NombreDriver": globalNombre ?? "SinNombre",
                            "Nota": textoNota,
                            "TimeStamp": DateTime.now().millisecondsSinceEpoch,
                            "Parentesco": parentesco,
                            "NombreRecibe": recibe,
                            "YYYYMMDD": yyyyMMdd,
                            "YYYYMMDDHHMMSS": yyyyMMddHHmmss,
                            "idDriver": globalUserId ?? "",
                            "data": dataPayload,
                          };

                          try {
                            const webhookUrl = "https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_dyuvUsB3QWxNmTdHi7qMfT";

                            final response = await http.post(
                              Uri.parse(webhookUrl),
                              headers: {HttpHeaders.contentTypeHeader: 'application/json'},
                              body: jsonEncode(body),
                            );

                            if (!mounted) return;

                            if (response.statusCode == 200) {
                              _snack('Información enviada exitosamente');
                            } else {
                              _snack('Error al enviar: ${response.body}');
                            }
                          } catch (e) {
                            if (!mounted) return;
                            _snack('Error de red: $e');
                          }

                          if (mounted) Navigator.pop(context);
                          // ---------- FIN LÓGICA ----------
                        }
                      : null, // 👉 desactivado si no hay imagen
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    elevation: 0,
                    // 🔒 Visual: reduce opacidad cuando esté deshabilitado
                    disabledBackgroundColor: brand.withOpacity(0.35),
                    disabledForegroundColor: Colors.white70,
                  ),
                  child: const Text('Guardar'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Painter de borde punteado ----------------
class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double radius;

  const _DashedRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final double w = size.width;
    final double h = size.height;
    final double r = radius;

    void drawDashedLine(Offset start, Offset end) {
      final bool isHorizontal = start.dy == end.dy;
      final double length =
          isHorizontal ? (end.dx - start.dx).abs() : (end.dy - start.dy).abs();
      double drawn = 0.0;
      while (drawn < length) {
        final double next = ((drawn + dashWidth).clamp(0.0, length)).toDouble();
        final Offset p1 = isHorizontal
            ? Offset(start.dx + drawn, start.dy)
            : Offset(start.dx, start.dy + drawn);
        final Offset p2 = isHorizontal
            ? Offset(start.dx + next, start.dy)
            : Offset(start.dx, start.dy + next);
        canvas.drawLine(p1, p2, paint);
        drawn += dashWidth + dashSpace;
      }
    }

    // Lados rectos dejando radio en esquinas
    drawDashedLine(Offset(r, 0), Offset(w - r, 0)); // top
    drawDashedLine(Offset(w, r), Offset(w, h - r)); // right
    drawDashedLine(Offset(w - r, h), Offset(r, h)); // bottom
    drawDashedLine(Offset(0, h - r), Offset(0, r)); // left

    void drawDashedArc(Rect rect, double startAngle, double sweep) {
      final path = Path()..addArc(rect, startAngle, sweep);
      for (final metric in path.computeMetrics()) {
        double distance = 0.0;
        while (distance < metric.length) {
          final double next =
              ((distance + dashWidth).clamp(0.0, metric.length)).toDouble();
          final extract = metric.extractPath(distance, next);
          canvas.drawPath(extract, paint);
          distance += dashWidth + dashSpace;
        }
      }
    }

    drawDashedArc(
        Rect.fromCircle(center: Offset(r, r), radius: r), math.pi, math.pi / 2); // top-left
    drawDashedArc(Rect.fromCircle(center: Offset(w - r, r), radius: r),
        -math.pi / 2, math.pi / 2); // top-right
    drawDashedArc(Rect.fromCircle(center: Offset(w - r, h - r), radius: r), 0,
        math.pi / 2); // bottom-right
    drawDashedArc(Rect.fromCircle(center: Offset(r, h - r), radius: r),
        math.pi / 2, math.pi / 2); // bottom-left
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashWidth != dashWidth ||
      old.dashSpace != dashSpace ||
      old.radius != radius;
}
