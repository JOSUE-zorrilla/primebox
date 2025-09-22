import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// Usa las globals igual que en tus otras pantallas
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

  // Visor de imagen
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
    if (url.isNotEmpty) setState(() => _viewerUrl = url);
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
                                const SizedBox(width: 48), // balance visual
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

                            // Píldora de estado (si dice "Descanso", se puede tocar para abrir el sheet)
                            InkWell(
                              onTap: conectado ? null : _openDescansosSheet,
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
