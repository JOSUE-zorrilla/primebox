import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// donde están globalUserId / globalNombre / globalIdCiudad
import 'login_page.dart';

class HistorialEntregasPage extends StatefulWidget {
  const HistorialEntregasPage({super.key});

  @override
  State<HistorialEntregasPage> createState() => _HistorialEntregasPageState();
}

class _HistorialEntregasPageState extends State<HistorialEntregasPage> {
  bool _loading = true;
  String? _error;
  final List<Map<String, dynamic>> _registros = [];

  // fecha seleccionada (por defecto: hoy)
  late DateTime _selectedDate;

  // para armar la clave de la fecha en la DB: 2025-11-24
  String get _fechaClaveDb =>
      DateFormat('yyyy-MM-dd').format(_selectedDate);

  // para mostrar en la UI: 24/11/2025
  String get _fechaTextoUi =>
      DateFormat('dd/MM/yyyy').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _cargarRegistros();
  }

  Future<void> _cargarRegistros() async {
    setState(() {
      _loading = true;
      _error = null;
      _registros.clear();
    });

    try {
      // Usar globalUserId si está disponible, si no, uid de FirebaseAuth
      String driverId = '';
      if (globalUserId != null && globalUserId!.trim().isNotEmpty) {
        driverId = globalUserId!.trim();
      } else {
        final user = FirebaseAuth.instance.currentUser;
        driverId = user?.uid ?? '';
      }

      if (driverId.isEmpty) {
        setState(() {
          _error = 'No se pudo determinar el conductor actual.';
          _loading = false;
        });
        return;
      }

      // Ruta: EntregasRepartidor/{driverId}/Meses/YYYY-MM-DD/Paquetes
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/EntregasRepartidor/$driverId/Meses/$_fechaClaveDb/Paquetes',
      );

      final snap = await ref.get();
      if (!snap.exists || snap.value == null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      final value = snap.value;
      if (value is Map) {
        final List<Map<String, dynamic>> temp = [];

        value.forEach((key, dynamic v) {
          // key = idGuia (por ejemplo PB1762292007638OX)
          if (v is Map) {
            final fecha = v['Fecha']?.toString() ?? '';
            final idGuia = v['idGuia']?.toString() ?? key.toString();
            final idMovimiento = v['idMovimiento']?.toString() ?? '';

            temp.add({
              'idMovimiento': idMovimiento,
              'idGuia': idGuia,
              'Fecha': fecha,
            });
          }
        });

        // Ordenar por fecha ascendente (como texto)
        temp.sort((a, b) =>
            (a['Fecha'] as String).compareTo(b['Fecha'] as String));

        setState(() {
          _registros.addAll(temp);
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error al cargar historial: $e';
        _loading = false;
      });
    }
  }

  // selector de fecha
  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(now.year - 1, 1, 1); // 1 año atrás

    final newDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 1)),
      helpText: 'Selecciona una fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (newDate != null) {
      setState(() {
        _selectedDate = DateTime(newDate.year, newDate.month, newDate.day);
      });
      await _cargarRegistros();
    }
  }

  Future<void> _mostrarDetalleMovimiento(
    BuildContext context,
    String idGuia,
    String idMovimiento,
  ) async {
    try {
      // Ruta: Historal/{idGuia}/Movimientos/{idMovimiento}
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Historal/$idGuia/Movimientos/$idMovimiento',
      );

      final snap = await ref.get();
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Sin información'),
            content: const Text('No se encontró detalle para este movimiento.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
        return;
      }

      final data = snap.value as Map;
      final recibio = data['Recibio']?.toString() ?? '';
      final parentesco = data['Parentesco']?.toString() ?? '';
      final fecha = data['Fecha']?.toString() ?? '';
      final foto1 = data['FotoEvidencia']?.toString() ?? '';
      final foto2 = data['FotoEvidencia2']?.toString() ?? '';

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Detalle de entrega'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('Recibió', recibio),
                const SizedBox(height: 4),
                _infoRow('Parentesco', parentesco),
                const SizedBox(height: 4),
                _infoRow('Fecha', fecha),
                const SizedBox(height: 16),
                if (foto1.isNotEmpty) _fotoSection('Foto evidencia 1', foto1),
                if (foto2.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _fotoSection('Foto evidencia 2', foto2),
                ],
                if (foto1.isEmpty && foto2.isEmpty)
                  const Text(
                    'No hay evidencias fotográficas registradas.',
                    style: TextStyle(color: Colors.black54),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: Text('No se pudo cargar el detalle: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(value.isEmpty ? '-' : value),
        ),
      ],
    );
  }

  Widget _fotoSection(String label, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _verImagenCompleta(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _descargarImagen(url),
            icon: const Icon(Icons.download),
            label: const Text('Descargar'),
          ),
        ),
      ],
    );
  }

  void _verImagenCompleta(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

Future<void> _descargarImagen(String url) async {
  try {
    final uri = Uri.parse(url);

    // Intentar abrir fuera de la app (navegador / visor de imágenes)
    final bool ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el enlace de descarga.'),
        ),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error al intentar descargar: $e')),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de paquetes'),
        backgroundColor: const Color(0xFF1955CC),
      ),
      body: Column(
        children: [
          // Selector de fecha
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Fecha: $_fechaTextoUi'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _cargarRegistros,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _error!,
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _cargarRegistros,
            child: const Text('Reintentar'),
          ),
        ],
      );
    }

    if (_registros.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'No hay entregas registradas para la fecha $_fechaTextoUi.',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _registros.length,
      itemBuilder: (context, index) {
        final reg = _registros[index];
        final idGuia = reg['idGuia'] as String;
        final fecha = reg['Fecha'] as String;
        final idMovimiento = reg['idMovimiento'] as String;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: ListTile(
            title: Text(
              'Guía: $idGuia',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('Fecha: $fecha'),
            trailing: IconButton(
              icon: const Icon(Icons.remove_red_eye_outlined),
              onPressed: () =>
                  _mostrarDetalleMovimiento(context, idGuia, idMovimiento),
            ),
          ),
        );
      },
    );
  }
}
