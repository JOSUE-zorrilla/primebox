import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  Map<String, dynamic> conductorData = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _cargarDatosConductor();
  }

  Future<void> _cargarDatosConductor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance.ref(
      'projects/proj_bt5YXxta3UeFNhYLsJMtiL/data/Conductores/${user.uid}',
    );

    final snapshot = await ref.get();

    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      setState(() {
        conductorData = data;
        loading = false;
      });
    } else {
      setState(() {
        loading = false;
      });
    }
  }

  Widget _buildCampo(String label, dynamic valor, {bool icono = false}) {
    final bool existe = valor != null && valor.toString().trim().isNotEmpty;
    final color = existe ? Colors.black : Colors.red;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icono) const Icon(Icons.person, size: 20, color: Colors.blue),
        if (icono) const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Expanded(
          child: Text(
            existe ? valor.toString() : 'No registrado',
            style: TextStyle(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final foto = conductorData['Foto'];
    final nombre = conductorData['Nombre'];
    final curp = conductorData['Curp'];
    final email = conductorData['Email'];
    final telefono = conductorData['Telefono'];

    final licencia = conductorData['LicenciaConducir'];
    final ineFrente = conductorData['IneFrente'];
    final ineAtras = conductorData['IneAtras'];
    final antecedentes = conductorData['CartaAntecedentes'];
    final comprobante = conductorData['ComprobanteDomicilio'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil del Conductor'),
        backgroundColor: const Color(0xFF1A3365),
        foregroundColor: Colors.white,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: (foto != null && foto.toString().isNotEmpty)
                          ? NetworkImage(foto)
                          : const AssetImage('assets/images/default.png') as ImageProvider,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildCampo('Nombre', nombre, icono: true),
                  const SizedBox(height: 8),
                  _buildCampo('CURP', curp, icono: true),
                  const SizedBox(height: 8),
                  _buildCampo('Email', email),
                  const SizedBox(height: 8),
                  _buildCampo('Teléfono', telefono),
                  const Divider(height: 32),
                  _buildCampo('Licencia de Conducir', licencia),
                  const SizedBox(height: 8),
                  _buildCampo('INE Frente', ineFrente),
                  const SizedBox(height: 8),
                  _buildCampo('INE Atrás', ineAtras),
                  const SizedBox(height: 8),
                  _buildCampo('Carta de Antecedentes', antecedentes),
                  const SizedBox(height: 8),
                  _buildCampo('Comprobante de Domicilio', comprobante),
                ],
              ),
            ),
    );
  }
}
