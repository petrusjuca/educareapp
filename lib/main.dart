// lib/main.dart
import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  runApp(const MyApp());
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

  StreamSubscription<List<ScanResult>>? scanResultsSub;
  StreamSubscription<BluetoothConnectionState>? deviceStateSub;
  StreamSubscription<List<int>>? notifySub;

  String received = "";
  bool isConnected = false;
  bool scanning = false;
  bool userCancelledScan = false;

  // Ajuste esses valores se quiser
  final String deviceName = "EDUCARE";
  final String serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final int scanTimeoutSeconds = 8;
  final int maxRetries = 8; // numero de tentativas automáticas

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureConnectedFlow();
    });
  }

  @override
  void dispose() {
    userCancelledScan = true;
    scanResultsSub?.cancel();
    deviceStateSub?.cancel();
    notifySub?.cancel();
    if (targetDevice != null && isConnected) {
      try {
        targetDevice!.disconnect();
      } catch (_) {}
    }
    super.dispose();
  }

  // ------------------ FLUXO PRINCIPAL ------------------
  Future<void> _ensureConnectedFlow() async {
    final ok = await _requestPermissions();
    if (!ok) {
      await _showAlert("Permissões", "Permissões necessárias não concedidas. O app pode não funcionar corretamente.");
      return;
    }

    final btOn = await _isBluetoothOn();
    if (!btOn) {
      final result = await _showConfirm("Bluetooth desligado", "O Bluetooth está desligado. Deseja ativá-lo?");
      if (result == true) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
      return;
    }

    await _tryConnectWithRetries();
  }

  // ------------------ PERMISSÕES ------------------
  Future<bool> _requestPermissions() async {
    try {
      final toRequest = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetooth,
        Permission.locationWhenInUse,
        Permission.location,
      ];

      final statuses = await toRequest.request();

      for (var p in toRequest) {
        final s = statuses[p];
        if (s == null) continue;
        if (s.isDenied || s.isPermanentlyDenied || s.isRestricted) {
          print("❌ Permissão negada: $p");
          return false;
        }
      }
      return true;
    } catch (e) {
      print("Erro ao solicitar permissões: $e");
      return false;
    }
  }

  // ------------------ CHECAR BLUETOOTH ------------------
  Future<bool> _isBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.first;
      print("📡 Estado do Bluetooth: $state");
      return state == BluetoothAdapterState.on;
    } catch (e) {
      print("Erro ao verificar estado bluetooth: $e");
      return false;
    }
  }

  // ------------------ TENTATIVAS DE CONEXÃO (AUTO-RETRY) ------------------
  Future<void> _tryConnectWithRetries() async {
    int attempt = 0;
    userCancelledScan = false;

    while (attempt < maxRetries && !isConnected && !userCancelledScan) {
      attempt++;
      print("Auto-scan tentativa $attempt / $maxRetries");
      final found = await _startScanAndConnect(timeout: Duration(seconds: scanTimeoutSeconds));
      if (found && isConnected) {
        print("✅ Conectado na tentativa $attempt");
        return;
      }

      // espera curta antes de tentar novamente (evita loop agressivo)
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!isConnected && !userCancelledScan) {
      await _showAlert("Falha", "Não foi possível conectar ao EDUCARE após $maxRetries tentativas.");
    }
  }

  Future<bool> _startScanAndConnect({required Duration timeout}) async {
    try {
      // garante que scan anterior esteja parado
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}

      bool deviceFound = false;
      scanning = true;
      setState(() {});

      final completer = Completer<bool>();

      // inicia scan sem depender exclusivamente do timeout — o código usa o timeout para cada tentativa,
      // mas se um dispositivo válido aparecer a callback resolve o completer imediatamente.
      FlutterBluePlus.startScan(timeout: timeout);

      scanResultsSub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          final name = r.device.name ?? "";
          final adv = r.advertisementData;
          bool matchesService = false;
          try {
            // verificação simples: se alguma serviceUuid conter parte do UUID
            if (adv != null && adv.serviceUuids.isNotEmpty) {
              for (var u in adv.serviceUuids) {
                if (u.toLowerCase().contains(serviceUuid.split('-')[0])) {
                  matchesService = true;
                  break;
                }
              }
            }
          } catch (_) {}

          final matchesName = name == deviceName || name.toLowerCase().contains(deviceName.toLowerCase());
          final matches = matchesName || matchesService;

          print("🔍 Scan found: '${name}' / id=${r.device.id} / matchesService=$matchesService");

          if (matches) {
            deviceFound = true;
            // para o scan e cancela o listener
            try {
              await FlutterBluePlus.stopScan();
            } catch (_) {}
            await scanResultsSub?.cancel();

            targetDevice = r.device;
            // tenta conectar
            final connected = await _connectToDevice();
            if (!completer.isCompleted) completer.complete(connected);
            break;
          }
        }
      });

      // Observa quando o scan realmente termina (ex.: timeout)
      final scanningSub = FlutterBluePlus.isScanning.listen((isScanning) {
        if (!isScanning && !deviceFound && !completer.isCompleted) {
          completer.complete(false);
        }
      });

      final result = await completer.future.timeout(timeout + const Duration(seconds: 2), onTimeout: () {
        if (!completer.isCompleted) completer.complete(false);
        return false;
      });

      await scanningSub.cancel();
      return result;
    } catch (e) {
      print("Erro no scan: $e");
      return false;
    } finally {
      scanning = false;
      setState(() {});
    }
  }

  // ------------------ CONEXÃO E NOTIFICAÇÕES ------------------
  Future<bool> _connectToDevice() async {
    if (targetDevice == null) return false;

    try {
      // Conectar (tenta reconectar se já estiver conectado)
      try {
        final st = await targetDevice!.connectionState.first;
        if (st == BluetoothConnectionState.connected) {
          isConnected = true;
          print("♻️ Já conectado.");
        } else {
          await targetDevice!.connect(timeout: const Duration(seconds: 10));
          isConnected = true;
          print("✅ Conectado a ${targetDevice!.name}");
        }
      } catch (e) {
        // fallback: tentar conectar de novo
        await targetDevice!.connect(timeout: const Duration(seconds: 10));
        isConnected = true;
        print("✅ Conectado (fallback) a ${targetDevice!.name}");
      }

      // listener do estado do device
      deviceStateSub?.cancel();
      deviceStateSub = targetDevice!.connectionState.listen((state) {
        print("🔌 Device state: $state");
        if (state == BluetoothConnectionState.disconnected) {
          isConnected = false;
          targetCharacteristic = null;
          // tenta reconectar automaticamente (após pequena espera)
          Future.delayed(const Duration(milliseconds: 500), () {
            _ensureConnectedFlow();
          });
        }
      });

      // Descobre serviços e escolhe a característica corretamente (filtrando por UUID do serviço se possível)
      final services = await targetDevice!.discoverServices();
      print("📂 Serviços: ${services.length}");

      BluetoothCharacteristic? found;
      for (var s in services) {
        // tenta comparar UUIDs de serviço (caso o ESP exponha exatamente o serviceUuid)
        final sUuid = s.uuid.toString().toLowerCase();
        final want = serviceUuid.toLowerCase();
        if (sUuid.contains(want.split('-')[0]) || sUuid == want) {
          for (var c in s.characteristics) {
            // preferimos uma característica com notify
            if (c.properties.notify) {
              found = c;
              break;
            }
          }
          if (found != null) break;
        }
      }

      // se não achou por serviço, procura pela primeira characteristic com notify em qualquer service
      if (found == null) {
        for (var s in services) {
          for (var c in s.characteristics) {
            if (c.properties.notify) {
              found = c;
              break;
            }
          }
          if (found != null) break;
        }
      }

      if (found == null) {
        print("⚠️ Característica com notify não encontrada.");
        return true; // conectado mas sem característica para receber
      }

      targetCharacteristic = found;

      if (targetCharacteristic!.properties.notify) {
        await targetCharacteristic!.setNotifyValue(true);
        notifySub?.cancel();
        notifySub = targetCharacteristic!.value.listen((value) {
          if (value.isEmpty) return;
          try {
            final letra = utf8.decode(value).trim();
            print("📥 Recebido raw: $value -> '$letra'");
            setState(() => received = letra);
          } catch (e) {
            print("Erro decode: $e");
          }
        }, onError: (err) {
          print("Erro notify stream: $err");
        }, onDone: () {
          print("Notify stream done.");
        });
      }

      return true;
    } catch (e) {
      print("❌ Erro conectar: $e");
      isConnected = false;
      return false;
    }
  }

  // ------------------ UI HELPERS ------------------
  Future<void> _showAlert(String title, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  Future<bool?> _showConfirm(String title, String message) async {
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Sim")),
        ],
      ),
    );
  }

  Future<bool> _ensureConnectionBeforeAction() async {
    if (isConnected && targetDevice != null) return true;
    final retry = await _showConfirm("Sem conexão", "Deseja reconectar ao EDUCARE?");
    if (retry == true) {
      await _ensureConnectedFlow();
      return isConnected;
    }
    return false;
  }

  // ------------------ BOTÕES ------------------
// ------------------ BOTÕES (somente receber) ------------------
Widget _buildButton(String letra) {
  final ativo = received == letra;
  return ElevatedButton(
    onPressed: null, // desabilitado porque o app não envia nada
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
              const SizedBox(height: 12),
              Text("Status: ${isConnected ? 'Conectado' : (scanning ? 'Procurando...' : 'Desconectado')}"),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      // inicia fluxo de conexão manualmente
                      await _ensureConnectedFlow();
                    },
                    child: const Text("Conectar / Reconectar"),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      // permite usuário cancelar scans automáticos
                      userCancelledScan = true;
                      await FlutterBluePlus.stopScan();
                      await scanResultsSub?.cancel();
                      setState(() {});
                    },
                    child: const Text("Parar Busca"),
                  ),
                ],
              )
            ],
          ),
        ),
      );
}
