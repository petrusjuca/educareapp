import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert' show utf8;

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  runApp(MyApp());
}

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
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  String received = "";
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToESP32();
  }

  @override
  void dispose() {
    // Ensure we stop scanning and disconnect when the widget is disposed
    FlutterBluePlus.stopScan();
    if (targetDevice != null && isConnected) {
      targetDevice!.disconnect();
    }
    super.dispose();
  }

  Future<void> _connectToESP32() async {
    try {
      // Start scanning for devices
      print("🔍 Iniciando busca por dispositivos Bluetooth...");
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Listen to scan results
      bool deviceFound = false;
      FlutterBluePlus.scanResults.listen((results) async {
        if (deviceFound) return; // Avoid duplicate connections

        // Look for the EDUCARE device
        for (ScanResult result in results) {
          print("📱 Dispositivo encontrado: ${result.device.name} (${result.device.id})");

          if (result.device.name == "EDUCARE") {
            deviceFound = true;
            FlutterBluePlus.stopScan();

            targetDevice = result.device;
            print("✅ Dispositivo EDUCARE encontrado!");

            // Connect to the device
            await _connectToDevice();
          }
        }
      });

      // If no device found after scan timeout
      FlutterBluePlus.isScanning.listen((isScanning) {
        if (!isScanning && !deviceFound) {
          print("❌ Dispositivo EDUCARE não encontrado após busca.");
        }
      });
    } catch (e) {
      print("❌ Erro ao iniciar busca: $e");
    }
  }

  Future<void> _connectToDevice() async {
    if (targetDevice == null) return;

    try {
      // Connect to the device
      await targetDevice!.connect();
      print("✅ Conectado a ${targetDevice!.name}");
      isConnected = true;

      // Discover services
      List<BluetoothService> services = await targetDevice!.discoverServices();
      print("🔍 Serviços descobertos: ${services.length}");

      // Find the characteristic we want to communicate with
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          // Check if this characteristic supports notifications (for receiving data)
          if (characteristic.properties.notify) {
            targetCharacteristic = characteristic;
            print("✅ Característica para notificações encontrada");

            // Subscribe to notifications
            await targetCharacteristic!.setNotifyValue(true);
            targetCharacteristic!.value.listen((value) {
              if (value.isNotEmpty) {
                print("📥 Dados brutos recebidos: $value"); // lista de bytes recebidos
                final letra = utf8.decode(value).trim();
                print("📥 Dados convertidos para string: '$letra'");

                setState(() => received = letra);
              }
            });

            break;
          }
        }
        if (targetCharacteristic != null) break;
      }

      if (targetCharacteristic == null) {
        print("⚠️ Não foi possível encontrar uma característica para comunicação");
      }
    } catch (e) {
      print("❌ Erro ao conectar: $e");
      isConnected = false;
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
