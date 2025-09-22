import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// Usa tus variables globales como en otras pantallas
import 'login_page.dart' show globalNombre, globalUserId;

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

  // Campos de imagen (URLs)
  String _ineFrente = '';
  String _ineAtras = '';
  String _cartaAntecedentes = '';
  String _comprobanteDomicilio = '';

  // Visor de imagen en overlay
  String? _viewerUrl;

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

        // Imágenes (ajusta si tus claves tienen otro nombre exacto)
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

  void _openViewer(String url) {
    if (url.isEmpty) return;
    setState(() => _viewerUrl = url);
  }

  void _closeViewer() {
    setState(() => _viewerUrl = null);
  }

  @override
  Widget build(BuildContext context) {
    final conectado = _estadoConexion == 'Conectado';
    final chipText = conectado ? 'Conectado' : 'Descanso';

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
                            CircleAvatar(
                              radius: 36,
                              backgroundImage:
                                  _foto.isNotEmpty ? NetworkImage(_foto) : null,
                              child: _foto.isEmpty
                                  ? const Icon(Icons.person,
                                      color: Colors.white, size: 36)
                                  : null,
                              backgroundColor: const Color(0xFF2A6AE8),
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
                            Container(
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
                                chipText,
                                style: TextStyle(
                                  color: conectado
                                      ? const Color(0xFF1955CC)
                                      : Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
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
                              _InfoImageRow(
                                leading: Icons.badge_outlined,
                                label: 'Ine (frente)',
                                url: _ineFrente,
                                onTap: _openViewer,
                              ),
                              const Divider(height: 20),
                              _InfoImageRow(
                                leading: Icons.badge_outlined,
                                label: 'Ine (atrás)',
                                url: _ineAtras,
                                onTap: _openViewer,
                              ),
                              const Divider(height: 20),
                              _InfoImageRow(
                                leading: Icons.description_outlined,
                                label: 'Carta de antecedentes',
                                url: _cartaAntecedentes,
                                onTap: _openViewer,
                              ),
                              const Divider(height: 20),
                              _InfoImageRow(
                                leading: Icons.home_outlined,
                                label: 'Comprobante de domicilio',
                                url: _comprobanteDomicilio,
                                onTap: _openViewer,
                              ),
                              const SizedBox(height: 12),
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
                            // Imagen con zoom y pan
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 24, 12, 24),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: InteractiveViewer(
                                    minScale: 0.8,
                                    maxScale: 4.0,
                                    child: AspectRatio(
                                      aspectRatio: 3 / 4,
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
                            ),
                            // Botón cerrar
                            Positioned(
                              top: 12,
                              right: 12,
                              child: IconButton(
                                onPressed: _closeViewer,
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withOpacity(0.15),
                                ),
                                icon: const Icon(Icons.close,
                                    color: Colors.white, size: 28),
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

/// Fila para valores de texto (Email / Phone)
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

/// Fila para documentos-imagen. Si la URL existe, muestra “tappable” con ícono de ojo.
class _InfoImageRow extends StatelessWidget {
  final IconData leading;
  final String label;
  final String url;
  final void Function(String url) onTap;

  const _InfoImageRow({
    required this.leading,
    required this.label,
    required this.url,
    required this.onTap,
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

    final hasImage = url.trim().isNotEmpty;

    return InkWell(
      onTap: hasImage ? () => onTap(url) : null,
      borderRadius: BorderRadius.circular(8),
      child: Row(
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
                Text(label,
                    style: const TextStyle(color: titleColor, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  hasImage ? 'Ver documento' : 'No cargado',
                  style: valueStyle.copyWith(
                    color: hasImage ? Colors.black87 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            hasImage ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: hasImage ? mainColor : Colors.black26,
            size: 20,
          ),
        ],
      ),
    );
  }
}
