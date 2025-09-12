import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data'; // NUEVO: para Uint8List (preview y subida)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'login_page.dart';
import 'package:firebase_database/firebase_database.dart';
import 'fallidas_multientrega_page.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart'; // NUEVO

class EntregaFallidaPage extends StatefulWidget {
  final String telefono;
  final String tnReference;   // Referencia "humana" (ruta Historal)
  final String destinatario;
  final String paqueteId;     // idPB (clave real en RTDB) recibido desde la primera pantalla

  const EntregaFallidaPage({
    super.key,
    required this.telefono,
    required this.tnReference,
    required this.destinatario,
    required this.paqueteId,
  });

  @override
  State<EntregaFallidaPage> createState() => _EntregaFallidaPageState();
}

class _EntregaFallidaPageState extends State<EntregaFallidaPage> {
  static const Color brand = Color(0xFFE04B41);

  final TextEditingController _notaController = TextEditingController();
  final List<File?> _imagenes = [null];
  String? _urlImagen;

  // NUEVO: bytes JPEG comprimidos para mostrar preview real (lo que subimos)
  Uint8List? _previewJpeg;

  // Multi-entrega (idPB adicionales que vienen de MultiEntrega)
  List<String> _guiasFallidas = [];

  // Empresa y ubicación
  String? _idEmpresa;
  Position? _posicionActual;

  // Motivos
  String _motivo = 'Titular ausente';
  final List<String> _motivos = const [
    'Titular ausente',
    'Titular no localizado',
    'Domicilio incorrecto',
    'Paquete dañado',
    'Robo',
    'Extravío',
    'Otro',
  ];

  // id del paquete actual (idPB). Si no viene en paqueteId, lo resolvemos desde Historal/{tnRef}/idPB
  String? _idPBActual;

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
    _obtenerIdEmpresa();

