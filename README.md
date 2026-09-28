# registros DNS

Script de PowerShell 7 que consulta registros DNS (**A**, **MX**, **NS** y **PTR**) para un dominio o una dirección IP, y genera un **reporte HTML** que se abre automáticamente en el navegador.

---

## Características

- Acepta **dominio** o **IP** como parámetro (detección automática).
- Consulta:
  - **A** — direcciones IPv4 del dominio.
  - **MX** — servidores de correo con su prioridad.
  - **NS** — name servers autoritativos.
  - **PTR** — búsqueda inversa (a partir de la primera IP del registro A, o de la IP ingresada).
- Genera un **reporte HTML** con estilo, tablas por tipo de registro, advertencias y errores.
- **Abre el reporte** en el navegador por defecto al finalizar (desactivable con `-NoOpen`).
- **Guardado robusto con fallback automático**: si la ruta pedida falla, reintenta con `\\?\`, luego en `%TEMP%` y finalmente en `C:\Temp`.
- Sin dependencias externas: solo módulos nativos de PowerShell.

---

## Requisitos

- **PowerShell 7.0 o superior** (`#Requires -Version 7.0`).
- Windows con `Resolve-DnsName` disponible (incluido por defecto en PowerShell 5.1+).
- Permisos de escritura en la ruta de salida, o acceso a `%TEMP%` / `C:\Temp` como fallback.

Verificar la versión:

```powershell
$PSVersionTable.PSVersion
