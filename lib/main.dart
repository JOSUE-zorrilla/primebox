import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'login_page.dart';
import 'qr_scanner_page.dart';
import 'paquetes_page.dart';
import 'update_required_page.dart';
import 'version_provider.dart'; // ⬅️ NUEVO: usamos APP_VERSION

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    runApp(const MyApp());
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('🔥 Error al inicializar Firebase:\n$e'),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Escanear QR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        '/qr': (context) => const QRScannerPage(),
        '/paquetes': (context) => const PaquetesPage(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _arrancarFlujo();
  }

  Future<void> _arrancarFlujo() async {
    const splashDelay = Duration(seconds: 3);

    try {
      // 1) Versión local desde --dart-define
      final localVersion = AppVersion.value.trim(); // p.ej. "1.3.0"

      // 2) Leer versión remota en RTDB
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Versiones/0',
      );
      final snap = await ref.get();

      String? remoteDriver;
      String? urlDriver;

      if (snap.exists) {
        remoteDriver = snap.child('Driver').value?.toString().trim();
        urlDriver = snap.child('UrlDriver').value?.toString().trim();
      }

      // 3) Decidir navegación
      if (remoteDriver != null &&
          remoteDriver.isNotEmpty &&
          remoteDriver != localVersion) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UpdateRequiredPage(
              currentVersion: localVersion.isEmpty ? '—' : localVersion,
              remoteVersion: remoteDriver!,
              downloadUrl: urlDriver ?? '',
            ),
          ),
        );
        return;
      }

      // Si no hay versión remota o coincide → continuar al login
      await Future.delayed(splashDelay);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (_) {
      // Ante cualquier error → continuar normal
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/primebox_logo.png',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(color: Color(0xFF1955CC)),
              const SizedBox(height: 16),
              const Text(
                'Cargando...',
                style: TextStyle(
                  color: Color(0xFF1955CC),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