    // Resolver _idPBActual
    () async {
      final fromWidget = widget.paqueteId.trim();
      if (fromWidget.isNotEmpty) {
        setState(() => _idPBActual = fromWidget);
      } else {
        final resolved = await _fetchIdPBFromRef(widget.tnReference, fallbackToTnRef: false);
        setState(() => _idPBActual = resolved);
      }
    }();
  }

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(message.isEmpty ? '(vacío)' : message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---------------------- LÓGICA ----------------------
  Future<void> _obtenerUbicacion() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        _snack('Activa el GPS del dispositivo.');
        return;
      }
      try {
        _posicionActual =
            await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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
    final id = Uri.decodeFull(widget.tnReference);
    final snapshot = await FirebaseDatabase.instance
        .ref('projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$id')
        .get();

    if (snapshot.exists) {
      final empresa = snapshot.child('idEmpresa').value?.toString();
      setState(() => _idEmpresa = empresa ?? 'NoRegistrado');
    } else {
      setState(() => _idEmpresa = 'NoRegistrado');
    }
  }

  // NUEVO: helper de compresión (JPEG, lado largo máx. 1600px, calidad 75)
  Future<Uint8List> _compressImage(File file) async {
    final originalBytes = await file.readAsBytes();
    final result = await FlutterImageCompress.compressWithList(
      originalBytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 75,           // 60–85 suele estar bien
      rotate: 0,
      keepExif: true,
      format: CompressFormat.jpeg,
    );
    return Uint8List.fromList(result);
  }

  // Subida con compresión y metadata correcta
  Future<void> _subirImagenAFirebase(File image) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Cargando imagen…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(days: 1),
      ),
    );
    try {
      // === COMPRESIÓN ===
      final Uint8List compressed = await _compressImage(image);

      // Nombre legible (y forzamos extensión .jpg)
      final fileName = path.basename(image.path).replaceAll(RegExp(r'\s+'), '_');
      final ref = FirebaseStorage.instance
          .ref()
          .child('imagenesfallidas')
          .child('${DateTime.now().millisecondsSinceEpoch}_$fileName.jpg');

      // Subimos bytes comprimidos con contentType correcto
      await ref.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await ref.getDownloadURL();

      setState(() {
        _imagenes[0] = image; // mantenemos referencia al File (por si la necesitas)
        _previewJpeg = compressed; // mostramos preview comprimido
        _urlImagen = url;
      });

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Imagen subida correctamente')),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Error al subir imagen: $e')),
      );
    }
  }

  void _llamar() async {
    final tel = _normalizePhone(widget.telefono, forWhatsApp: false);
    final digits = tel.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      _snack('Número de teléfono inválido');
      return;
    }
    final uri = Uri(scheme: 'tel', path: tel);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _snack('No se pudo iniciar la llamada');
    }
  }

  void _enviarWhatsApp() async {
    final String mensaje = 'Hola...';
    final String telefonoWa = _normalizePhone(widget.telefono, forWhatsApp: true);

    try {
      // 1) Validación de número (solo dígitos, 7–15)
      if (!RegExp(r'^\d{7,15}$').hasMatch(telefonoWa)) {
        throw 'Número inválido. Debe tener solo dígitos (7–15). Recibido: "$telefonoWa".';
      }

      // 2) URIs
      final Uri uriWaMe = Uri.parse(
        'https://wa.me/$telefonoWa?text=${Uri.encodeComponent(mensaje)}',
      );
      final Uri uriNative = Uri.parse(
        'whatsapp://send?phone=$telefonoWa&text=${Uri.encodeComponent(mensaje)}',
      );

      // 3) WEB: solo podemos abrir wa.me
      if (kIsWeb) {
        final ok = await launchUrl(uriWaMe, mode: LaunchMode.externalApplication);
        if (!ok) {
          throw 'No se pudo abrir el enlace wa.me en el navegador.';
        }
        return;
      }

      // 4) NATIVO: intentar app primero
      bool intentadoNativo = false;
      try {
        final puedeNativo = await canLaunchUrl(uriNative);
        if (puedeNativo) {
          intentadoNativo = true;
          final ok = await launchUrl(uriNative, mode: LaunchMode.externalApplication);
          if (!ok) {
            throw 'La app de WhatsApp no respondió al intento de apertura.';
          }
          return; // Listo
        }
      } catch (e) {
        throw 'Error al invocar la app de WhatsApp: $e';
      }

      // 5) Fallback a wa.me
      final puedeWeb = await canLaunchUrl(uriWaMe);
      if (puedeWeb) {
        final ok = await launchUrl(uriWaMe, mode: LaunchMode.externalApplication);
        if (!ok) {
          throw 'No se pudo abrir el enlace wa.me en el navegador.';
        }
        return;
      }

      // 6) Explicación si nada funcionó
      String razon = 'No fue posible abrir WhatsApp ni el enlace web. ';
      if (!intentadoNativo) {
        razon += 'Posible causa: WhatsApp no está instalado o el sistema bloqueó la intención.';
      } else {
        razon += 'Posible causa: el sistema bloqueó la apertura o no hay navegador disponible.';
      }
      throw razon;
    } on FormatException catch (e) {
      _snack('Número/URI con formato inválido: $e');
    } catch (e) {
      _snack('No se pudo abrir WhatsApp: $e');
    }
  }

  Future<void> _tomarFotografia() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _snack('Permiso de cámara denegado');
      return;
    }
    final picker = ImagePicker();
    // TIP: puedes limitar desde aquí también, pero igual comprimimos después
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85, // ligera compresión inicial para ahorrar RAM
    );
    if (picked != null) {
      await _subirImagenAFirebase(File(picked.path));
    }
  }

  Future<void> _abrirGaleria() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      _snack('Permiso de galería denegado');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,   // un poco mayor para fotos ya existentes
      maxHeight: 2000,
      imageQuality: 90, // compresión leve inicial
    );
    if (picked != null) {
      await _subirImagenAFirebase(File(picked.path));
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _normalizePhone(String input, {bool forWhatsApp = false}) {
    if (input.isEmpty) return input;
    var s = input.replaceAll(RegExp(r'[\s\-\(\)\.\_]'), '');
    final hadPlus = s.startsWith('+');
    s = s.replaceAll('+', '');
    if (hadPlus) s = '+$s';
    if (forWhatsApp && s.startsWith('+')) {
      s = s.substring(1);
    }
    return s;
  }

  // ---------------------- UI HELPERS ----------------------
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
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dashedBox({required Widget child}) {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: const Color(0xFFCBD5E1),
        strokeWidth: 1.2,
        dashWidth: 6.0,
        dashSpace: 4.0,
        radius: 12.0,
      ),
      child: Container(padding: const EdgeInsets.all(14), child: child),
    );
  }

  // Helper: obtener idPB desde Historal/$tnRef/idPB
  Future<String?> _fetchIdPBFromRef(String tnRef, {bool fallbackToTnRef = false}) async {
    try {
      final key = Uri.decodeFull(tnRef).trim();
      final snap = await FirebaseDatabase.instance
          .ref('projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$key/idPB')
          .get();

      final val = snap.value?.toString().trim();
      if (snap.exists && val != null && val.isNotEmpty) {
        return val; // idPB real
      }
    } catch (_) {}
    return fallbackToTnRef ? tnRef : null;
  }

  /// Conjunto de idPBs para envío: idPB actual + seleccionados en multientrega
  List<String> get _todasLasGuias {
    final set = <String>{};
    if ((_idPBActual ?? '').trim().isNotEmpty) set.add(_idPBActual!.trim());
    for (final g in _guiasFallidas) {
      final v = g.trim();
      if (v.isNotEmpty) set.add(v);
    }
    return set.toList();
  }

  // ---------------------- BUILD ----------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Entrega Fallida',
            style: TextStyle(fontWeight: FontWeight.w700, color: brand)),
        leadingWidth: 58,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FallidasMultiEntregaPage(
                    // Pasamos idPB actual; si es null/vacío, mandamos lista vacía
                    initialGuias: _idPBActual != null && _idPBActual!.trim().isNotEmpty
                        ? [_idPBActual!]
                        : const [],
                  ),
                ),
              );
              if (resultado != null && resultado is List<String>) {
                setState(() => _guiasFallidas = resultado); // resultado = lista de idPBs
              }
            },
            child: const Text('MultiEntrega',
                style: TextStyle(color: brand, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // Teléfono + Acciones
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

              // No. Guía y titular (UI humana: tnReference)
              const Text('No. Guía:', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 2),
              Text('#${widget.tnReference}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),

              const Text('Titular:', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 2),
              Text(widget.destinatario, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              // Motivo / Método
              _sectionTitle('Metodo de Entrega Fallida'),
              DropdownButtonFormField<String>(
                value: _motivo,
                decoration: _input('Selecciona una opción').copyWith(
                  suffixIcon: Container(
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: brand,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                items: _motivos
                    .map((mot) => DropdownMenuItem(value: mot, child: Text(mot)))
                    .toList(),
                onChanged: (v) => setState(() => _motivo = v!),
              ),

              const SizedBox(height: 16),
              _sectionTitle('Captura de Evidencia'),
              _dashedBox(
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    const Icon(Icons.cloud_upload_outlined, size: 42, color: Colors.black87),
                    const SizedBox(height: 6),
                    const Text(
                      'Selecciona o arrastra tus imágenes o video',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    const Text('(Png y Jpg máx 1gb)', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _tomarFotografia,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F1A2B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Tomar Fotografía',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _abrirGaleria,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brand,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Archivos Galería',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                    if (_previewJpeg != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _previewJpeg!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ] else if (_imagenes[0] != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _imagenes[0]!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ]
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _sectionTitle('Nota Extra'),
              TextField(
                controller: _notaController,
                maxLines: 4,
                decoration: _input('Observaciones adicionales...'),
              ),

              // Mostrar SIEMPRE la lista combinada (idPB actual + adicionales)
              if (_todasLasGuias.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle('Guías fallidas registradas (idPB)'),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE6E6E6)),
                  ),
                  child: Column(
                    children: _todasLasGuias
                        .map((idPB) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.qr_code),
                              title: Text(idPB),
                            ))
                        .toList(),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // BOTÓN GUARDAR
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    // Historal se sigue actualizando por tnReference (ruta humana)
                    final idHistoral = Uri.decodeFull(widget.tnReference).trim();
                    final DatabaseReference ref = FirebaseDatabase.instance
                        .ref("projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$idHistoral");

                    try {
                      final snapshot = await ref.child('Fallos').get();
                      final snapshotIdPB = await ref.child('idPB').get();

                      int intento = 1;
                      if (snapshot.exists) {
                        final valor = snapshot.value;
                        intento = int.tryParse(valor.toString()) != null
                            ? int.parse(valor.toString()) + 1
                            : 1;
                      }

                      final String idPBEnHistoral = snapshotIdPB.value?.toString() ?? '';

                      final codigoFalla = 'FL$intento';
                      final fechaAhora = DateTime.now();
                      final formato = DateFormat('yyyy-MM-dd HH:mm:ss');
                      final yyyyMMddHHmmss = formato.format(fechaAhora);
                      await ref.update({
                        'Estatus': codigoFalla,
                        'Fallos': intento,
                        'FechaEstatus': snapshot.exists ? ServerValue.timestamp : yyyyMMddHHmmss,
                      });

                      final Position posicion = _posicionActual ??
                          await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

                      final nota = _notaController.text.trim();

                      // idPBs para payload (actual + multientrega)
                      final List<String> referencias = _todasLasGuias;
                      final bool esMulti = referencias.length > 1;

                      Map<String, dynamic> dataPayload;

                      if (esMulti) {
                        // MULTI: ya tenemos idPBs listos
                        final Set<String> unicasIdPB = referencias
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toSet();

                        if (unicasIdPB.isEmpty) {
                          await _alert('Faltan idPB', 'No hay paquetes válidos para enviar.');
                          return;
                        }

                        dataPayload = {for (final id in unicasIdPB) id: {"idGuia": id}};
                      } else {
                        // SINGLE: usa paqueteId (idPB) recibido
                        final String idParaEnviar = (widget.paqueteId).trim().isNotEmpty
                            ? widget.paqueteId.trim()
                            : (_idPBActual ?? '').trim();

                        if (idParaEnviar.isEmpty) {
                          await _alert(
                            "Falta paqueteId",
                            "No se recibió un paqueteId (idPB) válido desde la pantalla anterior.",
                          );
                          return;
                        }

                        dataPayload = {idParaEnviar: {"idGuia": idParaEnviar}};
                      }

                      final now = DateTime.now();
                      final yyyyMMdd =
                          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

                      final Map<String, dynamic> body = {
                        "Evidencia1": _urlImagen ?? "",
                        "Intentos": intento,
                        "Latitude": posicion.latitude.toString(),
                        "Longitude": posicion.longitude.toString(),
                        "MotivoFalla": _motivo,
                        "NombreDriver": globalNombre ?? "SinNombre",
                        "NotaExtra": nota,
                        "Timestamp": DateTime.now().millisecondsSinceEpoch,
                        "idDriver": globalUserId ?? "",
                        "data": dataPayload, // <<<<< idPBs como keys
                        "YYYYMMDD": yyyyMMdd,
                        "YYYYMMDDHHMMSS": yyyyMMddHHmmss,
                      };

                      final response = await http.post(
                        Uri.parse('https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_avzsN6aBS9zC1yY5H6xxtq'),
                        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
                        body: jsonEncode(body),
                      );

                      if (!mounted) return;

                      if (response.statusCode == 200) {
                        _snack('Entrega fallida registrada correctamente');
                        Navigator.pop(context);
                      } else {
                        _snack('Error al enviar webhook: ${response.body}');
                      }
                    } catch (e) {
                      if (!mounted) return;
                      _snack('Ocurrió un error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    elevation: 0,
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

// ---------- Painter de borde punteado ----------
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
      final double length = isHorizontal ? (end.dx - start.dx).abs() : (end.dy - start.dy).abs();
      double drawn = 0.0;
      while (drawn < length) {
        final double next = ((drawn + dashWidth).clamp(0.0, length)).toDouble();
        final Offset p1 = isHorizontal ? Offset(start.dx + drawn, start.dy) : Offset(start.dx, start.dy + drawn);
        final Offset p2 = isHorizontal ? Offset(start.dx + next, start.dy) : Offset(start.dx, start.dy + next);
        canvas.drawLine(p1, p2, paint);
        drawn += dashWidth + dashSpace;
      }
    }

    drawDashedLine(Offset(r, 0), Offset(w - r, 0)); // top
    drawDashedLine(Offset(w, r), Offset(w, h - r)); // right
    drawDashedLine(Offset(w - r, h), Offset(r, h)); // bottom
    drawDashedLine(Offset(0, h - r), Offset(0, r)); // left

    void drawDashedArc(Rect rect, double startAngle, double sweep) {
      final path = Path()..addArc(rect, startAngle, sweep);
      for (final metric in path.computeMetrics()) {
        double distance = 0.0;
        while (distance < metric.length) {
          final double next = ((distance + dashWidth).clamp(0.0, metric.length)).toDouble();
          final extract = metric.extractPath(distance, next);
          canvas.drawPath(extract, paint);
          distance += dashWidth + dashSpace;
        }
      }
    }

    drawDashedArc(Rect.fromCircle(center: Offset(r, r), radius: r), math.pi, math.pi / 2); // top-left
    drawDashedArc(Rect.fromCircle(center: Offset(w - r, r), radius: r), -math.pi / 2, math.pi / 2); // top-right
    drawDashedArc(Rect.fromCircle(center: Offset(w - r, h - r), radius: r), 0, math.pi / 2); // bottom-right
    drawDashedArc(Rect.fromCircle(center: Offset(r, h - r), radius: r), math.pi / 2, math.pi / 2); // bottom-left
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashWidth != dashWidth ||
      old.dashSpace != dashSpace ||
      old.radius != radius;
}
