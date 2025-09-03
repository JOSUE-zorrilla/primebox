// recolectar_tiendas_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecolectarTiendasPage extends StatefulWidget {
  const RecolectarTiendasPage({super.key});

  @override
  State<RecolectarTiendasPage> createState() => _RecolectarTiendasPageState();
}

class _RecolectarTiendasPageState extends State<RecolectarTiendasPage> {
  bool _loading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  List<_Centro> _centros = [];
  List<_Centro> _filtrados = [];

  @override
  void initState() {
    super.initState();
    _cargarLocales();
    _searchCtrl.addListener(_filtrar);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarLocales() async {
    final prefs = await SharedPreferences.getInstance();

    // Lee la LISTA completa guardada por CentroBootPage
    final jsonStr = prefs.getString('cr_centros_json');

    final List<_Centro> lista = [];
    if (jsonStr != null && jsonStr.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              lista.add(_Centro(
                nombre: (item['Nombre'] ?? '').toString(),
                direccion: (item['Direccion'] ?? '').toString(),
                iconUrl: (item['Icono'] ?? '').toString(),
              ));
            }
          }
        }
      } catch (_) {
        // fallback a las llaves antiguas
      }
    }

    // Fallback: si no hay lista, usa las llaves individuales (1 centro)
    if (lista.isEmpty) {
      final nombre = (prefs.getString('cr_nombre') ?? '').trim();
      final direccion = (prefs.getString('cr_direccion') ?? '').trim();
      final icono = (prefs.getString('cr_icono') ?? '').trim();
      if (nombre.isNotEmpty || direccion.isNotEmpty || icono.isNotEmpty) {
        lista.add(_Centro(nombre: nombre, direccion: direccion, iconUrl: icono));
      }
    }

    // Orden estético
    lista.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

    setState(() {
      _centros = lista;
      _filtrados = [...lista];
      _loading = false;
    });
  }

  void _filtrar() {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtrados = [..._centros]);
      return;
    }
    setState(() {
      _filtrados = _centros
          .where((c) =>
              c.nombre.toLowerCase().contains(q) ||
              c.direccion.toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const headerColor = Color(0xFF1955CC);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            // ===== Encabezado azul estilo mock =====
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              decoration: const BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back + título centrado usando Stack
                  SizedBox(
                    height: 40,
                    child: Stack(
                      children: [
                        // Botón back en un cuadrito redondeado translúcido
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Material(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () => Navigator.pop(context),
                              borderRadius: BorderRadius.circular(10),
                              child: const SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(Icons.arrow_back_ios_new_rounded,
                                    size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        // Título centrado
                        const Align(
                          alignment: Alignment.center,
                          child: Text(
                            'Tiendas a recolectar',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Subtítulo en dos líneas
                  const Text(
                    'Ingresar Nombre',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'para encontrar la información que necesitas.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Buscador
                  TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Buscar',
                      hintStyle: const TextStyle(color: Colors.black38),
                      prefixIcon: const Icon(Icons.search, color: Colors.black45),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ===== Lista =====
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtrados.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text(
                              'No hay centros de recolección guardados.\nInicia sesión nuevamente para sincronizar.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: _filtrados.length,
                          itemBuilder: (_, i) {
                            final c = _filtrados[i];
                            return _CentroCard(
                              iconUrl: c.iconUrl,
                              nombre:
                                  c.nombre.isEmpty ? 'Centro sin nombre' : c.nombre,
                              direccion: c.direccion.isEmpty
                                  ? 'Dirección no registrada'
                                  : c.direccion,
                              onTap: () {
                                // TODO: Navegar al detalle de recolección
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Seleccionado: ${c.nombre}')),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CentroCard extends StatelessWidget {
  final String iconUrl;
  final String nombre;
  final String direccion;
  final VoidCallback onTap;

  const _CentroCard({
    required this.iconUrl,
    required this.nombre,
    required this.direccion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // fila superior
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icono cuadrado
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF3FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: iconUrl.isNotEmpty
                        ? Image.network(
                            iconUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.store_mall_directory,
                              color: Color(0xFF1A3365),
                            ),
                          )
                        : const Icon(Icons.store_mall_directory,
                            color: Color(0xFF1A3365)),
                  ),
                  const SizedBox(width: 10),

                  // Etiqueta + nombre
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Centro de recolección',
                          style: TextStyle(
                            color: Color(0xFF6C7A92),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                      ],
                    ),
                  ),

                  const Icon(Icons.chevron_right_rounded,
                      color: Color(0xFF6C7A92)),
                ],
              ),

              const SizedBox(height: 2),
              Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF1A3365),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Dirección',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                direccion,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6C7A92),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Centro {
  final String nombre;
  final String direccion;
  final String iconUrl;
  _Centro({required this.nombre, required this.direccion, required this.iconUrl});
}
