import 'package:flutter/material.dart';
import 'login_page.dart';
import 'qr_scanner_page.dart'; // asumo que esta es tu pantalla principal luego del login

void main() {
  runApp(const MyApp());
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
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginPage(),
        '/qr': (context) => const QRScannerPage(),
      },
    );
  }
}
