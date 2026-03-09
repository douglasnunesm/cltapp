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

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
