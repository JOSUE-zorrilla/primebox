import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'centro_boot_page.dart';

// ✅ Variables globales
String? globalUserId;
String? globalNombre;
String? globalIdCiudad;

// 🎨 Colores de la UI
const Color kBg = Color(0xFFF2F2F2);
const Color kTitle = Color(0xFF0F285C);
const Color kPrimaryBlue300 = Color(0xFF64B5F6);
const Color kUnderline = Color(0xFFBDBDBD);
const Color kHint = Color(0x99000000);



class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _verificarSesionIniciada();
  }

  Future<void> _verificarSesionIniciada() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      final uid = user.uid;

      final DatabaseReference ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/apps/app_19PX2WeHAwM8ejcWQ3jFCd/members/$uid/customData',
      );

      final snapshot = await ref.get();

      if (snapshot.exists && snapshot.child('TipoPerfil').value == 'Driver') {
        globalUserId = uid;
        await _cargarDatosConductor(uid);

        if (!mounted) return;

        // 👉 NUEVO: ir a cargar centro antes de paquetes
        if (globalIdCiudad != null && globalIdCiudad!.trim().isNotEmpty) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const CentroBootPage(nextRoute: '/paquetes'),
            ),
          );
        } else {
          Navigator.pushReplacementNamed(context, '/paquetes');
        }
      } else {
        await FirebaseAuth.instance.signOut();
      }
    }
  }

  Future<void> _cargarDatosConductor(String uid) async {
    final DatabaseReference conductorRef = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/$uid',
    );

    final snapshot = await conductorRef.get();

    if (snapshot.exists) {
      globalNombre = snapshot.child('Nombre').value?.toString();
      globalIdCiudad = snapshot.child('idCiudad').value?.toString();
    } else {
      debugPrint('⚠️ No se encontraron datos del conductor para UID: $uid');
    }
  }

  Future<void> _login() async {
    setState(() => loading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final uid = credential.user?.uid;
      if (uid == null) throw Exception('UID no encontrado');

      final DatabaseReference ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/apps/app_19PX2WeHAwM8ejcWQ3jFCd/members/$uid/customData',
      );

      final snapshot = await ref.get();

      if (snapshot.exists && snapshot.child('TipoPerfil').value == 'Driver') {
        globalUserId = uid;
        await _cargarDatosConductor(uid);

        if (!mounted) return;

        // 👉 NUEVO: ir a cargar centro antes de paquetes
        if (globalIdCiudad != null && globalIdCiudad!.trim().isNotEmpty) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const CentroBootPage(nextRoute: '/paquetes'),
            ),
          );
        } else {
          Navigator.pushReplacementNamed(context, '/paquetes');
        }
      } else {
        await FirebaseAuth.instance.signOut();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este usuario no está autorizado')),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Error al iniciar sesión';
      if (e.code == 'user-not-found') message = 'Usuario no encontrado';
      if (e.code == 'wrong-password') message = 'Contraseña incorrecta';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de conexión o datos inválidos')),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelLarge = Theme.of(context).textTheme.labelLarge;
    final labelMedium = Theme.of(context).textTheme.labelMedium;

    const overlay = SystemUiOverlayStyle(
      statusBarColor: kBg,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: kBg,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final viewportH = size.height - padding.vertical;
    final topGap = (viewportH * 0.20).clamp(56.0, 220.0).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: topGap),
                            Text(
                              'Bienvenido',
                              style: GoogleFonts.montserrat(
                                fontSize: 40,
                                fontWeight: FontWeight.w700,
                                color: kTitle,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Ingresa tu correo y contraseña para ingresar \na tu cuenta',
                              style: (labelLarge ?? const TextStyle())
                                  .copyWith(color: kHint, height: 1.35),
                            ),
                            const SizedBox(height: 28),
                            TextField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'Correo Electrónico',
                                prefixIcon: Icon(Icons.email_outlined),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: kUnderline),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                hintText: 'Contraseña',
                                prefixIcon: Icon(Icons.lock_outline),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: kUnderline),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: loading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3771E6),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: loading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'Iniciar Sesión',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: .2,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () {},
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF3771E6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                child: Text(
                                  '¿Olvidaste tu contraseña?',
                                  style: (labelMedium ?? const TextStyle())
                                      .copyWith(color: const Color(0xFF3771E6)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 50.0),
                        child: Center(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '¿Eres nuevo? ',
                                style: (labelMedium ?? const TextStyle())
                                    .copyWith(color: Colors.black54),
                              ),
                              GestureDetector(
                                onTap: () {},
                                child: Text(
                                  'Registrarte',
                                  style: (labelMedium ?? const TextStyle()).copyWith(
                                    color: const Color(0xFF3771E6),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
