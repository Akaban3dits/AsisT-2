# AsisT-2

Aplicación móvil desarrollada en Flutter para el control y gestión de asistencia.
Permite registrar sesiones, administrar asistencias y exportar información de forma organizada y eficiente.

## Getting Started

Este proyecto es una aplicación Flutter enfocada en el registro y análisis de asistencia.
## Features

- Registro de asistencia por sesión
- Base de datos local con SQLite
- Exportación de datos a Excel
- Visualización de estadísticas
- Interfaz optimizada para dispositivos móviles

## Installation

1. Clona el repositorio:

   git clone https://github.com/tu-usuario/attendance_app.git

2. Entra al directorio del proyecto:

   cd attendance_app

3. Instala las dependencias:

   flutter pub get

4. Ejecuta la aplicación:

   flutter run

## Project Structure

lib/
 ├── core/
 ├── features/
 ├── models/
 ├── repository/
 ├── screens/
 └── widgets/

## App Icon

El proyecto utiliza flutter_launcher_icons para generar automáticamente
los iconos de Android e iOS.

Para regenerarlos:

   dart run flutter_launcher_icons
