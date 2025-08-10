import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: BluetoothScreen(),
        debugShowCheckedModeBanner: false,
      );
}

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});
  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  BluetoothConnection? connection;
  String received = "";

  @override
  void initState() {
    super.initState();
    _connectToESP32();
  }

  Future<void> _connectToESP32() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      final esp = devices.firstWhere((d) => d.name == "EDUCARE",
          orElse: () => throw Exception("ESP32 'EDUCARE' não emparelhado"));

      connection = await BluetoothConnection.toAddress(esp.address);
      print("✅ Conectado a ${esp.name}");

      connection!.input!.listen((data) {
        final letra = String.fromCharCodes(data).trim();
        setState(() => received = letra);
        print("📥 Recebido: $letra");
      });
    } catch (e) {
      print("❌ Erro: $e");
    }
  }

  Widget _buildButton(String letra) {
    final ativo = received == letra;
    return ElevatedButton(
      onPressed: () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: ativo ? Colors.green : Colors.grey,
        minimumSize: const Size(120, 48),
      ),
      child: Text("Botão $letra"),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Controle EDUCARE")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildButton("A"),
              _buildButton("E"),
              _buildButton("I"),
              _buildButton("O"),
              _buildButton("U"),
              const SizedBox(height: 24),
              Text("Último recebido: $received"),
            ],
          ),
        ),
      );
}
