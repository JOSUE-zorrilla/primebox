// devolucion_formulario_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'login_page.dart' show globalNombre, globalUserId;

class DevolucionFormularioPage extends StatefulWidget {
  final String idGuia;
  const DevolucionFormularioPage({super.key, required this.idGuia});

  @override
  State<DevolucionFormularioPage> createState() => _DevolucionFormularioPageState();
}

class _DevolucionFormularioPageState extends State<DevolucionFormularioPage> {
  final _formKey = GlobalKey<FormState>();
  final _responsableCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();

  File? _imagen;
  bool _subiendo = false;

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

  String _fmt(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);

  Future<String> _subirFoto(String idGuia) async {
    if (_imagen == null) throw 'No hay imagen seleccionada';
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

  Future<void> _finalizar() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    if (_imagen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes cargar una imagen de evidencia.')),
      );
      return;
    }

    setState(() => _subiendo = true);

    try {
      final fotoUrl = await _subirFoto(widget.idGuia);

      final now = DateTime.now();
      final fecha = _fmt(now);

      final movimientosRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/${widget.idGuia}/Movimientos',
      ).push(); // crea id

      await movimientosRef.set({
        'Fecha': fecha,
        'FotoEvidencia': fotoUrl,
        'Movimiento': 'DEV',
        'NombreUsuario': (globalNombre?.trim().isNotEmpty ?? false) ? globalNombre : 'SinNombre',
        'Nota': 'Evidencia de devolución de paquete a cliente',
        'Recibio': _responsableCtrl.text.trim(),
        'idUsuario': (globalUserId?.trim().isNotEmpty ?? false) ? globalUserId : 'SIN_UID',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Devolución exitosamente')),
      );

      // Volver a la pantalla de Paquetes (vinimos con pushReplacement desde el escáner)
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar devolución: $e')),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amarillo = Colors.amber[700];

    return Scaffold(
      backgroundColor: Colors.amber[50],
      appBar: AppBar(
        backgroundColor: amarillo,
        title: const Text('Devolución - Detalles'),
        // Al presionar atrás, volvemos a Paquetes (porque la pantalla anterior fue reemplazada)
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
                    decoration: const InputDecoration(
                      hintText: 'Ej. Juan Pérez',
                      filled: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Ingrese el nombre del responsable' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Motivo de Devolución',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _motivoCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Describa el motivo',
                      filled: true,
                    ),
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Ingrese el motivo de devolución' : null,
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
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _subiendo ? null : _finalizar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Finalizar Devolución',
                        style: TextStyle(
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
