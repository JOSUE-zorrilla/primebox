import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

import 'perfil_page.dart';
import 'paqueteDetallePage.dart';
import 'entrega_fallida_page.dart';
import 'login_page.dart'; // para globalNombre / globalUserId si los tienes
import 'dart:async';

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
  String? _estadoConexion;

  bool _procesandoConexion = false; // evita toques repetidos del botón

  late DatabaseReference _estadoConexionRef;
  StreamSubscription<DatabaseEvent>? _estadoConexionSub;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filtrarPaquetes);
    _escucharEstadoConexion();
    _cargarPaquetes();
  }

  @override
  void dispose() {
    _estadoConexionSub?.cancel();
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

  void _escucharEstadoConexion() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _estadoConexionRef = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/${user.uid}/EstadoConexion',
    );

    _estadoConexionSub = _estadoConexionRef.onValue.listen((event) {
      final estado = event.snapshot.value?.toString() ?? 'Desconectado';
      setState(() {
        _estadoConexion = estado;
      });
    });

    _verificarActivo(user.uid);
  }

  Future<void> _verificarActivo(String uid) async {
    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/$uid',
    );
    final snap = await ref.get();
    final activo = snap.child('Activo').value?.toString().toLowerCase() ?? 'no';

    if (activo != 'si' && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PerfilPage()),
      );
    }
  }

  // ---------------------------
  // Helpers de ubicación
  // ---------------------------
  Future<Position?> _obtenerPosicion() async {
    final messenger = ScaffoldMessenger.of(context);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Activa el GPS del dispositivo para continuar.')),
      );
      return null;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Permiso de ubicación denegado.')),
        );
        return null;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación denegado permanentemente. Habilítalo en Ajustes.')),
      );
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo obtener la ubicación: $e')),
      );
      return null;
    }
  }

  // ---------------------------
  // Alternar estado con webhooks
  // ---------------------------
  Future<void> _alternarEstadoConexion() async {
    if (_procesandoConexion) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _estadoConexion == null) return;

    final estabaConectado = _estadoConexion == 'Conectado';
    final messenger = ScaffoldMessenger.of(context);

    // Si está Conectado, pedir confirmación de desconexión
    if (estabaConectado) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar desconexión'),
          content: const Text('Solo desconéctese cuando ya no pueda continuar entregando paquetes'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    setState(() => _procesandoConexion = true);

    try {
      // 1) Obtener lat/long
      final pos = await _obtenerPosicion();
      if (pos == null) {
        setState(() => _procesandoConexion = false);
        return;
      }

// 2) Preparar datos
final fecha = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
final nombreDriver = (globalNombre?.toString().trim().isNotEmpty ?? false)
    ? globalNombre!
    : (user.displayName ?? 'SinNombre');
final idDriver = (globalUserId?.toString().trim().isNotEmpty ?? false)
    ? globalUserId!
    : user.uid;

// Campos comunes
final Map<String, String> base = {
  'Latitude': pos.latitude.toString(),
  'Longitude': pos.longitude.toString(),
  'NombreDriver': nombreDriver,
  'idDriver': idDriver,
};

// 3) Elegir webhook según estado ACTUAL
final uri = Uri.parse(
  estabaConectado
      ? 'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_gYV8nsDeYbePDL6qoTZHxp' // al desconectarse (confirmado)
      : 'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_8G2yAtEEFvpvxyRYQzQgcw',   // al conectarse
);

// ✨ Mismo formato de fecha, distinto nombre de campo según webhook
final Map<String, String> body = {
  ...base,
  if (estabaConectado) 'FechaFormateada': fecha,  // desconexión
  if (!estabaConectado) 'YYYYMMDDHHMMSS': fecha,  // conexión (mismo formato)
};



      // 4) Enviar webhook y esperar respuesta
      final res = await http.post(uri, body: body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // 5) Actualizar EstadoConexion DESPUÉS de respuesta
        final nuevoEstado = estabaConectado ? 'Desconectado' : 'Conectado';
        final conductorRef = FirebaseDatabase.instance.ref(
          'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/${user.uid}/EstadoConexion',
        );
        await conductorRef.set(nuevoEstado);

        setState(() {
          _estadoConexion = nuevoEstado; // refleja al instante (además del listener)
        });

        messenger.showSnackBar(
          SnackBar(content: Text('Estado actualizado a $nuevoEstado')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Error del webhook (${res.statusCode}): ${res.body}')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error al cambiar estado: $e')),
      );
    } finally {
      if (mounted) setState(() => _procesandoConexion = false);
    }
  }

  // ---------------------------
  // Helpers de conexión para acciones Aceptar/Rechazar
  // ---------------------------
  bool get _estaConectado => _estadoConexion == 'Conectado';

  bool _requerirConexion() {
    if (_estaConectado) return true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No estás conectado'),
        content: const Text('Debes conectarte para gestionar paquetes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    return false;
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
      builder: (context) => const AlertDialog(
        title: Text('Paquete con múltiples intentos'),
        content: Text('Este paquete debe ser devuelto al proveedor.'),
      ),
    );
  }

  Future<void> _procesarNotificacionWebhook({
    required String paqueteId,
    required String tnReference,
    required String notificarRp,
    required String userId,
  }) async {
    final now = DateTime.now();
    final fechaPush = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final fechaEstimada = DateFormat('yyyy-MM-dd HH:mm:ss').format(now.add(const Duration(hours: 8)));

    final webhookUrl = Uri.parse('https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_1ms7YSCLjYnYUQnJYPp2pp');

    final Map<String, String> data = {
      'Estatus': 'RP',
      'FechaEstimada': fechaEstimada,
      'FechaPush': fechaPush,
      'idGuiaLP': tnReference,
      'idGuiaPM': paqueteId,
    };

    if (notificarRp.toLowerCase() == 'si') {
      await http.post(webhookUrl, body: data);
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$userId/Paquetes/$paqueteId/NotificarRp',
      );
      await ref.remove();
    } else {
      final refCheck = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/PushLRP/$paqueteId',
      );
      final exists = await refCheck.get();
      if (!exists.exists) {
        await http.post(webhookUrl, body: data);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool conectado = _estaConectado;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Paquetes'),
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _cerrarSesion,
            child: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
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
                if (_estadoConexion != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: ElevatedButton(
                      onPressed: _procesandoConexion ? null : _alternarEstadoConexion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: conectado ? Colors.grey[400] : Colors.green,
                      ),
                      child: Text(
                        _procesandoConexion
                            ? (conectado ? 'Desconectando...' : 'Conectando...')
                            : (conectado ? 'Desconectarse' : 'Conectarse'),
                        style: const TextStyle(color: Colors.black),
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
                                    Text(
                                      '🧾 Orden: ${paquete['id']}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
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
                                        // -------- Botón Rechazar --------
                                        ElevatedButton(
                                          onPressed: () async {
                                            if (!_requerirConexion()) return;

                                            final user = FirebaseAuth.instance.currentUser;
                                            if (user == null) return;

                                            final paqueteId = paquete['id'];
                                            final paqueteRef = FirebaseDatabase.instance.ref(
                                              'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/$paqueteId',
                                            );

                                            final snapshot = await paqueteRef.get();
                                            final tnReference = snapshot.child('TnReference').value?.toString() ?? '';
                                            final notificarRp = snapshot.child('NotificarRp').value?.toString() ?? '';

                                            await _procesarNotificacionWebhook(
                                              paqueteId: paqueteId,
                                              tnReference: tnReference,
                                              notificarRp: notificarRp,
                                              userId: user.uid,
                                            );

                                            final intentosRaw = snapshot.child('Intentos').value;
                                            final int intentos = intentosRaw is int
                                                ? intentosRaw
                                                : int.tryParse(intentosRaw.toString()) ?? 0;

                                            if (intentos >= 3) {
                                              _mostrarAlertaDevolucion();
                                              return;
                                            }

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
                                        // -------- Botón Aceptar --------
                                        ElevatedButton(
                                          onPressed: () async {
                                            if (!_requerirConexion()) return;

                                            final user = FirebaseAuth.instance.currentUser;
                                            if (user == null) return;

                                            final tnRef = FirebaseDatabase.instance.ref(
                                              'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/${paquete['id']}',
                                            );

                                            final tnSnapshot = await tnRef.get();
                                            final tnReference = tnSnapshot.child('TnReference').value?.toString() ?? 'Sin referencia';
                                            final telefono = tnSnapshot.child('Telefono').value?.toString() ?? '';

                                            if (!mounted) return;
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
