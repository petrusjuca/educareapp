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
  StreamSubscription<BluetoothDeviceState>? deviceStateSub;
  StreamSubscription<List<int>>? notifySub;

  String received = "";
  bool isConnected = false;
  bool scanning = false;

  final String deviceName = "EDUCARE";
  final int scanTimeoutSeconds = 8;
  final int maxRetries = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureConnectedFlow();
    });
  }

  @override
  void dispose() {
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

  // ---------- FLOW PRINCIPAL ----------
  Future<void> _ensureConnectedFlow() async {
    final ok = await _requestPermissions();
    if (!ok) {
      await _showAlert("Permissões", "Permissões necessárias não concedidas. O app não funcionará corretamente.");
      return;
    }

    final btOn = await _isBluetoothOn();
    if (!btOn) {
      final result = await _showConfirm("Bluetooth desligado", "O Bluetooth está desligado. Deseja ativá-lo?");
      if (result == true) {
        // tenta ligar programaticamente (pode não funcionar em todas as ROMs)
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
      return;
    }

    await _tryConnectWithRetries();
  }

  // ---------- PERMISSÕES (permission_handler ^11.2.0) ----------
  Future<bool> _requestPermissions() async {
    try {
      // Construir lista de permissões a pedir dependendo da plataforma / API
      final toRequest = <Permission>[];

      // Para Android 12+ pedimos bluetoothScan/bluetoothConnect; para versões antigas, Location é necessário para discovery.
      if (Platform.isAndroid) {
        // permission_handler define essas permissões (v11+)
        if (Permission.bluetoothScan.isDefined) toRequest.add(Permission.bluetoothScan);
        if (Permission.bluetoothConnect.isDefined) toRequest.add(Permission.bluetoothConnect);
        if (Permission.bluetooth.isDefined) toRequest.add(Permission.bluetooth);
        // Localização (discovery em Android <12)
        if (Permission.locationWhenInUse.isDefined) toRequest.add(Permission.locationWhenInUse);
        if (Permission.location.isDefined) toRequest.add(Permission.location);
      } else if (Platform.isIOS) {
        // iOS: pedimos quando/if needed (ex.: bluetooth)
        if (Permission.bluetooth.isDefined) toRequest.add(Permission.bluetooth);
      } else {
        // outras plataformas: apenas location como fallback
        if (Permission.locationWhenInUse.isDefined) toRequest.add(Permission.locationWhenInUse);
      }

      // remover duplicados (set)
      final uniq = toRequest.toSet().toList();

      // Solicitar todas
      final statuses = await uniq.request();

      // Verifica se alguma foi negada permanentemente
      for (var p in uniq) {
        final s = statuses[p];
        if (s == null) continue;
        if (s.isDenied || s.isPermanentlyDenied || s.isRestricted) {
          print("Permissão negada ou restrita: $p -> $s");
          return false;
        }
      }

      return true;
    } catch (e) {
      print("Erro ao solicitar permissões: $e");
      return false;
    }
  }

  // ---------- CHECK BLUETOOTH ON ----------
  Future<bool> _isBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.instance.state.first;
      print("Estado do Bluetooth: $state");
      return state == BluetoothState.on;
    } catch (e) {
      print("Erro ao verificar estado bluetooth: $e");
      return false;
    }
  }

  // ---------- RETRIES E SCAN ----------
  Future<void> _tryConnectWithRetries() async {
    int attempt = 0;
    while (attempt < maxRetries && !isConnected) {
      attempt++;
      print("Tentativa $attempt / $maxRetries");
      final found = await _startScanAndConnect(timeout: Duration(seconds: scanTimeoutSeconds));
      if (found && isConnected) {
        print("Conectado na tentativa $attempt");
        return;
      } else {
        final again = await _showConfirm("EDUCARE não encontrado", "Deseja tentar novamente? (Tentativa $attempt/$maxRetries)");
        if (!again) return;
      }
    }

    if (!isConnected) {
      await _showAlert("Falha", "Não foi possível conectar ao EDUCARE após $maxRetries tentativas.");
    }
  }

  Future<bool> _startScanAndConnect({required Duration timeout}) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    bool deviceFound = false;
    scanning = true;
    setState(() {});

    final completer = Completer<bool>();

    try {
      FlutterBluePlus.startScan(timeout: timeout);

      scanResultsSub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          final name = r.device.name;
          print("Scan: $name (${r.device.id})");
          if (name == deviceName) {
            deviceFound = true;
            await FlutterBluePlus.stopScan();
            await scanResultsSub?.cancel();
            targetDevice = r.device;
            final connected = await _connectToDevice();
            if (!completer.isCompleted) completer.complete(connected);
            break;
          }
        }
      });

      FlutterBluePlus.isScanning.listen((isScanning) {
        if (!isScanning && !deviceFound && !completer.isCompleted) {
          if (!completer.isCompleted) completer.complete(false);
        }
      });

      final result = await completer.future.timeout(timeout + const Duration(seconds: 2), onTimeout: () {
        if (!completer.isCompleted) completer.complete(false);
        return false;
      });

      return result;
    } catch (e) {
      print("Erro no scan: $e");
      if (!completer.isCompleted) completer.complete(false);
      return false;
    } finally {
      scanning = false;
      setState(() {});
    }
  }

  // ---------- CONEXÃO & NOTIFICAÇÕES ----------
  Future<bool> _connectToDevice() async {
    if (targetDevice == null) return false;

    try {
      // Conectar (com timeout)
      try {
        final st = await targetDevice!.state.first;
        if (st == BluetoothDeviceState.connected) {
          isConnected = true;
          print("Já conectado (reuso).");
        } else {
          await targetDevice!.connect(timeout: const Duration(seconds: 10));
          isConnected = true;
          print("Conectado a ${targetDevice!.name}");
        }
      } catch (e) {
        // fallback
        await targetDevice!.connect(timeout: const Duration(seconds: 10));
        isConnected = true;
        print("Conectado (fallback) a ${targetDevice!.name}");
      }

      deviceStateSub?.cancel();
      deviceStateSub = targetDevice!.state.listen((state) {
        print("Device state: $state");
        if (state == BluetoothDeviceState.disconnected) {
          isConnected = false;
          targetCharacteristic = null;
          _showConfirm("Conexão perdida", "Conexão com EDUCARE perdida. Reconectar?").then((retry) {
            if (retry == true) _ensureConnectedFlow();
          });
        }
      });

      final services = await targetDevice!.discoverServices();
      print("Serviços: ${services.length}");

      BluetoothCharacteristic? found;
      for (var s in services) {
        for (var c in s.characteristics) {
          if (c.properties.notify || c.properties.read || c.properties.write) {
            found = c;
            break;
          }
        }
        if (found != null) break;
      }

      if (found == null) {
        print("Característica compatível não encontrada.");
        return true; // conectado, mas sem char
      }

      targetCharacteristic = found;

      if (targetCharacteristic!.properties.notify) {
        try {
          await targetCharacteristic!.setNotifyValue(true);
          notifySub?.cancel();
          notifySub = targetCharacteristic!.value.listen((value) {
            if (value.isEmpty) return;
            print("Raw: $value");
            try {
              final letra = utf8.decode(value).trim();
              print("Recebido: '$letra'");
              setState(() => received = letra);
            } catch (e) {
              print("Erro decode: $e");
            }
          }, onError: (err) {
            print("Erro notify stream: $err");
          }, onDone: () {
            print("Notify stream done.");
          });
        } catch (e) {
          print("Falha notify: $e");
        }
      }

      return true;
    } catch (e) {
      print("Erro conectar: $e");
      isConnected = false;
      return false;
    }
  }

  // ---------- AÇÕES / VERIFICAÇÃO ANTES DE USAR ----------
  Future<bool> _ensureConnectionBeforeAction() async {
    if (isConnected && targetDevice != null) return true;
    final retry = await _showConfirm("Sem conexão", "App não está conectado ao EDUCARE. Deseja tentar reconectar?");
    if (retry == true) {
      await _ensureConnectedFlow();
      return isConnected;
    }
    return false;
  }

  // ---------- UI / MODAIS ----------
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

  // ---------- BOTÕES ----------
  Widget _buildButton(String letra) {
    final ativo = received == letra;
    return ElevatedButton(
      onPressed: () async {
        final ok = await _ensureConnectionBeforeAction();
        if (!ok) return;

        if (targetCharacteristic != null && targetCharacteristic!.properties.write) {
          try {
            final bytes = utf8.encode(letra);
            await targetCharacteristic!.write(bytes, withoutResponse: false);
            print("➡ Enviado: $letra");
          } catch (e) {
            print("Erro enviar: $e");
            await _showAlert("Erro", "Falha ao enviar comando: $e");
          }
        } else {
          print("Característica não suporta escrita.");
        }
      },
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
              ElevatedButton(
                onPressed: () async {
                  await _ensureConnectedFlow();
                },
                child: const Text("Conectar / Reconectar"),
              )
            ],
          ),
        ),
      );
}
