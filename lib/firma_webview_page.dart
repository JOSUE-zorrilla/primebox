// firma_webview_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_database/firebase_database.dart';

const String kFirebaseRoot =
    'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data';

class FirmaWebViewPage extends StatefulWidget {
  final String url;
  final int idEmbarque;
  /// Carpeta de fecha con formato YYYY-MM-DDD (día del año con 3 dígitos)
  final String fechaKeyYYYYMMDDD;

  const FirmaWebViewPage({
    super.key,
    required this.url,
    required this.idEmbarque,
    required this.fechaKeyYYYYMMDDD,
  });

  @override
  State<FirmaWebViewPage> createState() => _FirmaWebViewPageState();
}

class _FirmaWebViewPageState extends State<FirmaWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  StreamSubscription<DatabaseEvent>? _firmaSub;

  @override
  void initState() {
    super.initState();

    // Webview
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Suscripción a Realtime DB para detectar la URL de la firma
    final ref = FirebaseDatabase.instance.ref(
      '$kFirebaseRoot/FirmasProveedor/${widget.fechaKeyYYYYMMDDD}/Embarque/${widget.idEmbarque}/Url',
    );
    _firmaSub = ref.onValue.listen((event) {
      final value = event.snapshot.value;
      final urlFirma = (value ?? '').toString().trim();
      if (urlFirma.isNotEmpty) {
        // En cuanto aparezca, cerramos y devolvemos al caller con la URL
        if (mounted) {
          Navigator.of(context).pop<String>(urlFirma);
        }
      }
    });
  }

  @override
  void dispose() {
    _firmaSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firma Digital')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
