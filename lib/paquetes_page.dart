import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'paqueteDetallePage.dart'; 


class PaquetesPage extends StatefulWidget {
  const PaquetesPage({super.key});

  @override
  State<PaquetesPage> createState() => _PaquetesPageState();
}

class _PaquetesPageState extends State<PaquetesPage> {
  final List<Map<String, dynamic>> _paquetes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargarPaquetes();
  }

  Future<void> _cargarPaquetes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final DatabaseReference ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes',
    );

    final snapshot = await ref.get();

    if (snapshot.exists) {
      final Map data = snapshot.value as Map;
      final List<Map<String, dynamic>> lista = [];

      data.forEach((key, value) {
        lista.add({
          'id': key,
          'DireccionEntrega': value['DireccionEntrega'] ?? '',
          'Destinatario': value['Destinatario'] ?? '',
          'Intentos': value['Intentos'] ?? 0,
        });
      });

      setState(() {
        _paquetes.clear();
        _paquetes.addAll(lista);
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Paquetes'),
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _paquetes.isEmpty
              ? const Center(child: Text('No hay paquetes disponibles'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _paquetes.length,
                  itemBuilder: (context, index) {
                    final paquete = _paquetes[index];

                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('🧾 Orden: ${paquete['id']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text('📍 Dirección: ${paquete['DireccionEntrega']}'),
                            Text('👤 Destinatario: ${paquete['Destinatario']}'),
                            Text('📦 Intentos: ${paquete['Intentos']}'),
                            const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Botón Rechazar a la izquierda
                                  ElevatedButton(
                                    onPressed: () {
                                      // Acción rechazar
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.black),
                                    ),
                                    child: const Text(
                                      'Rechazar',
                                      style: TextStyle(color: Colors.black),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // Botón Aceptar a la derecha
                                  ElevatedButton(
                                    onPressed: () async {
                                      final user = FirebaseAuth.instance.currentUser;
                                      if (user == null) return;

                                      final DatabaseReference tnRef = FirebaseDatabase.instance.ref(
                                        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}',
                                      );

                                      final tnSnapshot = await tnRef.child(paquete['id']).get();
                                      final tnReference = tnSnapshot.child('TnReference').value ?? 'Sin referencia';

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PaqueteDetallePage(
                                            id: paquete['id'],
                                            telefono: tnSnapshot.child('Telefono').value?.toString() ?? '',
                                            destinatario: paquete['Destinatario'],
                                            tnReference: tnReference.toString(),
                                          ),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                    ),
                                    child: const Text(
                                      'Aceptar',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),


                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
