import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Image.asset(
                  'assets/images/primebox_logo.png',
                  height: 150,
                ),
                const SizedBox(height: 20),

                // Título
                const Text(
                  'Iniciar Sesión',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A3365),
                  ),
                ),
                const SizedBox(height: 30),

                // Correo
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Correo electrónico'),
                ),
                const TextField(
                  decoration: InputDecoration(
                    hintText: 'Ingrese su correo aqui...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // Contraseña
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Contraseña'),
                ),
                const TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: '•••',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 30),

                // Botón
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/qr');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3365),
                      foregroundColor: Colors.white, // 👈 aquí defines el color del texto
                    ),
                    child: const Text(
                      'ENTRAR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),



                // Pie de página
                const Text(
                  '© 2025 Desarrollado por Orionix.mx',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
