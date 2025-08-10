<<<<<<< HEAD
# flutter_application_1

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
=======

# 📚 Educare — Plataforma Figital de Aprendizagem Inclusiva

> **Educare** é um protótipo *figital* (físico + digital) que conecta hardware baseado em ESP32 a um aplicativo Flutter, promovendo uma aprendizagem mais acessível, engajadora e adaptada para crianças com necessidades especiais, especialmente aquelas no **Transtorno do Espectro Autista (TEA)**.

---

## 🌟 Visão Geral

A **Educare** foi desenvolvida para resolver o "Paradoxo da Inclusão": a lei garante a matrícula, mas muitas escolas não têm estrutura para incluir de fato.  
Combinamos **interação física** e **inteligência digital** para criar experiências multissensoriais que facilitam a alfabetização e o desenvolvimento cognitivo.

---

## ✨ Funcionalidades

- 🔗 **Conexão Bluetooth** entre aplicativo e dispositivo físico.
- 🎯 **Feedback multissensorial** — LEDs, som, vibração e interação tátil.
- 🧠 **Interface simples** para educadores não especialistas.
- 📶 **Modo offline-first** — funciona com ou sem internet.
- ⚙ **Personalização futura via IA adaptativa**.

---

## 🛠 Estrutura do Projeto

```

educare/
│
├── flutter\_application/       # Aplicativo Flutter
│   ├── lib/
│   │   ├── main.dart           # App principal e UI
│   │   └── services/           # Serviços de conexão Bluetooth
│   ├── pubspec.yaml            # Configurações e dependências
│
├── esp32\_firmware/             # Código Arduino para o ESP32
│   └── educare\_esp32.ino
│
└── docs/                       # Documentação e futuros recursos visuais

````

---

## 📲 Aplicativo Flutter

### 🔹 Tecnologias usadas
- [Flutter](https://flutter.dev/) 3.x
- [`flutter_bluetooth_serial`](https://pub.dev/packages/flutter_bluetooth_serial) (modificado localmente)
- [Permission Handler](https://pub.dev/packages/permission_handler) para Android 12+

### 🔹 Instalação

```bash
# Clonar o repositório
git clone https://github.com/petrusjuca/educare.git
cd educare/flutter_application

# Instalar dependências do Flutter
flutter pub get

# Rodar no dispositivo conectado
flutter run
````

---

## 🔌 Firmware ESP32

### 🔹 Tecnologias usadas

* Arduino Core for ESP32
* Biblioteca `BluetoothSerial.h`

### 🔹 Upload do código

1. Abra o arquivo `esp32_firmware/educare_esp32.ino` no Arduino IDE.
2. Selecione a placa **ESP32 Dev Module**.
3. Conecte o ESP32 via USB e envie o código.
4. O dispositivo aparecerá como **"EDUCARE"** para pareamento Bluetooth.

---

## 📋 Roadmap

* [x] Conexão Bluetooth com ESP32
* [x] Receber dados dos botões físicos no app
* [x] Feedback visual na interface
* [ ] Enviar comandos do app para o hardware
* [ ] Adicionar interface multissensorial no app
* [ ] Integração com IA adaptativa
* [ ] Versão web/offline com sincronização

---

## 🤝 Contribuindo

1. Faça um fork do repositório.
2. Crie uma branch para sua feature:

   ```bash
   git checkout -b minha-feature
   ```
3. Envie suas alterações:

   ```bash
   git commit -m 'Minha nova feature'
   git push origin minha-feature
   ```
4. Abra um Pull Request.

---

## 📄 Licença

Este projeto está licenciado sob a [MIT License](LICENSE).
ARQUIVO EM DESENVOLVIMENTO;

---

## 👨‍💻 Autor

**Petrus Jucá**
📧 [jucapetrus0@gmail.com](mailto:jucapetrus0@gmail.com)
🔗 [LinkedIn](https://linkedin.com/in/petrus-juca) | [GitHub](https://github.com/petrusjuca)



```

>>>>>>> c6898c00455222a84f4f6d526032fd89e5b5504c
