# DNS report.ps1

Script de PowerShell 7 que consulta registros DNS (**A**, **MX**, **NS** y **PTR**) para un dominio o una dirección IP, genera un **reporte HTML** con estilo y lo abre automáticamente en el navegador.

---
<img width="1874" height="850" alt="image" src="https://github.com/user-attachments/assets/9624832f-40e6-4f66-b9b2-18bcb4c8dd2f" />


## Índice

- [Características](#características)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Parámetros](#parámetros)
- [Ejemplos](#ejemplos)
- [Salida](#salida)
- [Reporte HTML](#reporte-html)
- [Comportamiento ante errores de guardado](#comportamiento-ante-errores-de-guardado)
- [Notas técnicas](#notas-técnicas)
- [Solución de problemas](#solución-de-problemas)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Licencia](#licencia)

---

## Características

- Acepta **dominio** o **IP** como parámetro (detección automática con `[System.Net.IPAddress]::TryParse`).
- Consulta los siguientes tipos de registro:
  - **A** — direcciones IPv4 del dominio.
  - **MX** — servidores de correo con su prioridad.
  - **NS** — name servers autoritativos.
  - **PTR** — búsqueda inversa (a partir de la primera IP del registro A, o de la IP ingresada).
- Genera un **reporte HTML** con estilo, tablas por tipo de registro, sección de advertencias y sección de errores.
- **Abre el reporte** en el navegador por defecto al finalizar (desactivable con `-NoOpen`).
- **Guardado robusto con fallback automático**: si la ruta pedida falla, reintenta con `\\?\`, luego en `%TEMP%` y finalmente en `C:\Temp`.
- **Sin dependencias externas**: solo módulos nativos de PowerShell.
- Manejo consistente de errores con `try/catch` en cada consulta DNS.

---

## Requisitos

- **PowerShell 7.0 o superior** (`#Requires -Version 7.0`).
- Windows con `Resolve-DnsName` disponible (incluido por defecto en PowerShell 5.1+).
- Permisos de escritura en la ruta de salida, o acceso a `%TEMP%` / `C:\Temp` como fallback.
- Un navegador por defecto configurado (para la apertura automática del reporte).

Verificar la versión instalada:

```powershell
$PSVersionTable.PSVersion
```

---

## Instalación

1. Guardá el script como `dns-report.ps1` en la carpeta que prefieras.
2. (Opcional) Si Windows bloquea la ejecución de scripts, ajustá la política para tu usuario:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

3. Verificá que el script se puede invocar:

```powershell
.\dns-report.ps1 -Target example.com
```

---

## Uso

```powershell
.\dns-report.ps1 -Target <dominio-o-ip> [-OutputPath <ruta>] [-NoOpen]
```

### Sintaxis posicional

El parámetro `-Target` es posicional en la primera posición, y `-OutputPath` en la segunda:

```powershell
.\dns-report.ps1 example.com
.\dns-report.ps1 example.com C:\Temp\reporte.html
```

---

## Parámetros

| Parámetro | Tipo | Obligatorio | Posición | Descripción |
|---|---|---|---|---|
| `-Target` | `string` | Sí | 0 | Dominio (ej: `example.com`) o dirección IP (ej: `8.8.8.8`). |
| `-OutputPath` | `string` | No | 1 | Ruta del HTML de salida. Por defecto: directorio actual con timestamp `DNS-Report-YYYYMMDD-HHmmss.html`. |
| `-NoOpen` | `switch` | No | — | Si se especifica, no abre el reporte en el navegador al finalizar. |

---

## Ejemplos

### Consultar un dominio y abrir el reporte

```powershell
.\dns-report.ps1 -Target example.com
```

Genera `DNS-Report-YYYYMMDD-HHmmss.html` en el directorio actual y lo abre en el navegador.

### Consultar una IP (solo PTR)

```powershell
.\dns-report.ps1 -Target 8.8.8.8
```

Cuando `-Target` es una IP, se omite la consulta A/MX/NS y solo se realiza la búsqueda inversa PTR.

### Guardar el reporte en una ruta específica

```powershell
.\dns-report.ps1 -Target example.com -OutputPath C:\Temp\example.html
```

### Generar el reporte sin abrirlo

```powershell
.\dns-report.ps1 -Target example.com -NoOpen
```

### Uso posicional

```powershell
.\dns-report.ps1 example.com
.\dns-report.ps1 8.8.8.8 C:\Temp\google-dns.html
```

---

## Salida

### Consola

Se muestra en colores el progreso de cada consulta:

```
=== Consultas DNS para: example.com ===
Modo: Dominio (A, MX, NS, PTR)

[1] Registros A para: example.com
  A     www.example.com  ->  93.184.x.x  (TTL 300)

[2] Registros MX para: example.com
  MX    example.com  ->  mx1.example.com  (Pref 10)

[3] Registros NS para: example.com
  NS    example.com  ->  ns1.example.com

[4] Registros PTR para: 93.184.x.x
  Sin PTR para 93.184.x.x. No implica necesariamente Cloudflare; ...

Reporte HTML generado en: C:\Temp\DNS-Report-20260928-121834.html
Abriendo el reporte en el navegador...
```

### Códigos de color

| Color | Significado |
|---|---|
| Cyan | Encabezados e información general. |
| Verde | Registros PTR resueltos / reporte guardado. |
| Amarillo | Advertencias (sin registros de un tipo, fallback de ruta). |
| Magenta | Sin PTR (nota sobre Cloudflare). |
| Rojo | Errores de resolución DNS o de guardado. |
| DarkGray | Detalle de intentos de guardado. |

---

## Reporte HTML

El reporte incluye:

1. **Encabezado**
   - Objetivo consultado.
   - Badge que indica si es `IP` o `Dominio`.
   - Hora de inicio, hora de fin y duración total en segundos.

2. **Tabla de registros A** (solo para dominios)
   - Columnas: Nombre, Dirección IP, TTL.

3. **Tabla de registros MX** (solo para dominios)
   - Columnas: Servidor, Prioridad, TTL.

4. **Tabla de registros NS** (solo para dominios)
   - Columnas: Name Server, TTL.

5. **Tabla de registros PTR**
   - Columnas: IP, Host, TTL.
   - El encabezado incluye la IP consultada.

6. **Sección de Advertencias**
   - Ejemplos: "sin registros MX", "sin registros PTR", "no hay IP para consultar PTR".

7. **Sección de Errores**
   - Fallos de resolución DNS capturados por los `try/catch`.

El HTML es autocontenido (CSS embebido), no requiere conexión a internet ni recursos externos.

---

## Comportamiento ante errores de guardado

Si la ruta indicada en `-OutputPath` (o la ruta por defecto) no es escribible, el script intenta guardar en este orden:

1. `-OutputPath` tal cual se pasó.
2. La misma ruta con prefijo `\\?\` (bypass de canonicalización Win32).
3. `%TEMP%\<nombre>.html`.
4. `C:\Temp\<nombre>.html`.

Para cada candidato se hacen dos intentos:

- `[System.IO.File]::WriteAllText` (crea el archivo si no existe, escribe sin BOM).
- Si falla, `New-Item` + `Set-Content` como fallback.

Si el reporte termina en una ruta distinta a la pedida, se avisa en **amarillo** y se listan los intentos con su estado (`OK` / `FAIL`).

Si **ninguna** ubicación funciona, se muestra el detalle completo de todos los intentos y sus errores.

---

## Notas técnicas

### Por qué `${var}` y no `$var:`

En PowerShell, dentro de una cadena con comillas dobles, `$var:` se interpreta como un *scope modifier* (`$env:PATH`, `$global:foo`, etc.). Si querés interpolar una variable seguida de `:` literal, hay que usar `${var}`:

```powershell
"$Target:"      # ❌ ParserError
"${Target}:"    # ✅ correcto
"$Target :"     # ✅ también funciona (espacio de por medio)
"$($Target):"   # ✅ también funciona (subexpresión)
```

Este script usa `${Target}` y similares en todos los casos donde la variable va seguida de `:`.

### Por qué no se usa `Out-File -LiteralPath`

En PowerShell 5.1 (y en algunas versiones de PS7 con ciertos proveedores), `Out-File -LiteralPath` puede fallar con `Could not find file` cuando el archivo destino no existe todavía, en lugar de crearlo. Este script usa `[System.IO.File]::WriteAllText` como método principal por ser más predecible, y `New-Item` + `Set-Content` como fallback.

### Dirección IP vs dominio

La detección se hace con `[System.Net.IPAddress]::TryParse` (no con regex), lo cual cubre correctamente IPv4 e IPv6.

- Si es **IP** → solo se consulta PTR.
- Si es **dominio** → se consultan A, MX y NS; el PTR se hace contra la primera IP del registro A.

### Ausencia de PTR no implica Cloudflare

Muchas IPs no publican DNS inverso. En particular, el bloque `104.18.0.0/15` pertenece a Cloudflare, y sus IPs de proxy de borde no suelen tener PTR individual. Que no haya PTR **no** es prueba de que el destino sea Cloudflare; es simplemente ausencia de registro inverso.

---

## Solución de problemas

### `La referencia de variable no es válida. ":" no va seguido de un carácter de nombre de variable válido`

**Causa:** una variable va seguida de `:` dentro de una cadena con comillas dobles.

**Solución:** envolver la variable con llaves: `${FQDN}` en lugar de `$FQDN:`.

```powershell
# ❌
Write-Host "Unable to resolve IP for $FQDN: $($_.Exception.Message)"

# ✅
Write-Host "Unable to resolve IP for ${FQDN}: $($_.Exception.Message)"
```

### `Could not find file 'C:\...\DNS-Report-....html'` al guardar

**Síntoma:** el error aparece con `Out-File`, `Set-Content`, `New-Item`, `[System.IO.File]::WriteAllText`, e incluso `cmd /c echo`.

**Causas posibles (en orden de probabilidad):**

1. **Controlled Folder Access** de Windows Defender protegiendo `Documents`. Reporta el bloqueo como *file not found* en vez de *access denied*.
2. Un **antivirus / EDR / DLP** con un filter driver interceptando escrituras.
3. **Corrupción NTFS** o ACLs rotas en la carpeta destino.
4. Carpeta con nombre que contiene **caracteres invisibles** (espacio final, `\u00A0`).

**Diagnóstico:** ejecutá esto desde una consola de PowerShell:

```powershell
$dir = "C:\Users\<usuario>\Documents\...\Scripts"

# ¿Es reparse point?
fsutil reparsepoint query "$dir"

# ¿Puede el kernel escribir?
fsutil file createnew "$dir\dns-test.txt" 0

# ¿Qué dice Defender?
Get-MpPreference | Select-Object EnableControlledFolderAccess, `
    ControlledFolderAccessProtectedFolders, ControlledFolderAccessAllowedApplications

# ¿Funciona en TEMP y C:\Temp?
[System.IO.File]::WriteAllText("$env:TEMP\dns-test.html", "hola")
[System.IO.File]::WriteAllText("C:\Temp\dns-test.html", "hola")
```

**Solución si es Controlled Folder Access** (desde consola **elevada**):

```powershell
$pwsh = (Get-Process -Id $PID).Path
Add-MpPreference -ControlledFolderAccessAllowedApplications $pwsh
```

**Workaround inmediato** (sin tocar el sistema): usar una ruta alternativa.

```powershell
.\dns-report.ps1 -Target example.com -OutputPath C:\Temp\reporte.html
```

El script ya cae automáticamente al fallback, así que aunque `Scripts` esté roto, el reporte se genera igual en `%TEMP%`.

### El reporte no se abre automáticamente

- Verificá que haya un navegador por defecto configurado.
- Si `Start-Process` no encuentra el visor, abrí el HTML manualmente.
- Para desactivar la apertura automática:

```powershell
.\dns-report.ps1 -Target example.com -NoOpen
```

### Los acentos o la `ñ` se ven mal en el reporte

El script guarda el HTML en **UTF-8 sin BOM**. Si tu editor o navegador lo muestra mal, verificá que lo estés abriendo como UTF-8. El HTML ya declara `<meta charset="utf-8">`.

### `Resolve-DnsName` no se reconoce como comando

Verificá que estás usando **PowerShell 7** (o 5.1 en Windows) y no PowerShell Core en Linux/macOS. Este script está pensado para Windows.

```powershell
$PSVersionTable.PSVersion
Get-Command Resolve-DnsName
```

---

## Estructura del proyecto

```
.
├── dns-report.ps1    # Script principal
└── README.md         # Este archivo
```

---

## Licencia

Uso libre. Modificá y adaptá según tus necesidades.
