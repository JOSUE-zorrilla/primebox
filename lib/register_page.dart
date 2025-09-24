import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';

const Color kBg = Color(0xFFF2F2F2);
const Color kTitle = Color(0xFF0F285C);
const Color kPrimaryBlue300 = Color(0xFF64B5F6);
const Color kUnderline = Color(0xFFBDBDBD);
const Color kHint = Color(0x99000000);

class CityOption {
  final String id;         // key del nodo en AlmacenPicker
  final String nombre;     // NombreAlmacen

  CityOption({required this.id, required this.nombre});
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nombreCtrl = TextEditingController();
  final _curpCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  // Ciudades
  bool _loadingCities = true;
  List<CityOption> _ciudades = [];
  CityOption? _selCiudad;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cargarCiudades();
  }

  Future<void> _cargarCiudades() async {
    setState(() => _loadingCities = true);
    try {
      final ref = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/idCiudades',
      );
      final snap = await ref.get();

      final List<CityOption> temporal = [];
      if (snap.exists && snap.children.isNotEmpty) {
        for (final c in snap.children) {
          final nombre = c.child('NombreCiudad').value?.toString() ?? '';
          final id = c.key ?? '';
          if (id.isNotEmpty && nombre.isNotEmpty) {
            temporal.add(CityOption(id: id, nombre: nombre));
          }
        }
      }
      temporal.sort((a, b) => a.nombre.compareTo(b.nombre));

      setState(() {
        _ciudades = temporal;
        _loadingCities = false;
      });
    } catch (_) {
      setState(() => _loadingCities = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar las ciudades')),
      );
    }
  }

  Future<void> _registrar() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    if (_selCiudad == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona la ciudad donde trabajarás')),
      );
      return;
    }
    if (_passCtrl.text != _pass2Ctrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las contraseñas no coinciden')),
      );
      return;
    }

    setState(() => _saving = true);

    final nombre = _nombreCtrl.text.trim();
    final curp = _curpCtrl.text.trim();
    final telefono = _telefonoCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final idCiudad = _selCiudad!.id;
    final nombreCiudad = _selCiudad!.nombre;

    try {
      // 1) Crear en Firebase Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final uid = cred.user!.uid;

      // 2) Guardar en members/{uid}
      final membersRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/apps/app_19PX2WeHAwM8ejcWQ3jFCd/members/$uid',
      );

      await membersRef.set({
        'email': email,
        'name': nombre,
        'phone': telefono,
        'customData': {
          'TipoPerfil': 'Driver',
          'idCiudad': idCiudad,
        }
      });

      // 3) Guardar en ConductoresCiudad/{idCiudad}/Conductores/{uid}
      final ciudadConductorRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/ConductoresCiudad/$idCiudad/Conductores/$uid',
      );
      await ciudadConductorRef.set({
        'Curp': curp,
        'Email': email,
        'Nombre': nombre,
        'Telefono': telefono,
        'idConductor': uid,
      });

      // 4) Guardar en UsuariosPW/{uid}/Data (⚠️ texto plano, pedido explícito)
      final passRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/UsuariosPW/$uid',
      );
      await passRef.set({'Data': pass});

      // 5) Guardar en Conductores/{uid}
      final conductoresRef = FirebaseDatabase.instance.ref(
        'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/$uid',
      );
      await conductoresRef.set({
        'Activo': 'No',
        'Curp': curp,
        'Email': email,
        'Nombre': nombre,
        'NombreCiudad': nombreCiudad,
        'PorcentajeEfectividad': 100,
        'Telefono': telefono,
        'idCiudad': idCiudad,
        'idRepartidor': uid,
      });

      // 6) Cerrar sesión y volver a Login
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro exitoso. Inicia sesión.')),
      );

      Navigator.pop(context); // vuelve a la pantalla de login
    } on FirebaseAuthException catch (e) {
      String msg = 'No se pudo crear la cuenta';
      if (e.code == 'email-already-in-use') {
        msg = 'El correo ya está registrado';
      } else if (e.code == 'invalid-email') {
        msg = 'Correo inválido';
      } else if (e.code == 'weak-password') {
        msg = 'La contraseña es muy débil';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ocurrió un error guardando los datos')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelLarge = Theme.of(context).textTheme.labelLarge;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Registrarte'),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: kTitle,
        elevation: 0.3,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Regístrate',
                      style: GoogleFonts.montserrat(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: kTitle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rellena todos los campos para continuar.',
                      style: (labelLarge ?? const TextStyle())
                          .copyWith(color: kHint, height: 1.35),
                    ),
                    const SizedBox(height: 24),

                    // Nombre
                    TextFormField(
                      controller: _nombreCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Nombre Completo',
                        prefixIcon: Icon(Icons.person_outline),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kUnderline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre' : null,
                    ),
                    const SizedBox(height: 14),

                    // Correo
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Correo Electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kUnderline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Ingresa tu correo' : null,
                    ),
                    const SizedBox(height: 14),

                    // Teléfono
                    TextFormField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Teléfono',
                        prefixIcon: Icon(Icons.phone_outlined),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kUnderline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Ingresa tu teléfono' : null,
                    ),
                    const SizedBox(height: 14),

                    // CURP
                    TextFormField(
                      controller: _curpCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'CURP',
                        prefixIcon: Icon(Icons.badge_outlined),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kUnderline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Ingresa tu CURP' : null,
                    ),
                    const SizedBox(height: 14),

                    // Ciudad (select)
                    _loadingCities
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: LinearProgressIndicator(),
                          )
                        : DropdownButtonFormField<CityOption>(
                            value: _selCiudad,
                            items: _ciudades
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c.nombre),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _selCiudad = v),
                            decoration: const InputDecoration(
                              hintText: 'Ciudad de trabajo',
                              prefixIcon: Icon(Icons.location_on_outlined),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: kUnderline),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                              ),
                            ),
                            validator: (v) =>
                                v == null ? 'Selecciona una ciudad' : null,
                          ),
                    const SizedBox(height: 14),

                    // Contraseña
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kUnderline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                    ),
                    const SizedBox(height: 14),

                    // Repetir contraseña
                    TextFormField(
                      controller: _pass2Ctrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        hintText: 'Repetir contraseña',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kUnderline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: kPrimaryBlue300, width: 1.5),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Repite la contraseña' : null,
                    ),

                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _registrar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3771E6),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Registrarme',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
