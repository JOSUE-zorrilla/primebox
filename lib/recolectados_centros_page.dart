// recolectados_centros_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

// Globales
import 'login_page.dart' show globalUserId;
import 'recolectados_detalle_page.dart';

class RecolectadosCentrosPage extends StatefulWidget {
  const RecolectadosCentrosPage({super.key});

  @override
  State<RecolectadosCentrosPage> createState() => _RecolectadosCentrosPageState();
}

class _RecolectadosCentrosPageState extends State<RecolectadosCentrosPage> {
  late final DatabaseReference _ref;
  bool _loading = true;
  List<_CentroItem> _items = [];

  @override
  void initState() {
    super.initState();
    _ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RecolectadosConductor/${globalUserId ?? ''}/PaquetesRecolectados',
    );
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snap = await _ref.get();

    final List<_CentroItem> tmp = [];
    if (snap.value is Map) {
      final map = (snap.value as Map);
      for (final e in map.entries) {
        final idCentro = e.key.toString(); // clave del registro
        final v = e.value;
        if (v is Map) {
          final nombre = (v['NombreCentro'] ?? '').toString();
          if (nombre.isNotEmpty) {
            tmp.add(_CentroItem(
              idCentroRecoleccion: idCentro,
              nombreCentro: nombre,
            ));
          }
        }
      }
    } else if (snap.value is List) {
      // Por si el nodo es una lista
      final list = (snap.value as List);
      for (int i = 0; i < list.length; i++) {
        final v = list[i];
        if (v is Map) {
          final idCentro = (v['idCentroRecoleccion'] ?? i.toString()).toString();
          final nombre = (v['NombreCentro'] ?? '').toString();
          if (nombre.isNotEmpty) {
            tmp.add(_CentroItem(
              idCentroRecoleccion: idCentro,
              nombreCentro: nombre,
            ));
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _items = tmp;
      _loading = false;
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
              child: SizedBox(
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
                        'Centro de recolección',
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
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text(
                              'Sin centros recolectados.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final it = _items[i];
                            return Card(
                              elevation: 1.5,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFEFF3FF),
                                  child: Icon(Icons.apartment_rounded,
                                      color: Color(0xFF1955CC)),
                                ),
                                title: Text(
                                  it.nombreCentro,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text('ID centro: ${it.idCentroRecoleccion}'),
                                trailing: const Icon(Icons.chevron_right_rounded),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RecolectadosDetallePage(
                                        idCentroRecoleccion: it.idCentroRecoleccion,
                                        nombreCentro: it.nombreCentro,
                                      ),
                                    ),
                                  );
                                },
                              ),
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

class _CentroItem {
  final String idCentroRecoleccion;
  final String nombreCentro;
  _CentroItem({
    required this.idCentroRecoleccion,
    required this.nombreCentro,
  });
}
