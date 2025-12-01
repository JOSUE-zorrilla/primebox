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

  /// Rango de fechas (NO puede ser mayor a hoy)
  late DateTime _fromDate;
  late DateTime _toDate;

  final DateFormat _fmtDb = DateFormat('yyyy-MM-dd');
  final DateFormat _fmtUi = DateFormat('dd/MM/yyyy');

  String get _fromText => _fmtUi.format(_fromDate);
  String get _toText => _fmtUi.format(_toDate);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day); // hoy
    _toDate   = DateTime(now.year, now.month, now.day); // hoy
    _cargarRegistros();
  }

  /// LEE TODAS LAS FECHAS ENTRE [_fromDate] y [_toDate] (ambas incluidas)
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

      final List<Map<String, dynamic>> temp = [];

      // Iterar por cada día del rango
      DateTime current = _fromDate;
      final DateTime today = DateTime.now();

      while (!current.isAfter(_toDate)) {
        // Seguridad extra: nunca leer más allá de hoy
        final safeCurrent = current.isAfter(today)
            ? DateTime(today.year, today.month, today.day)
            : current;

        final fechaClaveDb = _fmtDb.format(safeCurrent);

        // Ruta: EntregasRepartidor/{driverId}/Meses/YYYY-MM-DD/Paquetes
        final ref = FirebaseDatabase.instance.ref(
          'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/EntregasRepartidor/$driverId/Meses/$fechaClaveDb/Paquetes',
        );

        final snap = await ref.get();
        if (snap.exists && snap.value != null && snap.value is Map) {
          final value = snap.value as Map;

          value.forEach((key, dynamic v) {
            if (v is Map) {
              final fecha = v['Fecha']?.toString() ?? '';
              final idGuia = v['idGuia']?.toString() ?? key.toString();
              final idMovimiento = v['idMovimiento']?.toString() ?? '';

              temp.add({
                'idMovimiento': idMovimiento,
                'idGuia': idGuia,
                'Fecha': fecha,
                'FechaClave': fechaClaveDb, // por si quieres mostrar luego
              });
            }
          });
        }

        // siguiente día
        current = current.add(const Duration(days: 1));
      }

      // Ordenar por fecha (texto) y luego por guía
      temp.sort((a, b) {
        final f1 = (a['Fecha'] as String?) ?? '';
        final f2 = (b['Fecha'] as String?) ?? '';
        final cmp = f1.compareTo(f2);
        if (cmp != 0) return cmp;
        return (a['idGuia'] as String).compareTo(b['idGuia'] as String);
      });

      setState(() {
        _registros.addAll(temp);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar historial: $e';
        _loading = false;
      });
    }
  }

  /// Selector genérico de fecha (desde / hasta)
  Future<void> _pickDate({required bool isFrom}) async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(now.year - 1, 1, 1); // 1 año atrás

    final initial = isFrom ? _fromDate : _toDate;

    final newDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year, now.month, now.day), // no más que hoy
      helpText: isFrom ? 'Selecciona fecha inicial' : 'Selecciona fecha final',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (newDate != null) {
      setState(() {
        final picked =
            DateTime(newDate.year, newDate.month, newDate.day); // normalizar

        if (isFrom) {
          _fromDate = picked;
          // si la fecha inicial queda mayor que la final, ajustamos la final
          if (_fromDate.isAfter(_toDate)) {
            _toDate = _fromDate;
          }
        } else {
          _toDate = picked;
          // si la fecha final queda menor que la inicial, ajustamos la inicial
          if (_toDate.isBefore(_fromDate)) {
            _fromDate = _toDate;
          }
        }
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
        title: const Text(
          'Historial de paquetes',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1955CC),
        iconTheme: const IconThemeData(
          color: Colors.white, // flecha de regresar en blanco
        ),
      ),
      body: Column(
        children: [
          // Selector de rango de fechas
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: true),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Desde: $_fromText'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: false),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Hasta: $_toText'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // CONTADOR DE PAQUETES
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Total de paquetes: ${_registros.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
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
            'No hay entregas registradas entre $_fromText y $_toText.',
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
