import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class FilaVirtualListaPage extends StatelessWidget {
  final String idAlmacen;
  final String nombreAlmacen;

  const FilaVirtualListaPage({
    super.key,
    required this.idAlmacen,
    required this.nombreAlmacen,
  });

  @override
  Widget build(BuildContext context) {
    final path =
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/FilaVirtualAlmacen/$idAlmacen/FilaVirtual';

    final ref = FirebaseDatabase.instance.ref(path);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fila Virtual'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombreAlmacen,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  'Conductores en fila virtual',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: ref.onValue,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                final dataSnapshot = snapshot.data?.snapshot;
                if (dataSnapshot == null || !dataSnapshot.exists) {
                  return const Center(
                    child: Text('No hay conductores en la fila virtual.'),
                  );
                }

                final raw = dataSnapshot.value;
                if (raw is! Map) {
                  return const Center(child: Text('Formato inesperado de datos.'));
                }

                // Map<String, dynamic> esperando { userId: {NombreDriver, HoraVinculacion, idDriver, ...} }
                final map = Map<String, dynamic>.from(raw as Map);

                // Convertir a lista y ordenar por HoraVinculacion asc (si se puede)
                final items = <_FilaItem>[];
                map.forEach((key, value) {
                  if (value is Map) {
                    final v = Map<String, dynamic>.from(value);
                    items.add(_FilaItem(
                      id: key,
                      nombre: (v['NombreDriver'] ?? '').toString(),
                      hora: (v['HoraVinculacion'] ?? '').toString(),
                    ));
                  }
                });

                items.sort((a, b) => a.hora.compareTo(b.hora));

                if (items.isEmpty) {
                  return const Center(
                    child: Text('No hay conductores en la fila virtual.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    return Card(
                      elevation: 1.0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(it.nombre.isEmpty ? '(Sin nombre)' : it.nombre),
                        subtitle: Text('Hora vinculación: ${it.hora}'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF3FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('#${i + 1}',
                              style: const TextStyle(
                                  color: Color(0xFF1955CC),
                                  fontWeight: FontWeight.w700)),
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
    );
  }
}

class _FilaItem {
  final String id;
  final String nombre;
  final String hora;

  _FilaItem({
    required this.id,
    required this.nombre,
    required this.hora,
  });
}
