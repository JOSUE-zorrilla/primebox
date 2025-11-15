// devolucion_formulario_page.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import 'login_page.dart' show globalNombre, globalUserId;



class DevolucionFormularioPage extends StatefulWidget {
  final String idGuia;       // ÚNICO id escaneado
  final String? idEmpresa;   // Si lo tienes, pásalo aquí

  const DevolucionFormularioPage({
    super.key,
    required this.idGuia,
    this.idEmpresa,
  });

  @override
  State<DevolucionFormularioPage> createState() => _DevolucionFormularioPageState();
}

class _DevolucionFormularioPageState extends State<DevolucionFormularioPage> {
  final _formKey = GlobalKey<FormState>();
  final _responsableCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();

  File? _imagen;
  bool _subiendo = false;
  bool _notificarEmpresa = false; // Switch

  final _picker = ImagePicker();

  @override
  void dispose() {
    _responsableCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _tomarFoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (x != null) setState(() => _imagen = File(x.path));
  }

  Future<void> _desdeGaleria() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _imagen = File(x.path));
  }

  String _fmtFull(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  String _fmtDay(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  Future<String> _subirFoto(String idGuia) async {
    if (_imagen == null) throw 'Debes adjuntar una foto de evidencia.';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref()
        .child('devoluciones')
        .child(idGuia)
        .child('evidencia_$ts.jpg');

    final task = ref.putFile(_imagen!);
    final snap = await task.whenComplete(() {});
    final url = await snap.ref.getDownloadURL();
    return url;
  }

  /// data con SOLO el id escaneado:
  /// {
  ///   "<idGuia>": { "idGuia": "<idGuia>", "Motivo": "<motivo>" }
  /// }
  Map<String, dynamic> _buildDataSingle() {
    final motivo = _motivoCtrl.text.trim();
    final g = widget.idGuia;
    return {
      g: {
        "idGuia": g,
        "Motivo": motivo,
      }
    };
  }

  Future<Map<String, dynamic>> _obtenerGeoYDireccion() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw 'Los servicios de ubicación están desactivados.';

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw 'Permiso de ubicación denegado.';
    }
    if (permission == LocationPermission.deniedForever) {
      throw 'Permiso de ubicación denegado permanentemente.';
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
    String direccion = '';
    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      final partes = <String>[
        p.street ?? '',
        p.subLocality ?? '',
        p.locality ?? '',
        p.administrativeArea ?? '',
        p.postalCode ?? '',
        p.country ?? '',
      ]..removeWhere((s) => s.trim().isEmpty);
      direccion = partes.join(', ');
    }

    return {
      'lat': pos.latitude,
      'lon': pos.longitude,
      'direccion': direccion.isNotEmpty ? direccion : 'Dirección no disponible',
    };
  }

  /// Enviar al webhook con geolocalización, dirección e imagen
  Future<void> _enviarWebhook({
    required String fotoUrl,
    required String direccion,
    required double lat,
    required double lon,
    required Map<String, dynamic> data,
  }) async {
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;

    final payload = {
      'Direccion': direccion,
      'FotoComprobante': fotoUrl,
      'Latitude': lat,
      'Longitude': lon,
      'MotivoDev': _motivoCtrl.text.trim(),
      'NombreUsuario': (globalNombre?.trim().isNotEmpty ?? false) ? globalNombre : 'SinNombre',
      'Timestamp': ts,
      'YYYYMMDD': _fmtDay(now),
      'YYYYMMDDHHMMSS': _fmtFull(now),
      'idEmbarque': ts,
      'idEmpresa': (widget.idEmpresa?.trim().isNotEmpty ?? false) ? widget.idEmpresa : 'SIN_EMPRESA',
      'idUsuario': (globalUserId?.trim().isNotEmpty ?? false) ? globalUserId : 'SIN_UID',
      'data': data, // SOLO el idGuia escaneado
    };

    // 🔧 Endpoint corregido: Apphive Webhook (el de Cloud Run devolvía 404 "Cannot POST /hook/...").
    final uri = Uri.parse('https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_rCqKrsavcb4RjVeFgRjNRc');

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw 'Webhook respondió ${resp.statusCode}: ${resp.body}';
    }
  }

  Future<void> _finalizar() async {
    // Validaciones condicionales:
    // - Si _notificarEmpresa == true => validar campos de texto (responsable y motivo)
    // - Si _notificarEmpresa == false => no validar esos campos.
    if (_notificarEmpresa) {
      final ok = _formKey.currentState?.validate() ?? false;
      if (!ok) return;
    }

    // La foto es requerida en ambos casos
    if (_imagen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes cargar una imagen de evidencia.')),
      );
      return;
    }

    setState(() => _subiendo = true);

    try {
      // Subir la imagen para tener URL
      final fotoUrl = await _subirFoto(widget.idGuia);
      final now = DateTime.now();
      final fecha = _fmtFull(now);

      if (_notificarEmpresa) {
        // Geolocalización + dirección
        final geo = await _obtenerGeoYDireccion();
        final lat = geo['lat'] as double;
        final lon = geo['lon'] as double;
        final direccion = geo['direccion'] as String;

        // data con ÚNICO id
        final data = _buildDataSingle();

        // Enviar al webhook
        await _enviarWebhook(
          fotoUrl: fotoUrl,
          direccion: direccion,
          lat: lat,
          lon: lon,
          data: data,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Devolución notificada a la empresa.')),
        );
      } else {
        // Flujo normal: guardar en Realtime Database
        final movimientosRef = FirebaseDatabase.instance
            .ref('projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/${widget.idGuia}/Movimientos')
            .push();

        await movimientosRef.set({
          'Fecha': fecha,
          'FotoEvidencia': fotoUrl,
          'Movimiento': 'DEV',
          'NombreUsuario': (globalNombre?.trim().isNotEmpty ?? false) ? globalNombre : 'SinNombre',
          'Nota': 'Evidencia de devolución de paquete a cliente',
          'Recibio': _responsableCtrl.text.trim(), // puede venir vacío si switch off
          'Motivo': _motivoCtrl.text.trim(),       // puede venir vacío si switch off
          'idUsuario': (globalUserId?.trim().isNotEmpty ?? false) ? globalUserId : 'SIN_UID',
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Devolución registrada exitosamente')),
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al procesar devolución: $e')),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  String? _validatorObligatorioSiNotificar(String? v, String nombreCampo) {
    if (!_notificarEmpresa) return null; // no obligatorio si el switch está apagado
    if (v == null || v.trim().isEmpty) return 'Ingrese $nombreCampo';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final amarillo = Colors.amber[700];

    return Scaffold(
      backgroundColor: Colors.amber[50],
      appBar: AppBar(
        backgroundColor: amarillo,
        title: const Text('Devolución - Detalles'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'ID Guía: ${widget.idGuia}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Nombre Responsable de la empresa a devolver paquete:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _responsableCtrl,
                    decoration: InputDecoration(
                      hintText: _notificarEmpresa ? 'Ej. Juan Pérez (requerido)' : 'Ej. Juan Pérez (opcional)',
                      filled: true,
                    ),
                    validator: (v) => _validatorObligatorioSiNotificar(v, 'el nombre del responsable'),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Motivo de Devolución',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _motivoCtrl,
                    decoration: InputDecoration(
                      hintText: _notificarEmpresa ? 'Describa el motivo (requerido)' : 'Describa el motivo (opcional)',
                      filled: true,
                    ),
                    maxLines: 3,
                    validator: (v) => _validatorObligatorioSiNotificar(v, 'el motivo de devolución'),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Evidencia (foto o imagen)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _tomarFoto,
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Tomar foto'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700]),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _desdeGaleria,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galería'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_imagen != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _imagen!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),

                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    value: _notificarEmpresa,
                    onChanged: (v) => setState(() {
                      _notificarEmpresa = v;
                      // Revalida para actualizar mensajes de error si cambia el switch
                      _formKey.currentState?.validate();
                    }),
                    title: const Text(
                      'Notificar a Empresa',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _notificarEmpresa
                          ? 'Se tomará geolocalización, se obtendrá dirección y se enviará al webhook (incluye "data" con el único id). Campos de texto: REQUERIDOS.'
                          : 'Se registrará la devolución únicamente en el sistema. Campos de texto: OPCIONALES.',
                    ),
                    activeColor: Colors.amber[700],
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _subiendo ? null : _finalizar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _notificarEmpresa ? 'Finalizar y Notificar' : 'Finalizar Devolución',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_subiendo)
            Container(
              color: Colors.black.withOpacity(0.35),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
