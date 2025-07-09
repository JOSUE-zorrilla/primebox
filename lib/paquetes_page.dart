import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'paqueteDetallePage.dart';
import 'entrega_fallida_page.dart';

class PaquetesPage extends StatefulWidget {
  const PaquetesPage({super.key});

  @override
  State<PaquetesPage> createState() => _PaquetesPageState();
}

class _PaquetesPageState extends State<PaquetesPage> {
  final List<Map<String, dynamic>> _paquetes = [];
  List<Map<String, dynamic>> _paquetesFiltrados = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filtrarPaquetes);
    _cargarPaquetes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filtrarPaquetes() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _paquetesFiltrados = [..._paquetes]);
    } else {
      setState(() {
        _paquetesFiltrados = _paquetes.where((paquete) {
          final id = paquete['id'].toString().toLowerCase();
          return id.contains(query);
        }).toList();
      });
    }
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
          'TipoEnvio': value['TipoEnvio'] ?? '',
        });
      });

      setState(() {
        _paquetes.clear();
        _paquetes.addAll(lista);
        _paquetesFiltrados = [...lista];
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _paquetesFiltrados = [];
      });
    }
  }

  Future<void> _cerrarSesion() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _mostrarAlertaDevolucion() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paquete con múltiples intentos'),
        content: const Text('Este paquete debe ser devuelto al proveedor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Paquetes'),
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _cerrarSesion,
            child: const Text(
              'Cerrar sesión',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Buscar por ID',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: _paquetesFiltrados.isEmpty
                      ? const Center(child: Text('No hay paquetes disponibles'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _paquetesFiltrados.length,
                          itemBuilder: (context, index) {
                            final paquete = _paquetesFiltrados[index];
                            final tipoEnvio = paquete['TipoEnvio'];
                            final bool esEspecial = tipoEnvio == 'HD0D' || tipoEnvio == 'HD1D';

                            return Card(
                              elevation: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('🧾 Orden: ${paquete['id']}',
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text('📍 Dirección: ${paquete['DireccionEntrega']}'),
                                    Text('👤 Destinatario: ${paquete['Destinatario']}'),
                                    Text('📦 Intentos: ${paquete['Intentos']}'),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (esEspecial)
                                          Container(
                                            margin: const EdgeInsets.only(right: 10),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.yellow[700],
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              tipoEnvio,
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ElevatedButton(
                                          onPressed: () async {
                                            final user = FirebaseAuth.instance.currentUser;
                                            if (user == null) return;

                                            final paqueteId = paquete['id'];
                                            final DatabaseReference paqueteRef = FirebaseDatabase.instance.ref(
                                              'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/$paqueteId',
                                            );

                                            final snapshot = await paqueteRef.get();

                                            // Convertimos 'Intentos' a int de forma segura
                                            final dynamic intentosRaw = snapshot.child('Intentos').value;
                                            final int intentos = intentosRaw is int
                                                ? intentosRaw
                                                : int.tryParse(intentosRaw.toString()) ?? 0;

                                            if (intentos >= 3) {
                                              _mostrarAlertaDevolucion();
                                              return;
                                            }

                                            final tnReference = snapshot.child('TnReference').value?.toString() ?? 'Sin referencia';
                                            final telefono = snapshot.child('Telefono').value?.toString() ?? '';

                                            if (!mounted) return;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => EntregaFallidaPage(
                                                  telefono: telefono,
                                                  tnReference: tnReference,
                                                  destinatario: paquete['Destinatario'],
                                                ),
                                              ),
                                            );
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
                                        ElevatedButton(
                                          onPressed: () async {
                                            final user = FirebaseAuth.instance.currentUser;
                                            if (user == null) return;

                                            final tnRef = FirebaseDatabase.instance.ref(
                                              'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/${paquete['id']}',
                                            );

                                            final tnSnapshot = await tnRef.get();
                                            final tnReference = tnSnapshot.child('TnReference').value?.toString() ?? 'Sin referencia';
                                            final telefono = tnSnapshot.child('Telefono').value?.toString() ?? '';

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PaqueteDetallePage(
                                                  id: paquete['id'],
                                                  telefono: telefono,
                                                  destinatario: paquete['Destinatario'],
                                                  tnReference: tnReference,
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
                ),
              ],
            ),
    );
  }
}
