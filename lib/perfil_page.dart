import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// Usa las globals igual que en tus otras pantallas
import 'login_page.dart' show globalNombre, globalUserId;

// ===== NUEVO: imports para cambiar foto y subir docs =====
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';            // << NUEVO
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';          // << NUEVO
import 'package:mime/mime.dart';                           // << NUEVO
import 'dart:typed_data' show Uint8List;

// ===========================================

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  bool _loading = true;

  // Campos de texto
  String _foto = '';
  String _nombre = '';
  String _email = '';
  String _telefono = '';
  String _estadoConexion = 'Desconectado';

  // Campos de imagen/documento (URLs)
  String _ineFrente = '';
  String _ineAtras = '';
  String _cartaAntecedentes = '';
  String _comprobanteDomicilio = '';

  // Visor de imagen
  String? _viewerUrl;

  // Estado de subida
  bool _subiendoFoto = false;

  // NUEVO: progreso por campo de documento
  final Map<String, bool> _subiendoCampo = {
    'IneFrente': false,
    'IneAtras': false,
    'CartaAntecedentes': false,
    'ComprobanteDomicilio': false,
  };

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    final String uid = (globalUserId?.trim().isNotEmpty ?? false)
        ? globalUserId!.trim()
        : user.uid;

    try {
      final base =
          'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/$uid';

      final ref = FirebaseDatabase.instance.ref(base);
      final snap = await ref.get();

      final estadoSnap =
          await FirebaseDatabase.instance.ref('$base/EstadoConexion').get();

      setState(() {
        _foto = (snap.child('Foto').value ?? '').toString();
        _nombre = (snap.child('Nombre').value ?? '').toString();
        _email = (snap.child('Email').value ?? '').toString();
        _telefono = (snap.child('Telefono').value ?? '').toString();

        _ineFrente = (snap.child('IneFrente').value ?? '').toString();
        _ineAtras = (snap.child('IneAtras').value ?? '').toString();
        _cartaAntecedentes =
            (snap.child('CartaAntecedentes').value ?? '').toString();
        _comprobanteDomicilio =
            (snap.child('ComprobanteDomicilio').value ?? '').toString();

        _estadoConexion = (estadoSnap.value ?? 'Desconectado').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el perfil: $e')),
      );
    }
  }

  void _openViewer(String url) async {
    if (url.isEmpty) return;
    // Si es PDF -> abrir con navegador/visor externo
    if (_isPdfUrl(url)) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _toast('No se pudo abrir el documento.');
      }
      return;
    }
    // Si es imagen -> visor interno
    setState(() => _viewerUrl = url);
  }

  void _closeViewer() => setState(() => _viewerUrl = null);

  // ---------- DESCANSOS (Bottom Sheet) ----------
  Future<void> _openDescansosSheet() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DescansosSheet(),
    );
  }

  // =========================================================
  // ============== CAMBIAR FOTO DE PERFIL ===================
  // =========================================================
  Future<void> _cambiarFotoPerfil() async {
    if (_subiendoFoto) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Cambiar foto de perfil',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Seleccionar de galería'),
              onTap: () async {
                Navigator.pop(context);
                await _pickAndUpload(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () async {
                Navigator.pop(context);
                await _pickAndUpload(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      // Permisos (no aplica en Web)
      if (!kIsWeb) {
        if (source == ImageSource.camera) {
          final cam = await Permission.camera.request();
          if (!cam.isGranted) {
            _toast('Permiso de cámara denegado');
            return;
          }
        } else {
          final gal = await Permission.photos.request();
          if (!gal.isGranted && gal.isPermanentlyDenied == false) {
            _toast('Permiso de galería denegado');
            return;
          }
        }
      }

      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;

      await _subirFotoPerfil(picked);
    } catch (e) {
      _toast('No se pudo seleccionar la imagen: $e');
    }
  }

  Future<void> _subirFotoPerfil(XFile picked) async {
    if (_subiendoFoto) return;
    setState(() => _subiendoFoto = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Sesión no válida.');
      setState(() => _subiendoFoto = false);
      return;
    }

    final String uid = (globalUserId?.trim().isNotEmpty ?? false)
        ? globalUserId!.trim()
        : user.uid;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(
      content: Text('Subiendo foto...'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(days: 1),
    ));

    try {
      final fileName = (picked.name.isNotEmpty ? picked.name : 'perfil.jpg')
          .replaceAll(RegExp(r'\s+'), '_');
      final safeName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(fileName)}';

final ref = FirebaseStorage.instance
    .ref()
    .child('conductores_perfil')
    .child(uid)
    .child(safeName);

// SIEMPRE putData con bytes
final bytes = await picked.readAsBytes();
await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));

      final url = await ref.getDownloadURL();

      final base =
          'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/$uid';
      await FirebaseDatabase.instance.ref('$base/Foto').set(url);

      // Opcional: actualizar también FirebaseAuth
      try {
        await user.updatePhotoURL(url);
      } catch (_) {}

      setState(() {
        _foto = url;
        _subiendoFoto = false;
      });

      messenger.hideCurrentSnackBar();
      _toast('Foto actualizada correctamente');
    } catch (e) {
      setState(() => _subiendoFoto = false);
      messenger.hideCurrentSnackBar();
      _toast('Error al subir la foto: $e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // =========================================================
  // ========== SUBIR DOCUMENTO (imagen o PDF) ===============
  // =========================================================
  Future<void> _elegirYSubirDocumento(String campo) async {
    // BottomSheet con opciones
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Subir documento',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Imagen desde galería'),
              onTap: () async {
                Navigator.pop(context);
                await _subirDocumentoDesdeImagen(campo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () async {
                Navigator.pop(context);
                await _subirDocumentoDesdeCamara(campo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Seleccionar PDF / archivo'),
              onTap: () async {
                Navigator.pop(context);
                await _subirDocumentoDesdeArchivo(campo);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _subirDocumentoDesdeImagen(String campo) async {
    try {
      if (!kIsWeb) {
        final gal = await Permission.photos.request();
        if (!gal.isGranted && gal.isPermanentlyDenied == false) {
          _toast('Permiso de galería denegado');
          return;
        }
      }
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (picked == null) return;
      final ext = _safeExtension(picked.name, fallback: 'jpg');
      final mime = lookupMimeType(picked.name) ?? 'image/jpeg';
      final bytes = await picked.readAsBytes();
      await _subirBytesAGuardarURL(campo, bytes, ext, mime);
    } catch (e) {
      _toast('No se pudo seleccionar la imagen: $e');
    }
  }

  Future<void> _subirDocumentoDesdeCamara(String campo) async {
    try {
      if (!kIsWeb) {
        final cam = await Permission.camera.request();
        if (!cam.isGranted) {
          _toast('Permiso de cámara denegado');
          return;
        }
      }
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (picked == null) return;
      final ext = _safeExtension(picked.name, fallback: 'jpg');
      final mime = lookupMimeType(picked.name) ?? 'image/jpeg';
      final bytes = await picked.readAsBytes();
      await _subirBytesAGuardarURL(campo, bytes, ext, mime);
    } catch (e) {
      _toast('No se pudo usar la cámara: $e');
    }
  }

  Future<void> _subirDocumentoDesdeArchivo(String campo) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
        withData: kIsWeb, // en web necesitamos bytes
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;

      final ext = _safeExtension(file.name, fallback: 'pdf');
      final mime = lookupMimeType(file.name) ??
          (ext == 'pdf' ? 'application/pdf' : 'application/octet-stream');

      // Bytes (web) o desde path (móvil/desktop)
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          _toast('No se pudo leer el archivo.');
          return;
        }
        await _subirBytesAGuardarURL(campo, bytes, ext, mime);
      } else {
        if (file.path == null) {
          _toast('Ruta de archivo no disponible.');
          return;
        }
        await _subirFileAGuardarURL(campo, File(file.path!), ext, mime);
      }
    } catch (e) {
      _toast('No se pudo seleccionar el archivo: $e');
    }
  }

Future<void> _subirBytesAGuardarURL(
  String campo,
  Uint8List bytes,        // ← antes era List<int>
  String ext,
  String mime,
) async {
  await _subirGenerico(
    campo,
    uploader: (ref) async {
      await ref.putData(
        bytes,                          // ← directo, sin fromList
        SettableMetadata(contentType: mime),
      );
    },
    ext: ext,
  );
}


  Future<void> _subirFileAGuardarURL(
      String campo, File file, String ext, String mime) async {
    await _subirGenerico(campo, uploader: (ref) async {
      await ref.putFile(file, SettableMetadata(contentType: mime));
    }, ext: ext);
  }

  Future<void> _subirGenerico(
    String campo, {
    required Future<void> Function(Reference ref) uploader,
    required String ext,
  }) async {
    if (_subiendoCampo[campo] == true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Sesión no válida.');
      return;
    }
    final String uid = (globalUserId?.trim().isNotEmpty ?? false)
        ? globalUserId!.trim()
        : user.uid;

    setState(() => _subiendoCampo[campo] = true);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Subiendo $campo...'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(days: 1),
    ));

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final safeName = '${campo}_$ts.$ext';
      final ref = FirebaseStorage.instance
          .ref()
          .child('conductores_docs')
          .child(uid)
          .child(campo)
          .child(safeName);

      await uploader(ref);
      final url = await ref.getDownloadURL();

      final base =
          'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/$uid';
      await FirebaseDatabase.instance.ref('$base/$campo').set(url);

      // refrescar UI local
      setState(() {
        switch (campo) {
          case 'IneFrente':
            _ineFrente = url;
            break;
          case 'IneAtras':
            _ineAtras = url;
            break;
          case 'CartaAntecedentes':
            _cartaAntecedentes = url;
            break;
          case 'ComprobanteDomicilio':
            _comprobanteDomicilio = url;
            break;
        }
        _subiendoCampo[campo] = false;
      });

      messenger.hideCurrentSnackBar();
      _toast('Documento de $campo actualizado.');
    } catch (e) {
      setState(() => _subiendoCampo[campo] = false);
      messenger.hideCurrentSnackBar();
      _toast('Error al subir $campo: $e');
    }
  }

  String _safeExtension(String name, {String fallback = 'dat'}) {
    final ext = p.extension(name).replaceAll('.', '').toLowerCase();
    if (ext.isEmpty) return fallback;
    return ext;
  }

  bool _isPdfUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.pdf') || lower.startsWith('blob:application/pdf');
  }

  // =================== BOTONES INFERIORES =====================
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _eliminarCuenta() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('No hay usuario autenticado.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmación'),
        content: const Text('¿Desea eliminar su cuenta ahora?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí')),
        ],
      ),
    );
    if (confirm != true) return;

    final String soporteId = (globalUserId?.trim().isNotEmpty ?? false)
        ? globalUserId!.trim()
        : user.uid;

    try {
      final ticketsRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/TicketsDrivers',
      ).push(); // ID automático

      final fecha = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      await ticketsRef.set({
        'Descripcion': 'Eliminar cuenta',
        'Fecha': fecha,
        'idSoporte': soporteId,
        'idTicket': soporteId,
      });

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      _toast('No se pudo crear el ticket: $e');
    }
  }
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    final conectado = _estadoConexion == 'Conectado';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // Contenido principal
                  Column(
                    children: [
                      // Encabezado azul
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1955CC),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.arrow_back,
                                      color: Colors.white),
                                ),
                                const Spacer(),
                                const Text(
                                  'Perfil',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                const SizedBox(width: 48),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Avatar tocable + indicador de subida
                            Stack(
                              children: [
                                InkWell(
                                  onTap: _cambiarFotoPerfil,
                                  borderRadius: BorderRadius.circular(999),
                                  child: CircleAvatar(
                                    radius: 36,
                                    backgroundImage:
                                        _foto.isNotEmpty ? NetworkImage(_foto) : null,
                                    child: _foto.isEmpty
                                        ? const Icon(Icons.person,
                                            color: Colors.white, size: 36)
                                        : null,
                                    backgroundColor: const Color(0xFF2A6AE8),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 3,
                                        )
                                      ],
                                    ),
                                    child: _subiendoFoto
                                        ? const Padding(
                                            padding: EdgeInsets.all(6),
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.camera_alt, size: 16, color: Color(0xFF1955CC)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _nombre.isEmpty ? 'Sin nombre' : _nombre,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Repartidor',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 8),

                            // Píldora de estado -> SIEMPRE abre Descansos
                            InkWell(
                              onTap: _openDescansosSheet,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: conectado
                                      ? Colors.white
                                      : const Color(0xFF2F63D3),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  'Descansos',
                                  style: TextStyle(
                                    color: conectado ? const Color(0xFF1955CC) : Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Sección blanca con los datos
                      Expanded(
                        child: Container(
                          color: Colors.white,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            children: [
                              _InfoTextRow(
                                leading: Icons.email_outlined,
                                label: 'Email',
                                value: _email,
                              ),
                              const Divider(height: 20),
                              _InfoTextRow(
                                leading: Icons.phone_outlined,
                                label: 'Phone',
                                value: _telefono,
                              ),
                              const Divider(height: 20),

                              // --------- Fila: Ine Frente ----------
                              _InfoDocRow(
                                leading: Icons.badge_outlined,
                                label: 'Ine (frente)',
                                url: _ineFrente,
                                onView: _openViewer,
                                uploading: _subiendoCampo['IneFrente'] == true,
                                onUpload: () => _elegirYSubirDocumento('IneFrente'),
                              ),
                              const Divider(height: 20),

                              // --------- Fila: Ine Atrás ------------
                              _InfoDocRow(
                                leading: Icons.badge_outlined,
                                label: 'Ine (atrás)',
                                url: _ineAtras,
                                onView: _openViewer,
                                uploading: _subiendoCampo['IneAtras'] == true,
                                onUpload: () => _elegirYSubirDocumento('IneAtras'),
                              ),
                              const Divider(height: 20),

                              // --------- Fila: Carta Antecedentes ---
                              _InfoDocRow(
                                leading: Icons.description_outlined,
                                label: 'Carta de antecedentes',
                                url: _cartaAntecedentes,
                                onView: _openViewer,
                                uploading: _subiendoCampo['CartaAntecedentes'] == true,
                                onUpload: () => _elegirYSubirDocumento('CartaAntecedentes'),
                              ),
                              const Divider(height: 20),

                              // --------- Fila: Comprobante Domicilio -
                              _InfoDocRow(
                                leading: Icons.home_outlined,
                                label: 'Comprobante de domicilio',
                                url: _comprobanteDomicilio,
                                onView: _openViewer,
                                uploading: _subiendoCampo['ComprobanteDomicilio'] == true,
                                onUpload: () => _elegirYSubirDocumento('ComprobanteDomicilio'),
                              ),
                              const SizedBox(height: 24),

                              // ================== BOTONES ABAJO ==================
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _logout,
                                      icon: const Icon(Icons.logout),
                                      label: const Text('Cerrar sesión'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        side: const BorderSide(color: Color(0xFF1955CC)),
                                        foregroundColor: const Color(0xFF1955CC),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _eliminarCuenta,
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Eliminar cuenta'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFE53935),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // ===================================================
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Overlay visor de imagen
                  if (_viewerUrl != null) ...[
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _closeViewer,
                        child: Container(
                          color: Colors.black.withOpacity(0.85),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: SafeArea(
                        child: Stack(
                          children: [
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 24, 12, 24),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: InteractiveViewer(
                                    minScale: 0.8,
                                    maxScale: 4.0,
                                    child: Image.network(
                                      _viewerUrl!,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return const ColoredBox(
                                          color: Colors.black12,
                                          child: Center(
                                            child: Text(
                                              'No se pudo cargar la imagen',
                                              style: TextStyle(
                                                  color: Colors.white70),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: IconButton(
                                onPressed: _closeViewer,
                                icon: const Icon(Icons.close,
                                    color: Colors.white, size: 28),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withOpacity(0.15),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// --------- BOTTOM SHEET DE DESCANSOS (muestra el texto tal cual viene de RTDB) ---------
class _DescansosSheet extends StatelessWidget {
  const _DescansosSheet({super.key});

  DatabaseReference get _ref => FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/DescansoDias',
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black26)],
          ),
          child: Column(
            children: [
              // Barra superior con X
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              // Título y subtítulo
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Descansos',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sin fecha',
                      style: TextStyle(
                          color: Colors.black54, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<DataSnapshot>(
                  future: _ref.get(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snap.hasData || !snap.data!.exists) {
                      return const Center(child: Text('Sin datos de descansos.'));
                    }

                    final val = snap.data!.value;
                    final List<String> fechas = [];

                    if (val is Map) {
                      val.forEach((_, v) {
                        final raw = (v is Map ? v['Fecha'] : v)?.toString() ?? '';
                        if (raw.trim().isNotEmpty) fechas.add(raw.trim());
                      });
                    } else if (val is List) {
                      for (final v in val) {
                        final raw = (v is Map ? v['Fecha'] : v)?.toString() ?? '';
                        if (raw.trim().isNotEmpty) fechas.add(raw.trim());
                      }
                    } else {
                      final raw = val.toString();
                      if (raw.trim().isNotEmpty) fechas.add(raw.trim());
                    }

                    if (fechas.isEmpty) {
                      return const Center(child: Text('No hay fechas cargadas.'));
                    }

                    return ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                      itemBuilder: (context, i) {
                        return _DescansoCardSimple(textoFecha: fechas[i]);
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: fechas.length,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DescansoCardSimple extends StatelessWidget {
  final String textoFecha; // Se muestra tal cual viene de RTDB

  const _DescansoCardSimple({required this.textoFecha, super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1A3365)),
              ),
              child: const Icon(Icons.event_note_outlined,
                  color: Color(0xFF1A3365)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fecha',
                      style: TextStyle(
                          color: Color(0xFF6B7A99), fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    textoFecha.isEmpty ? '—' : textoFecha,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- Filas de la parte blanca ----------
class _InfoTextRow extends StatelessWidget {
  final IconData leading;
  final String label;
  final String value;

  const _InfoTextRow({
    required this.leading,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    const titleColor = Color(0xFF6B7A99);
    const valueStyle = TextStyle(
      color: Colors.black87,
      fontWeight: FontWeight.w600,
      fontSize: 16,
    );
    const mainColor = Color(0xFF1A3365);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(leading, color: mainColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: titleColor, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value.isEmpty ? '—' : value, style: valueStyle),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila de Documento con "Ver" y "Subir/Actualizar"
class _InfoDocRow extends StatelessWidget {
  final IconData leading;
  final String label;
  final String url;
  final void Function(String url) onView;
  final VoidCallback onUpload;
  final bool uploading;

  const _InfoDocRow({
    required this.leading,
    required this.label,
    required this.url,
    required this.onView,
    required this.onUpload,
    this.uploading = false,
  });

  @override
  Widget build(BuildContext context) {
    const titleColor = Color(0xFF6B7A99);
    const valueStyle = TextStyle(
      color: Colors.black87,
      fontWeight: FontWeight.w600,
      fontSize: 16,
    );
    const mainColor = Color(0xFF1A3365);

    final hasDoc = url.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(leading, color: mainColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: titleColor, fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  // Ver documento (si hay)
                  Expanded(
                    child: InkWell(
                      onTap: hasDoc ? () => onView(url) : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          Icon(
                            hasDoc
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: hasDoc ? mainColor : Colors.black26,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasDoc ? 'Ver documento' : 'No cargado',
                            style: valueStyle.copyWith(
                              color: hasDoc ? Colors.black87 : Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Subir/Actualizar
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: uploading ? null : onUpload,
                      icon: uploading
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined, size: 18),
                      label: Text(uploading ? 'Subiendo...' : 'Subir'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1955CC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
