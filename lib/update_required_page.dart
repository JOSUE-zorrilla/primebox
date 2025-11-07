import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateRequiredPage extends StatelessWidget {
  final String currentVersion;
  final String remoteVersion;
  final String downloadUrl;

  const UpdateRequiredPage({
    super.key,
    required this.currentVersion,
    required this.remoteVersion,
    required this.downloadUrl,
  });

 Future<void> _openUpdateUrl(BuildContext context) async {
  if (downloadUrl.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay URL de actualización disponible.')),
    );
    return;
  }

  // 1) Sanitizar: quitar comillas/espacios y asegurar esquema
  String raw = downloadUrl.trim();
  if ((raw.startsWith('"') && raw.endsWith('"')) ||
      (raw.startsWith("'") && raw.endsWith("'"))) {
    raw = raw.substring(1, raw.length - 1).trim();
  }
  if (!raw.contains('://')) raw = 'https://$raw';

  Uri? uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    uri = null;
  }
  if (uri == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('URL de actualización inválida: $raw')),
    );
    return;
  }

  // 2) Intentar con varios modos (algunos emuladores no tienen navegador)
  final modes = <LaunchMode>[
    LaunchMode.externalApplication,   // navegador/app externa
    LaunchMode.inAppBrowserView,      // vista tipo CustomTabs/SFSafariView
    LaunchMode.platformDefault,       // lo que el SO decida
  ];

  for (final m in modes) {
    try {
      final opened = await launchUrl(uri, mode: m);
      if (opened) return;
    } catch (_) {
      // Ignora y prueba el siguiente modo
    }
  }

  // 3) Si todos fallan
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('No se pudo abrir la URL: $raw')),
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update, size: 64, color: Color(0xFF1955CC)),
                    const SizedBox(height: 16),
                    const Text(
                      'Se requiere actualización',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F285C),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Para continuar usando el sistema debes actualizar a la última versión.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black54, height: 1.35),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F0FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _versionItem('Actual', currentVersion),
                          const Icon(Icons.arrow_forward, color: Color(0xFF1955CC)),
                          _versionItem('Requerida', remoteVersion),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Actualizar'),
                        onPressed: () => _openUpdateUrl(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1955CC),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Debes actualizar para continuar.')),
                        );
                      },
                      child: const Text('Más tarde'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _versionItem(String label, String version) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 4),
        Text(
          version.isEmpty ? '—' : version,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F285C),
          ),
        ),
      ],
    );
  }
}
