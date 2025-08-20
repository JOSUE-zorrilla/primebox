import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

import 'perfil_page.dart';
import 'paqueteDetallePage.dart';
import 'entrega_fallida_page.dart';
import 'login_page.dart'; // para globalNombre / globalUserId si los tienes

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
  bool _procesandoConexion = false;

  // Filtro (desde el encabezado)
  String _filtroTipo = 'Todos'; // Todos | HD0D | HD1D

  late DatabaseReference _estadoConexionRef;
  StreamSubscription<DatabaseEvent>? _estadoConexionSub;

  // NUEVO: suscripción en tiempo real a Paquetes
  StreamSubscription<DatabaseEvent>? _paquetesSub;
  DatabaseReference? _paquetesRef;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filtrarPaquetes);
    _escucharEstadoConexion();
    _suscribirsePaquetes(); // ahora en tiempo real
  }

  @override
  void dispose() {
    _estadoConexionSub?.cancel();
    _paquetesSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // =============== Utilidades de tiempo ===============
  String _fmt(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);

  // =============== Filtros ===============
  void _filtrarPaquetes() {
    final query = _searchController.text.toLowerCase();
    List<Map<String, dynamic>> base = [..._paquetes];

    if (_filtroTipo != 'Todos') {
      base = base.where((p) => (p['TipoEnvio'] ?? '') == _filtroTipo).toList();
    }

    if (query.isEmpty) {
      setState(() => _paquetesFiltrados = base);
    } else {
      setState(() {
        _paquetesFiltrados = base.where((paquete) {
          final id = paquete['id'].toString().toLowerCase();
          final direccion = (paquete['DireccionEntrega'] ?? '').toString().toLowerCase();
          return id.contains(query) || direccion.contains(query);
        }).toList();
      });
    }
  }

  // =============== Estado conexión ===============
  void _escucharEstadoConexion() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _estadoConexionRef = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/${user.uid}/EstadoConexion',
    );

    _estadoConexionSub = _estadoConexionRef.onValue.listen((event) {
      final estado = event.snapshot.value?.toString() ?? 'Desconectado';
      if (mounted) {
        setState(() {
          _estadoConexion = estado;
        });
      }
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

  // =============== Ubicación ===============
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

  // =============== Alternar Conexión ===============
  Future<void> _alternarEstadoConexion() async {
    if (_procesandoConexion) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _estadoConexion == null) return;

    final estabaConectado = _estadoConexion == 'Conectado';
    final messenger = ScaffoldMessenger.of(context);

    if (estabaConectado) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar desconexión'),
          content: const Text('Solo desconéctate cuando ya no puedas continuar entregando paquetes.'),
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
      final pos = await _obtenerPosicion();
      if (pos == null) {
        setState(() => _procesandoConexion = false);
        return;
      }

      final fecha = _fmt(DateTime.now());
      final nombreDriver = (globalNombre?.toString().trim().isNotEmpty ?? false)
          ? globalNombre!
          : (user.displayName ?? 'SinNombre');
      final idDriver = (globalUserId?.toString().trim().isNotEmpty ?? false)
          ? globalUserId!
          : user.uid;

      final Map<String, String> base = {
        'Latitude': pos.latitude.toString(),
        'Longitude': pos.longitude.toString(),
        'NombreDriver': nombreDriver,
        'idDriver': idDriver,
      };

      final uri = Uri.parse(
        estabaConectado
            ? 'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_gYV8nsDeYbePDL6qoTZHxp'
            : 'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_8G2yAtEEFvpvxyRYQzQgcw',
      );

      final Map<String, String> body = {
        ...base,
        if (estabaConectado) 'FechaFormateada': fecha,
        if (!estabaConectado) 'YYYYMMDDHHMMSS': fecha,
      };

      final res = await http.post(uri, body: body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final nuevoEstado = estabaConectado ? 'Desconectado' : 'Conectado';
        final conductorRef = FirebaseDatabase.instance.ref(
          'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/${user.uid}/EstadoConexion',
        );
        await conductorRef.set(nuevoEstado);
        if (mounted) {
          setState(() {
            _estadoConexion = nuevoEstado;
          });
        }
        messenger.showSnackBar(
          SnackBar(content: Text('Estado actualizado a $nuevoEstado')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Error del webhook (${res.statusCode}): ${res.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cambiar estado: $e')),
      );
    } finally {
      if (mounted) setState(() => _procesandoConexion = false);
    }
  }

  // =============== Requerir conexión ===============
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

  // =============== Suscripción en tiempo real a Paquetes ===============
  Future<void> _suscribirsePaquetes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _paquetesRef = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes',
    );

    // Cancelar suscripción previa si existe
    await _paquetesSub?.cancel();

    // Primer estado: loading true hasta recibir el primer snapshot
    if (mounted) setState(() => _loading = true);

    _paquetesSub = _paquetesRef!.onValue.listen((DatabaseEvent event) {
      final snap = event.snapshot;

      if (!snap.exists || snap.value == null) {
        // No hay paquetes
        _paquetes
          ..clear();
        _paquetesFiltrados = [];
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
        return;
      }

      final value = snap.value;

      // Esperamos un Map<dynamic, dynamic> { idPaquete: { ...datos } }
      if (value is Map) {
        final List<Map<String, dynamic>> lista = [];

        value.forEach((key, dynamic paquete) {
          if (paquete is Map) {
            lista.add({
              'id': key.toString(),
              'DireccionEntrega': paquete['DireccionEntrega'] ?? '',
              'Destinatario': paquete['Destinatario'] ?? '',
              'Intentos': paquete['Intentos'] ?? 0,
              'TipoEnvio': paquete['TipoEnvio'] ?? '',
            });
          }
        });

        // Orden opcional por id o por algo más si lo necesitas
        // lista.sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));

        _paquetes
          ..clear()
          ..addAll(lista);

        // Reaplicar filtros y búsqueda
        _aplicarFiltrosEnMemoria();

        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      } else {
        // Estructura inesperada
        _paquetes
          ..clear();
        _paquetesFiltrados = [];
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    }, onError: (e) {
      // En caso de error en el stream, mostramos estado vacío pero dejamos el listener activo
      _paquetes
        ..clear();
      _paquetesFiltrados = [];
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al escuchar paquetes: $e')),
        );
      }
    });
  }

  void _aplicarFiltrosEnMemoria() {
    // Aplica filtro por tipo y búsqueda actual sin pedir de nuevo
    final query = _searchController.text.toLowerCase();
    List<Map<String, dynamic>> base = [..._paquetes];

    if (_filtroTipo != 'Todos') {
      base = base.where((p) => (p['TipoEnvio'] ?? '') == _filtroTipo).toList();
    }

    if (query.isEmpty) {
      _paquetesFiltrados = base;
    } else {
      _paquetesFiltrados = base.where((paquete) {
        final id = paquete['id'].toString().toLowerCase();
        final direccion = (paquete['DireccionEntrega'] ?? '').toString().toLowerCase();
        return id.contains(query) || direccion.contains(query);
      }).toList();
    }
  }

  // =============== Cerrar sesión ===============
  Future<void> _cerrarSesion() async {
    await FirebaseAuth.instance.signOut();
    // Cancelar suscripciones por seguridad
    await _paquetesSub?.cancel();
    await _estadoConexionSub?.cancel();

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

  // =============== Webhook RP (compartido) ===============
  Future<void> _enviarWebhookRP({
    required String paqueteId,
    required String tnReference,
  }) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final estimada = DateTime.fromMillisecondsSinceEpoch(nowMs + 28800000); // +8h en ms

    final url = Uri.parse('https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_woPgim5JFu1wFjHR21cHnK');

    final body = <String, String>{
      'Estatus': 'RP',
      'FechaEstimada': _fmt(estimada),
      'FechaPush': _fmt(now),
      'idGuiaLP': tnReference,
      'idGuiaPM': paqueteId,
    };

    await http.post(url, body: body);
  }

  Future<void> _limpiarNotificarRp({
    required String userId,
    required String paqueteId,
  }) async {
    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$userId/Paquetes/$paqueteId/NotificarRp',
    );
    await ref.set(''); // dejarlo vacío (no eliminar)
  }

  // =============== UI ===============
  @override
  Widget build(BuildContext context) {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Color(0xFF1955CC),         // mismo color del encabezado
      statusBarIconBrightness: Brightness.light, // íconos blancos (Android)
      statusBarBrightness: Brightness.dark,      // íconos blancos (iOS)
    );

    final bool conectado = _estaConectado;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F3F7),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Encabezado azul
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1955CC), // color solicitado
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fila superior: menú + botón conectar/desconectar
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {},
                                icon: const Icon(Icons.menu, color: Colors.white),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _procesandoConexion ? null : _alternarEstadoConexion,
                                style: TextButton.styleFrom(
                                  backgroundColor:
                                      conectado ? Colors.white : const Color(0xFF2E7D32),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(
                                  _procesandoConexion
                                      ? (conectado ? 'Desconectando...' : 'Conectando...')
                                      : (conectado ? 'Desconectarme' : 'Conectarme'),
                                  style: TextStyle(
                                    color: conectado ? const Color(0xFF1955CC) : Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sigue tu paquete!',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ingresa el número de guía o palabra clave para\nencontrar la información que necesitas.',
                            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.2),
                          ),
                          const SizedBox(height: 12),

                          // Buscador (blanco) + 2 cuadritos en la MISMA FILA
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style: const TextStyle(color: Colors.black87),
                                  decoration: InputDecoration(
                                    hintText: 'Buscar',
                                    hintStyle: const TextStyle(color: Colors.black38),
                                    prefixIcon: const Icon(Icons.search, color: Colors.black45),
                                    filled: true,
                                    fillColor: Colors.white, // fondo blanco
                                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _SquareIconButton(
                                icon: Icons.tune,
                                onTap: _abrirFiltroTipo,
                              ),
                              const SizedBox(width: 10),
                              _SquareIconButton(
                                icon: Icons.grid_view_rounded,
                                onTap: () {}, // decorativo
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // “Píldora” Orden Fast
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Text(
                            'Orden Fast',
                            style: TextStyle(color: Color(0xFF1A3365), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),

                    // Lista de paquetes
                    Expanded(
                      child: _paquetesFiltrados.isEmpty
                          ? const Center(child: Text('No hay paquetes disponibles'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                              itemCount: _paquetesFiltrados.length,
                              itemBuilder: (context, index) {
                                final paquete = _paquetesFiltrados[index];
                                final tipoEnvio = paquete['TipoEnvio'];
                                final bool esEspecial = tipoEnvio == 'HD0D' || tipoEnvio == 'HD1D';

                                return _PaqueteCard(
                                  id: paquete['id'],
                                  direccion: paquete['DireccionEntrega'],
                                  destinatario: paquete['Destinatario'],
                                  intentos: paquete['Intentos'],
                                  tipoEnvio: tipoEnvio,
                                  esEspecial: esEspecial,
                                  onEntregar: () async {
                                    if (!_requerirConexion()) return;

                                    final user = FirebaseAuth.instance.currentUser;
                                    if (user == null) return;

                                    final paqueteRef = FirebaseDatabase.instance.ref(
                                      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/${paquete['id']}',
                                    );

                                    final snap = await paqueteRef.get();
                                    final tnReference =
                                        snap.child('TnReference').value?.toString() ?? 'Sin referencia';
                                    final telefono = snap.child('Telefono').value?.toString() ?? '';
                                    final notificarRp = snap.child('NotificarRp').value?.toString() ?? '';

                                    // Si NotificarRp == "Si" -> enviar webhook y limpiar campo
                                    if (notificarRp.toLowerCase() == 'si') {
                                      try {
                                        await _enviarWebhookRP(
                                          paqueteId: paquete['id'],
                                          tnReference: tnReference,
                                        );
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error al enviar webhook de entrega: $e')),
                                          );
                                        }
                                      } finally {
                                        await _limpiarNotificarRp(
                                          userId: user.uid,
                                          paqueteId: paquete['id'],
                                        );
                                      }
                                    }

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
                                  onRechazar: () async {
                                    if (!_requerirConexion()) return;

                                    final user = FirebaseAuth.instance.currentUser;
                                    if (user == null) return;

                                    final paqueteId = paquete['id'];
                                    final paqueteRef = FirebaseDatabase.instance.ref(
                                      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes/$paqueteId',
                                    );

                                    final snapshot = await paqueteRef.get();
                                    final tnReference =
                                        snapshot.child('TnReference').value?.toString() ?? '';
                                    final telefono =
                                        snapshot.child('Telefono').value?.toString() ?? '';

                                    // Rechazar -> enviar MISMA info al MISMO webhook y limpiar
                                    try {
                                      await _enviarWebhookRP(
                                        paqueteId: paqueteId,
                                        tnReference: tnReference,
                                      );
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error al enviar webhook de rechazo: $e')),
                                        );
                                      }
                                    } finally {
                                      await _limpiarNotificarRp(
                                        userId: user.uid,
                                        paqueteId: paqueteId,
                                      );
                                    }

                                    final intentosRaw = snapshot.child('Intentos').value;
                                    final int intentos = intentosRaw is int
                                        ? intentosRaw
                                        : int.tryParse(intentosRaw.toString()) ?? 0;

                                    if (intentos >= 3) {
                                      _mostrarAlertaDevolucion();
                                      return;
                                    }

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
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _cerrarSesion,
          child: const Icon(Icons.logout),
        ),
      ),
    );
  }

  // Bottom sheet de filtro
  void _abrirFiltroTipo() async {
    final sel = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('Filtrar por tipo de envío',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _OpcionFiltro(
                titulo: 'Todos',
                seleccionado: _filtroTipo == 'Todos',
                onTap: () => Navigator.pop(context, 'Todos'),
              ),
              _OpcionFiltro(
                titulo: 'HD0D',
                seleccionado: _filtroTipo == 'HD0D',
                onTap: () => Navigator.pop(context, 'HD0D'),
              ),
              _OpcionFiltro(
                titulo: 'HD1D',
                seleccionado: _filtroTipo == 'HD1D',
                onTap: () => Navigator.pop(context, 'HD1D'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (sel != null && sel != _filtroTipo) {
      setState(() {
        _filtroTipo = sel;
      });
      _filtrarPaquetes();
    }
  }
}

// ===== Widgets de apoyo =====
class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SquareIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A6AE8), // cuadrito azul más claro
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _OpcionFiltro extends StatelessWidget {
  final String titulo;
  final bool seleccionado;
  final VoidCallback onTap;
  const _OpcionFiltro({
    required this.titulo,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(titulo),
      trailing: seleccionado ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: onTap,
    );
  }
}

class _PaqueteCard extends StatelessWidget {
  final String id;
  final String direccion;
  final String destinatario;
  final int intentos;
  final String tipoEnvio;
  final bool esEspecial;
  final VoidCallback onEntregar;
  final VoidCallback onRechazar;

  const _PaqueteCard({
    super.key,
    required this.id,
    required this.direccion,
    required this.destinatario,
    required this.intentos,
    required this.tipoEnvio,
    required this.esEspecial,
    required this.onEntregar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  esEspecial ? Icons.bolt : Icons.inventory_2_outlined,
                  color: esEspecial ? Colors.amber[700] : const Color(0xFF1A3365),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '#$id',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (esEspecial)
                  Container(
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
              ],
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  const TextSpan(text: 'Dirección\n', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: direccion),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  const TextSpan(text: 'Propietario\n', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: destinatario),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text('Intentos: $intentos'),
            const SizedBox(height: 12),

            // Acciones: Entregado (expande) + rojito
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onEntregar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2F63D3),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Entregado',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: onRechazar,
                  borderRadius: BorderRadius.circular(10),
                  child: Ink(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(Icons.error_outline, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
