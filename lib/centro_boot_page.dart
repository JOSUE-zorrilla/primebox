// centro_boot_page.dart
import 'dart:convert';                     // <- para json
import 'dart:developer' as dev;            // <- logs
import 'package:flutter/foundation.dart';  // <- kDebugMode
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Usa las globals definidas en login_page.dart
import 'login_page.dart' show globalIdCiudad;

class CentroBootPage extends StatefulWidget {
  final String nextRoute; // a dónde ir cuando termine
  const CentroBootPage({super.key, this.nextRoute = '/paquetes'});

  @override
  State<CentroBootPage> createState() => _CentroBootPageState();
}

class _CentroBootPageState extends State<CentroBootPage> {
  String _status = "Iniciando...";
  String? _debugIdCiudad; // para mostrar arriba en debug
  int _cargados = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final idCiudad = globalIdCiudad;
      _debugIdCiudad = idCiudad;

      debugPrint('[CentroBoot] idCiudad="$idCiudad"');
      dev.log('idCiudad="$idCiudad"', name: 'CentroBoot');

      if (idCiudad == null || idCiudad.trim().isEmpty) {
        debugPrint('[CentroBoot] idCiudad vacío. Saltando carga.');
        setState(() => _status = 'Sin idCiudad. Continuando...');
      } else {
        final path =
            'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/CentrosRecoleccionCiudad/$idCiudad/CentrosRecoleccion';
        debugPrint('[CentroBoot] Path Firebase: $path');

        setState(() => _status = 'Cargando información base...');
        final ref = FirebaseDatabase.instance.ref(path);

        final snap = await ref.get().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('[CentroBoot] 🔥 Timeout al leer Firebase.');
            throw Exception('Timeout Firebase');
          },
        );

        debugPrint('[CentroBoot] snap.exists = ${snap.exists}');
        if (kDebugMode) {
          dev.log('Valor crudo de snap: ${snap.value}', name: 'CentroBoot/snap');
        }

        /// Normalizamos a una **lista de centros** con las llaves:
        /// Nombre, Direccion, Icono
        final List<Map<String, String>> centros = [];

        if (snap.exists && snap.value != null) {
          final val = snap.value;

          // Estructura típica: Map { centroId: {Nombre, Direccion, Icono}, ... }
          if (val is Map) {
            for (final entry in val.entries) {
              final data = entry.value;
              if (data is Map) {
                centros.add({
                  'Nombre': (data['Nombre'] ?? '').toString(),
                  'Direccion': (data['Direccion'] ?? '').toString(),
                  'Icono': (data['Icono'] ?? '').toString(),
                });
              }
            }
          }
          // A veces podría venir como List
          else if (val is List) {
            for (final item in val) {
              if (item is Map) {
                centros.add({
                  'Nombre': (item['Nombre'] ?? '').toString(),
                  'Direccion': (item['Direccion'] ?? '').toString(),
                  'Icono': (item['Icono'] ?? '').toString(),
                });
              }
            }
          } else {
            debugPrint('[CentroBoot] ⚠️ Formato inesperado: ${val.runtimeType}');
          }
        } else {
          debugPrint('[CentroBoot] ⚠️ No hay centros en la ruta.');
        }

        _cargados = centros.length;
        setState(() => _status = 'Sincronizando $_cargados centro(s)...');

        final prefs = await SharedPreferences.getInstance();

        // Guarda lista completa (JSON)
        await prefs.setString('cr_centros_json', jsonEncode(centros));
        await prefs.setString('cr_lastSync', DateTime.now().toIso8601String());

        // Compatibilidad: guarda el primero en las llaves antiguas
        if (centros.isNotEmpty) {
          await prefs.setString('cr_nombre', centros.first['Nombre'] ?? '');
          await prefs.setString('cr_direccion', centros.first['Direccion'] ?? '');
          await prefs.setString('cr_icono', centros.first['Icono'] ?? '');
        } else {
          await prefs.setString('cr_nombre', '');
          await prefs.setString('cr_direccion', '');
          await prefs.setString('cr_icono', '');
        }

        debugPrint('[CentroBoot] ✅ Prefs guardadas. total=${centros.length}');
        if (kDebugMode) {
          dev.log('centros_json=${jsonEncode(centros)}', name: 'CentroBoot/prefs');
        }
      }
    } catch (e, st) {
      debugPrint('[CentroBoot] ❌ Error en _boot: $e');
      if (kDebugMode) dev.log('StackTrace: $st', name: 'CentroBoot/error');
    } finally {
      setState(() => _status = 'Finalizando...');
      // Mantener splash al menos 3s para UX
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      _goNext();
    }
  }

  void _goNext() {
    Navigator.pushReplacementNamed(context, widget.nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // 🔎 Banda superior con idCiudad y cantidad (solo en debug)
            if (kDebugMode && (_debugIdCiudad?.isNotEmpty ?? false))
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'idCiudad: ${_debugIdCiudad!} • cargados: $_cargados',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // Logo + lema
            Align(
              alignment: const Alignment(0, -0.15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/primebox_logo.png',
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Experiencia e Innovación',
                    style: TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            // Ilustración
            Align(
              alignment: const Alignment(0, 0.3),
              child: Image.asset(
                'assets/images/truck_illustration.png',
                height: 140,
                fit: BoxFit.contain,
              ),
            ),

            // Estado
            Align(
              alignment: const Alignment(0, 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
