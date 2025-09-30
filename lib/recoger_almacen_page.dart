import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';

// Usa la global como en tus otras pantallas
import 'login_page.dart' show globalIdCiudad;

// Pantalla con escáner
import 'recoger_almacen_scan_page.dart';

class RecogerAlmacenPage extends StatefulWidget {
  const RecogerAlmacenPage({super.key});

  @override
  State<RecogerAlmacenPage> createState() => _RecogerAlmacenPageState();
}

class _RecogerAlmacenPageState extends State<RecogerAlmacenPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _almacenes = [];

  @override
  void initState() {
    super.initState();
    _cargarAlmacenes();
  }

  Future<void> _cargarAlmacenes() async {
  try {
    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/AlmacenPicker',
    );

    final snap = await ref.get();
    final List<Map<String, dynamic>> lista = [];

    if (snap.exists && snap.value is Map) {
      final value = snap.value as Map;
      value.forEach((key, raw) {
        if (raw is Map) {
          // CARGAR TODO: ya NO filtramos por idCiudad
          lista.add({
            'id': key.toString(),
            'NombreAlmacen': raw['NombreAlmacen']?.toString() ?? 'Sin nombre',
            'Direccion': raw['Direccion']?.toString() ?? 'Sin dirección',
            // OJO: seguimos sin leer idFirma de la tabla
          });
        }
      });

      // (Opcional) ordena por nombre para mostrar consistente
      lista.sort((a, b) =>
          (a['NombreAlmacen'] as String).toLowerCase().compareTo(
              (b['NombreAlmacen'] as String).toLowerCase()));
    }

    if (!mounted) return;
    setState(() {
      _almacenes = lista;
      _loading = false;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudieron cargar los almacenes: $e')),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F3F7),
        body: SafeArea(
          child: Column(
            children: [
              // Header con botón atrás y título centrado
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    _BackChip(onTap: () => Navigator.pop(context)),
                    const Spacer(),
                    const Text(
                      'Almacén de recojo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A3365),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _almacenes.isEmpty
                        ? const Center(child: Text('No hay almacenes disponibles'))
                        : RefreshIndicator(
                            onRefresh: _cargarAlmacenes,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                              itemCount: _almacenes.length,
                              itemBuilder: (context, index) {
                                final a = _almacenes[index];
                                return _AlmacenCard(
                                  nombre: a['NombreAlmacen'],
                                  direccion: a['Direccion'],
                                  onTap: () {
                                    // Generar idFirma como timestamp (ms)
                                    final idFirma = DateTime
                                            .now()
                                            .millisecondsSinceEpoch
                                            .toString();

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RecogerAlmacenScanPage(
                                          idAlmacen: a['id'],
                                          nombreAlmacen: a['NombreAlmacen'],
                                          direccionAlmacen: a['Direccion'],
                                          idFirma: idFirma, // << pasamos el timestamp
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  final VoidCallback onTap;
  const _BackChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF0FF),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.arrow_back, color: Color(0xFF1A3365)),
        ),
      ),
    );
  }
}

class _AlmacenCard extends StatelessWidget {
  final String nombre;
  final String direccion;
  final VoidCallback? onTap;

  const _AlmacenCard({
    required this.nombre,
    required this.direccion,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warehouse_outlined, color: Color(0xFF1A3365)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1A3365),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      direccion,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.only(top: 8),
                      color: Colors.black.withOpacity(0.06),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
