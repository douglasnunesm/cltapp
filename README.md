# cltapp

A new Flutter project.

## CI/CD (GitHub Actions)

Este projeto possui workflow para gerar APK release automaticamente a cada push na branch `main`:

- Arquivo: `.github/workflows/android-release.yml`
- Artefato gerado: `app-release.apk`

Configure estes secrets no GitHub (`Settings > Secrets and variables > Actions`):

- `ANDROID_KEYSTORE_BASE64` (conteúdo do `.jks` em base64)
- `KEYSTORE_PASSWORD`
- `KEY_ALIAS`
- `KEY_PASSWORD`
- `GOOGLE_SERVICES_JSON_BASE64` (conteudo em base64 do `android/app/google-services.json`)

## Firebase Analytics e Crashlytics

O app esta preparado para enviar eventos de uso (Analytics) e erros/falhas (Crashlytics).

### 1) Dependencias ja adicionadas

- `firebase_core`
- `firebase_analytics`
- `firebase_crashlytics`

### 2) Configurar Firebase no projeto

No diretorio `flutter_app`, execute:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project <SEU_FIREBASE_PROJECT_ID> --platforms=android
```

Isso gera os arquivos de configuracao (incluindo `google-services.json`) para o Android.

### 3) Eventos enviados atualmente

- `calculate_salary`
- `calculate_vacation`
- `calculate_termination`
- `menu_section_open`
- `calculator_tab_open`
- `toggle_dark_mode`

### 4) Validar

```bash
flutter pub get
flutter run
```

No Firebase Console:

- Analytics > DebugView para ver eventos em tempo real
- Crashlytics para erros e falhas

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
