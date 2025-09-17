// recolectar_tiendas_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recolectar_recoleccion_page.dart';

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

    final jsonStr = prefs.getString('cr_centros_json');
    final List<_Centro> lista = [];

    if (jsonStr != null && jsonStr.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonStr);

        // 1) LISTA de objetos
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final id = (item['IdTienda'] ??
                      item['idTienda'] ??
                      item['Id'] ??
                      item['id'] ??
                      item['uid'] ??
                      item['key'] ??
                      item['idGuiaPB'] ?? // por si viene como guía
                      '')
                  .toString();

              // nombre/dirección opcionales
              final nombre = (item['Nombre'] ?? item['nombre'] ?? id).toString();
              final direccion =
                  (item['Direccion'] ?? item['direccion'] ?? '').toString();
              final icono = (item['Icono'] ?? item['icono'] ?? '').toString();

              lista.add(_Centro(
                idTienda: id,
                nombre: nombre.isEmpty ? id : nombre,
                direccion: direccion,
                iconUrl: icono,
              ));
            }
          }
        }
        // 2) MAPA { "<id>": { ... } }  ← TU CASO
        else if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value is Map) {
              // si no hay id dentro, usar la CLAVE del mapa
              final id = (value['IdTienda'] ??
                      value['idTienda'] ??
                      value['Id'] ??
                      value['id'] ??
                      value['idGuiaPB'] ??
                      key)
                  .toString();

              // estos datos pueden NO venir; mostramos algo útil
              final nombre =
                  (value['Nombre'] ?? value['nombre'] ?? 'ID $key').toString();
              final direccion =
                  (value['Direccion'] ?? value['direccion'] ?? '').toString();
              final icono = (value['Icono'] ?? value['icono'] ?? '').toString();

              lista.add(_Centro(
                idTienda: id,
                nombre: nombre.isEmpty ? 'ID $key' : nombre,
                direccion: direccion,
                iconUrl: icono,
              ));
            } else {
              // Si el valor no es Map, al menos mostramos la clave como item
              lista.add(_Centro(
                idTienda: key.toString(),
                nombre: 'ID $key',
                direccion: '',
                iconUrl: '',
              ));
            }
          });
        }
      } catch (_) {
        // sigue al fallback
      }
    }

    // Fallback: llaves individuales (1 centro)
    if (lista.isEmpty) {
      final id = (prefs.getString('cr_id_tienda') ??
              prefs.getString('cr_id') ??
              prefs.getString('cr_key') ??
              '')
          .trim();
      final nombre = (prefs.getString('cr_nombre') ?? '').trim();
      final direccion = (prefs.getString('cr_direccion') ?? '').trim();
      final icono = (prefs.getString('cr_icono') ?? '').trim();
      if (id.isNotEmpty || nombre.isNotEmpty || direccion.isNotEmpty) {
        lista.add(_Centro(
          idTienda: id,
          nombre: nombre.isEmpty ? id : nombre,
          direccion: direccion,
          iconUrl: icono,
        ));
      }
    }

    // Orden y setState
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
            // Header
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
                  SizedBox(
                    height: 40,
                    child: Stack(
                      children: [
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

            // Lista
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtrados.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text(
                              'No hay registros.\nInicia sesión nuevamente para sincronizar.',
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
                              nombre: c.nombre.isEmpty ? 'ID ${c.idTienda}' : c.nombre,
                              direccion: c.direccion.isEmpty ? '—' : c.direccion,
                              onTap: () {
                                if (c.idTienda.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Este registro no tiene ID.'),
                                    ),
                                  );
                                  return;
                                }

                                // Generar el timestamp de Embarque y enviarlo a la siguiente pantalla
                                final embarqueMs =
                                    DateTime.now().millisecondsSinceEpoch;

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RecolectarRecoleccionPage(
                                      idTienda: c.idTienda,
                                      nombreCentro: c.nombre,
                                      direccionCentro: c.direccion,
                                      iconUrl: c.iconUrl,
                                      embarqueMs: embarqueMs, // ← NUEVO
                                    ),
                                  ),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
                  const Expanded(
                    child: Text(
                      'Centro de recolección',
                      style: TextStyle(
                        color: Color(0xFF6C7A92),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
              const Text('Dirección', style: TextStyle(fontWeight: FontWeight.w700)),
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
  final String idTienda;   // ← aquí guardamos la CLAVE del mapa (p.ej. L0003175562114040030PB)
  final String nombre;
  final String direccion;
  final String iconUrl;
  _Centro({
    required this.idTienda,
    required this.nombre,
    required this.direccion,
    required this.iconUrl,
  });
}
