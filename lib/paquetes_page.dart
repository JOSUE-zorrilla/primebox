import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'recolectados_centros_page.dart';

import 'escanear_paquete_page.dart';
import 'perfil_page.dart';
import 'paqueteDetallePage.dart';
import 'entrega_fallida_page.dart';
import 'login_page.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'recolectar_tiendas_page.dart';
import 'recoger_almacen_page.dart';
import 'devoluciones_scan_page.dart';

// NUEVO: mostrar QR propio y pantalla de delegar
import 'package:qr_flutter/qr_flutter.dart';
import 'delegar_paquete_page.dart';

// String? globalNombre;
// String? globalUserId;

class PaquetesPage extends StatefulWidget {
  const PaquetesPage({super.key});

  @override
  State<PaquetesPage> createState() => _PaquetesPageState();
}

class _PaquetesPageState extends State<PaquetesPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<Map<String, dynamic>> _paquetes = [];
  List<Map<String, dynamic>> _paquetesFiltrados = [];
  final TextEditingController _searchController = TextEditingController();
  int get _cantidadPaquetes => _paquetesFiltrados.length;

  bool _loading = true;
  String? _estadoConexion;
  bool _procesandoConexion = false;

  String _filtroTipo = 'Todos'; // Todos | HD0D | HD1D

  String _claveDireccion(Map<String, dynamic> p) {
    return (p['DireccionEntrega'] ?? '').toString().toLowerCase().trim();
  }

  late DatabaseReference _estadoConexionRef;
  StreamSubscription<DatabaseEvent>? _estadoConexionSub;
  StreamSubscription<DatabaseEvent>? _paquetesSub;
  DatabaseReference? _paquetesRef;

  String _driverNombre = '';
  String _driverFoto = '';
  bool _estaActivo = false;
  DatabaseReference? _conductorRef;
  StreamSubscription<DatabaseEvent>? _conductorSub;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filtrarPaquetes);
    _escucharEstadoConexion();
    _suscribirsePaquetes();
    _escucharPerfilConductor();
  }

  @override
  void dispose() {
    _estadoConexionSub?.cancel();
    _paquetesSub?.cancel();
    _conductorSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _escucharPerfilConductor() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _conductorRef = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/${user.uid}',
    );

    _conductorSub = _conductorRef!.onValue.listen((event) {
      final snap = event.snapshot;
      final nombre = snap.child('Nombre').value?.toString() ?? '';
      final foto = snap.child('Foto').value?.toString() ?? '';
      final activoStr =
          snap.child('Activo').value?.toString().toLowerCase() ?? 'no';
      if (mounted) {
        setState(() {
          _driverNombre = nombre;
          _driverFoto = foto;
          _estaActivo = (activoStr == 'si');
        });
      }
    });
  }

  void _irARecolectarTiendas() {
    if (!_requerirDesconexion()) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const RecolectarTiendasPage()));
  }

  void _irARecogerEnAlmacen() {
    if (!_requerirDesconexion()) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const RecogerAlmacenPage()));
  }

  void _mostrarMiQR() {
    final user = FirebaseAuth.instance.currentUser;
    final String data = (globalUserId?.trim().isNotEmpty ?? false)
        ? globalUserId!.trim()
        : (user?.uid ?? 'SIN_UID');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mi código (para delegar)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 220,
              gapless: true,
            ),
            const SizedBox(height: 2),
            SelectableText(
              data,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Muestra este QR para que otro conductor te delegue un paquete.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);

  void _filtrarPaquetes() {
    final query = _searchController.text.toLowerCase();
    List<Map<String, dynamic>> base = [..._paquetes];

    if (_filtroTipo != 'Todos') {
      base =
          base.where((p) => (p['TipoEnvio'] ?? '') == _filtroTipo).toList();
    }

    if (query.isEmpty) {
      setState(() => _paquetesFiltrados = base);
    } else {
      setState(() {
        _paquetesFiltrados = base.where((paquete) {
          final id = paquete['id'].toString().toLowerCase();
          final direccion =
              (paquete['DireccionEntrega'] ?? '').toString().toLowerCase();
          return id.contains(query) || direccion.contains(query);
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
      if (mounted) setState(() => _estadoConexion = estado);
    });

    _verificarActivo(user.uid);
  }

  Future<void> _verificarActivo(String uid) async {
    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/$uid',
    );
    final snap = await ref.get();
    final activoStr =
        snap.child('Activo').value?.toString().toLowerCase() ?? 'no';
    if (mounted) setState(() => _estaActivo = (activoStr == 'si'));
  }

  Future<Position?> _obtenerPosicion() async {
    final messenger = ScaffoldMessenger.of(context);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Activa el GPS del dispositivo para continuar.')));
      return null;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado.')));
        return null;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Permiso de ubicación denegado permanentemente. Habilítalo en Ajustes.')));
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('No se pudo obtener la ubicación: $e')));
      return null;
    }
  }

  // ====== entrega en segundo plano ======
  Future<void> _procesarEntregaPaquete(String userId, Map paquete) async {
    try {
      final paqueteRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$userId/Paquetes/${paquete['id']}',
      );

      final snap = await paqueteRef.get();
      final tnReference =
          snap.child('TnReference').value?.toString() ?? 'Sin referencia';
      final notificarRp = snap.child('NotificarRp').value?.toString() ?? '';

      if (notificarRp.toLowerCase() == 'si') {
        await _enviarWebhookRP(
          paqueteId: paquete['id'],
          tnReference: tnReference,
        );
        await _limpiarNotificarRp(userId: userId, paqueteId: paquete['id']);
      }
    } catch (_) {}
  }

  // ====== rechazo en segundo plano ======
  Future<void> _procesarRechazoPaquete(String userId, String paqueteId) async {
    try {
      final paqueteRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/$userId/Paquetes/$paqueteId',
      );

      final snapshot = await paqueteRef.get();
      final tnReference = snapshot.child('TnReference').value?.toString() ?? '';

      await _enviarWebhookRP(paqueteId: paqueteId, tnReference: tnReference);
      await _limpiarNotificarRp(userId: userId, paqueteId: paqueteId);

      final intentosRaw = snapshot.child('Intentos').value;
      final int intentos = intentosRaw is int
          ? intentosRaw
          : int.tryParse(intentosRaw.toString()) ?? 0;

      if (intentos >= 3 && mounted) {
        _mostrarAlertaDevolucion();
      }
    } catch (_) {}
  }

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
              child: const Text('Cerrar'))
        ],
      ),
    );
    return false;
  }

  bool _requerirDesconexion() {
    if (!_estaConectado) return true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estás conectado'),
        content: const Text(
            'Debes desconectarte para realizar la delegación de paquetes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'))
        ],
      ),
    );
    return false;
  }

  Future<void> _suscribirsePaquetes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _paquetesRef = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/RepartoDriver/${user.uid}/Paquetes',
    );

    await _paquetesSub?.cancel();
    if (mounted) setState(() => _loading = true);

    _paquetesSub = _paquetesRef!.onValue.listen((DatabaseEvent event) {
      final snap = event.snapshot;

      if (!snap.exists || snap.value == null) {
        _paquetes..clear();
        _paquetesFiltrados = [];
        if (mounted) setState(() => _loading = false);
        return;
      }

      final value = snap.value;
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
              'Telefono': paquete['Telefono'] ?? '',
              'TnReference': paquete['TnReference'] ?? '',
            });
          }
        });

        lista.sort((a, b) => _claveDireccion(a).compareTo(_claveDireccion(b)));

        _paquetes..clear()..addAll(lista);
        _aplicarFiltrosEnMemoria();
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _aplicarFiltrosEnMemoria() {
    final query = _searchController.text.toLowerCase();
    List<Map<String, dynamic>> base = [..._paquetes];

    if (_filtroTipo != 'Todos') {
      base =
          base.where((p) => (p['TipoEnvio'] ?? '') == _filtroTipo).toList();
    }

    if (query.isEmpty) {
      _paquetesFiltrados = base;
    } else {
      _paquetesFiltrados = base.where((paquete) {
        final id = paquete['id'].toString().toLowerCase();
        final direccion =
            (paquete['DireccionEntrega'] ?? '').toString().toLowerCase();
        return id.contains(query) || direccion.contains(query);
      }).toList();
    }
  }

  Future<void> _cerrarSesion() async {
    await FirebaseAuth.instance.signOut();
    await _paquetesSub?.cancel();
    await _estadoConexionSub?.cancel();
    await _conductorSub?.cancel();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
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

  Future<void> _enviarWebhookRP({
    required String paqueteId,
    required String tnReference,
  }) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final estimada = DateTime.fromMillisecondsSinceEpoch(nowMs + 28800000);

    final url = Uri.parse(
        'https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_woPgim5JFu1wFjHR21cHnK');

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
    await ref.set('');
  }

  // ======== Drawer ========
  Drawer _buildDrawer(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final nombreFallback =
        (globalNombre?.trim().isNotEmpty ?? false)
            ? globalNombre!
            : (user?.displayName ?? 'Usuario');
    final fotoAuth = user?.photoURL ?? '';

    Widget header = InkWell(
      onTap: () async {
        Navigator.pop(context);
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PerfilPage()),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: ((_driverFoto.trim().isNotEmpty
                          ? _driverFoto.trim()
                          : fotoAuth)
                      .isNotEmpty)
                  ? NetworkImage(_driverFoto.trim().isNotEmpty
                      ? _driverFoto.trim()
                      : fotoAuth)
                  : null,
              child: ((_driverFoto.trim().isNotEmpty
                          ? _driverFoto.trim()
                          : fotoAuth)
                      .isEmpty)
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
              backgroundColor: const Color(0xFF2A6AE8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Perfil',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text(
                    _driverNombre.trim().isNotEmpty
                        ? _driverNombre.trim()
                        : nombreFallback,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Container(height: 1, color: Colors.black12),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    ListTile item({
      required IconData icon,
      required String text,
      Color? iconColor,
      VoidCallback? onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: iconColor ?? const Color(0xFF1A3365)),
        title: Text(text),
        onTap: () async {
          Navigator.pop(context);
          if (onTap != null) onTap();
        },
      );
    }

    return Drawer(
      width: 290,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            header,
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  item(
                    icon: Icons.store_mall_directory_outlined,
                    text: 'Recolectar en tienda',
                    onTap: _irARecolectarTiendas,
                  ),
                  item(
                    icon: Icons.group_add_outlined,
                    text: 'Delegar paquete',
                    onTap: () async {
                      if (!_requerirDesconexion()) return;
                      await Navigator.push<String?>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DelegarPaquetePage()),
                      );
                    },
                  ),
                  item(
                    icon: Icons.inventory_2_outlined,
                    text: 'Paquetes recolectados',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RecolectadosCentrosPage()),
                      );
                    },
                  ),
                  item(
                    icon: Icons.local_shipping_outlined,
                    text: 'Recoger paquete en almacén',
                    onTap: _irARecogerEnAlmacen,
                  ),
                  item(
                    icon: Icons.assignment_return_outlined,
                    text: 'Devoluciones',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DevolucionesScanPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading:
                  const Icon(Icons.logout, color: Color(0xFFE53935)),
              title: const Text(
                'Salir de la app',
                style: TextStyle(
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.w600),
              ),
              onTap: _cerrarSesion,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Color(0xFF1955CC),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    );

    final bool conectado = _estaConectado;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildDrawer(context),
        backgroundColor: const Color(0xFFF2F3F7),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // encabezado azul
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1955CC),
                        borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                                icon: const Icon(Icons.menu,
                                    color: Colors.white),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _procesandoConexion
                                    ? null
                                    : _alternarEstadoConexion,
                                style: TextButton.styleFrom(
                                  backgroundColor: conectado
                                      ? Colors.white
                                      : const Color(0xFF2E7D32),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                                child: Text(
                                  _procesandoConexion
                                      ? (conectado
                                          ? 'Desconectando...'
                                          : 'Conectando...')
                                      : (conectado
                                          ? 'Desconectarme'
                                          : 'Conectarme'),
                                  style: TextStyle(
                                    color: conectado
                                        ? const Color(0xFF1955CC)
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sigue tu paquete!',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ingresa el número de guía o palabra clave...',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style:
                                      const TextStyle(color: Colors.black87),
                                  decoration: InputDecoration(
                                    hintText: 'Buscar',
                                    hintStyle: const TextStyle(
                                        color: Colors.black38),
                                    prefixIcon: const Icon(Icons.search,
                                        color: Colors.black45),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                             _SquareIconButton(
                              icon: Icons.qr_code, // este muestra tu propio QR
                              onTap: _mostrarMiQR,
                            ),
                            const SizedBox(width: 10),
                            _SquareIconButton(
                              icon: Icons.qr_code_scanner, // este abre el escáner
                              onTap: () async {
                                if (!_requerirConexion()) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const EscanearPaquetePage()),
                                );
                              },
                            ),

                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: Text(
                            'Número de paquetes: ${_estaActivo ? _cantidadPaquetes : 0}',
                            style: const TextStyle(
                                color: Color(0xFF1A3365),
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: !_estaActivo
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  'Revise que todos sus documentos estén completos...',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Color(0xFFE53935),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            )
                          : (_paquetesFiltrados.isEmpty
                              ? const Center(
                                  child:
                                      Text('No hay paquetes disponibles'))
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 12, 12, 24),
                                  itemCount: _paquetesFiltrados.length,
                                  itemBuilder: (context, index) {
                                    final paquete =
                                        _paquetesFiltrados[index];
                                    final tipoEnvio = paquete['TipoEnvio'];
                                    final bool esEspecial =
                                        tipoEnvio == 'HD0D' ||
                                            tipoEnvio == 'HD1D';

                                    return _PaqueteCard(
                                      id: paquete['id'],
                                      direccion:
                                          paquete['DireccionEntrega'],
                                      destinatario: paquete['Destinatario'],
                                      intentos: paquete['Intentos'],
                                      tipoEnvio: tipoEnvio,
                                      esEspecial: esEspecial,
                                      onEntregar: () async {
                                        if (!_requerirConexion()) return;
                                        final user = FirebaseAuth
                                            .instance.currentUser;
                                        if (user == null) return;

                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                PaqueteDetallePage(
                                              id: paquete['id'],
                                              telefono: paquete['Telefono'],
                                              destinatario:
                                                  paquete['Destinatario'],
                                              tnReference:
                                                  paquete['TnReference'],
                                            ),
                                          ),
                                        );

                                        unawaited(_procesarEntregaPaquete(
                                            user.uid, paquete));
                                      },
                                      onRechazar: () async {
                                        if (!_requerirConexion()) return;
                                        final user = FirebaseAuth
                                            .instance.currentUser;
                                        if (user == null) return;

                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                EntregaFallidaPage(
                                              telefono: paquete['Telefono'],
                                              tnReference:
                                                  paquete['TnReference'],
                                              destinatario:
                                                  paquete['Destinatario'],
                                              paqueteId: paquete['id'],
                                            ),
                                          ),
                                        );

                                        unawaited(_procesarRechazoPaquete(
                                            user.uid, paquete['id']));
                                      },
                                    );
                                  },
                                )),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ======= NUEVO: webhook al conectarse =======
  Future<void> _enviarWebhookConexion({
    required double lat,
    required double lng,
  }) async {
    final url = Uri.parse('https://appprocesswebhook-l2fqkwkpiq-uc.a.run.app/ccp_8G2yAtEEFvpvxyRYQzQgcw');

    final body = <String, String>{
      'Latitude': lat.toString(),
      'Longitude': lng.toString(),
      'NombreDriver': (globalNombre ?? '').trim(),
      'YYYYMMDDHHMMSS': _fmt(DateTime.now()), // yyyy-MM-dd HH:mm:ss
      'idDriver': (globalUserId ?? '').trim(),
    };

    try {
      await http.post(url, body: body);
    } catch (_) {
      // Silencioso para no romper el flujo de conexión
    }
  }

  Future<void> _alternarEstadoConexion() async {
    if (_procesandoConexion) return;

    final messenger = ScaffoldMessenger.of(context);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Sesión inválida. Inicia sesión nuevamente.'),
      ));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
      return;
    }

    setState(() => _procesandoConexion = true);

    try {
      final conductoresBase =
          'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/${user.uid}';

      if (_estaConectado) {
        // --- DESConectar ---
        await FirebaseDatabase.instance
            .ref('$conductoresBase/EstadoConexion')
            .set('Desconectado');

        await FirebaseDatabase.instance
            .ref('$conductoresBase/UltimaDesconexion')
            .set(_fmt(DateTime.now()));

        messenger.showSnackBar(const SnackBar(
          content: Text('Te has desconectado.'),
        ));
      } else {
        // --- Conectar ---
        // 1) Validar que esté activo
        if (!_estaActivo) {
          messenger.showSnackBar(const SnackBar(
            content: Text(
              'No puedes conectarte: tu perfil no está activo.\n'
              'Revisa que tus documentos estén completos.',
            ),
          ));
          return;
        }

        // 2) Obtener ubicación
        final pos = await _obtenerPosicion();
        if (pos == null) {
          // _obtenerPosicion ya muestra un SnackBar específico
          return;
        }

        // 3) Escribir estado y metadata de conexión
        await FirebaseDatabase.instance.ref(conductoresBase).update({
          'EstadoConexion': 'Conectado',
          'UltimaConexion': _fmt(DateTime.now()),
          'Lat': pos.latitude,
          'Lng': pos.longitude,
          'Precision': pos.accuracy,
        });

        // 4) NUEVO: enviar webhook con datos de conexión
        await _enviarWebhookConexion(lat: pos.latitude, lng: pos.longitude);

        messenger.showSnackBar(const SnackBar(
          content: Text('Conectado: ya puedes gestionar paquetes.'),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error al cambiar estado: $e')),
      );
    } finally {
      if (mounted) setState(() => _procesandoConexion = false);
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
      color: const Color(0xFF2A6AE8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(icon, color: Colors.white), // ← ahora usa el que se le pase
          ),
        ),
      ),
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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Icon(
                esEspecial ? Icons.bolt : Icons.inventory_2_outlined,
                color: esEspecial
                    ? Colors.amber[700]
                    : const Color(0xFF1A3365),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('#$id',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              if (esEspecial)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.yellow[700],
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(tipoEnvio,
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: const [
            TextSpan(
                text: 'Dirección',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ])),
          Text(direccion),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: const [
            TextSpan(
                text: 'Propietario',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ])),
          Text(destinatario),
          const SizedBox(height: 4),
          Text('Intentos: $intentos'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onEntregar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2F63D3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Entregado',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
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
                      borderRadius: BorderRadius.circular(10)),
                  child: const Center(
                      child:
                          Icon(Icons.error_outline, color: Colors.white)),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
