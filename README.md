# Arbeitszeit

Cross-platform Arbeitszeiterfassungs-App mit Flutter (Android + iOS) und vorbereiteter Widget-Anbindung.

## Setup

1. Flutter installieren (im aktuellen Setup wurde Puro verwendet):
	- `winget install --id pingbird.Puro -e`
	- `puro flutter install stable`
2. Abhaengigkeiten installieren:
	- `puro flutter pub get`
3. App starten:
	- `puro flutter run`

## Aktueller Stand

- Start/Stop fuer Arbeitszeit-Tracking
- Tagessumme in Stunden:Minuten
- Lokale Persistenz mit `shared_preferences`
- Grundgeruest fuer Home-Screen-Widget-Sync ueber `home_widget`

## Widget (naechster Schritt)

Native Widget-Targets muessen noch erstellt werden:

- Android: AppWidgetProvider + Layout + Manifest-Eintrag
- iOS: Widget Extension (WidgetKit)

Die Flutter-Seite ist bereits vorbereitet und schreibt `today_duration` via `home_widget`.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
