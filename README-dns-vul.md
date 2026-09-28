# dns-vul.ps1

Script de PowerShell 7 que mide el **factor de amplificación DNS** de un servidor usando **paquetes UDP reales**, detecta si es **open resolver**, y genera un **reporte HTML** (con CSV opcional) que se abre automáticamente en el navegador.

> ⚠️ **Aviso legal**: usar este script contra servidores que no son tuyos o sin autorización explícita por escrito puede violar términos de servicio, leyes de ciberseguridad y ser interpretado como preparación de un ataque DoS. Usalo **solo** contra tu propia infraestructura o en un laboratorio aislado.

---

## Índice

- [Características](#características)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Parámetros](#parámetros)
- [Ejemplos](#ejemplos)
- [Salida](#salida)
- [Reporte HTML](#reporte-html)
- [Interpretación de resultados](#interpretación-de-resultados)
- [Notas técnicas](#notas-técnicas)
- [Solución de problemas](#solución-de-problemas)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Licencia](#licencia)

---

## Características

- **Mide amplificación real** a nivel paquete UDP: compara bytes de consulta vs bytes de respuesta.
- Prueba múltiples tipos de registro: `A`, `ANY`, `TXT`, `NS`, `MX`, `SOA`, `DNSKEY`, `RRSIG`, `NSEC`, `NSEC3`, `CAA`, `SRV`.
- **Detecta open resolver** leyendo los flags `RA` y `RCODE` del header DNS.
- Construye el **paquete DNS a mano** (header + QNAME + QTYPE + QCLASS), sin depender de `Resolve-DnsName` ni de librerías externas.
- Genera un **reporte HTML** con estilo, tabla ordenada por factor de amplificación y veredicto con código de color.
- **Exportación a CSV** opcional.
- **Abre el reporte** en el navegador por defecto (desactivable con `-NoOpen`).
- **Guardado robusto con fallback automático**: si la ruta pedida falla, reintenta con `\\?\`, luego en `%TEMP%` y finalmente en `C:\Temp`.
- **Sin dependencias externas**: solo .NET Framework vía PowerShell.

---

## Requisitos

- **PowerShell 7.0 o superior** (`#Requires -Version 7.0`).
- Windows con acceso **UDP/53 saliente** hacia el servidor objetivo.
- Permisos de escritura en la ruta de salida, o acceso a `%TEMP%` / `C:\Temp` como fallback.
- Un navegador por defecto configurado (para la apertura automática del reporte).

Verificar la versión instalada:

```powershell
$PSVersionTable.PSVersion
```

---

## Instalación

1. Guardá el script como `dns-vul.ps1` en la carpeta que prefieras.
2. (Opcional) Si Windows bloquea la ejecución de scripts, ajustá la política para tu usuario:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

3. Verificá que el script se puede invocar:

```powershell
.\dns-vul.ps1 -DnsServer 10.0.0.53 -TargetDomain example.com
```

---

## Uso

```powershell
.\dns-vul.ps1 -DnsServer <IP> -TargetDomain <dominio> [-Types <lista>] `
              [-TimeoutMs <ms>] [-OutputPath <ruta>] [-ExportCsv] [-NoOpen]
```

---

## Parámetros

| Parámetro | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `-DnsServer` | `string` | Sí | IP del servidor DNS a probar. |
| `-TargetDomain` | `string` | Sí | Dominio sobre el que se hacen las consultas. Ideal: uno tuyo con registros TXT/DNSKEY grandes para medir el peor caso. |
| `-Types` | `string[]` | No | Tipos de registro a probar. Por defecto: `A, ANY, TXT, NS, MX, SOA, DNSKEY, RRSIG, NSEC, NSEC3, CAA, SRV`. |
| `-TimeoutMs` | `int` | No | Timeout por consulta en milisegundos. Por defecto: `2000`. |
| `-OutputPath` | `string` | No | Ruta del HTML de salida. Por defecto: directorio actual con timestamp `DNS-Vul-YYYYMMDD-HHmmss.html`. |
| `-ExportCsv` | `switch` | No | Si se especifica, también exporta un CSV junto al HTML. |
| `-NoOpen` | `switch` | No | Si se especifica, no abre el reporte en el navegador al finalizar. |

---

## Ejemplos

### Batería completa contra tu DNS interno

```powershell
.\dns-vul.ps1 -DnsServer 10.0.0.53 -TargetDomain example.com
```

### Solo vectores modernos, con exportación a CSV

```powershell
.\dns-vul.ps1 -DnsServer 10.0.0.53 -TargetDomain mi-dominio.example `
    -Types TXT,DNSKEY,RRSIG,NSEC -ExportCsv
```

### Sin abrir el navegador

```powershell
.\dns-vul.ps1 -DnsServer 10.0.0.53 -TargetDomain example.com -NoOpen
```

### Timeout más agresivo contra un servidor lento

```powershell
.\dns-vul.ps1 -DnsServer 192.168.1.1 -TargetDomain example.com -TimeoutMs 5000
```

### Guardar el reporte en una ruta específica

```powershell
.\dns-vul.ps1 -DnsServer 10.0.0.53 -TargetDomain example.com `
    -OutputPath C:\Temp\auditoria-dns.html
```

---

## Salida

### Consola

Se muestra en colores el progreso de cada consulta:

```
=== Test de vulnerabilidad / amplificación DNS ===
Servidor: 10.0.0.53
Dominio:  example.com
Tipos:    A, ANY, TXT, NS, MX, SOA, DNSKEY, RRSIG, NSEC, NSEC3, CAA, SRV
Timeout:  2000ms
----------------------------------------

[*] Detectando open resolver...
    -> Es OPEN RESOLVER (responde con recursión a cualquier origen)

  A        query=  33B  resp=   45B  amp=  1.36x
  ANY      query=  33B  resp=   45B  amp=  1.36x
  TXT      query=  33B  resp=  380B  amp= 11.52x
  NS       query=  33B  resp=  120B  amp=  3.64x
  MX       query=  33B  resp=   85B  amp=  2.58x
  ...

Factor máximo: 11.52x  ->  AMPLIFICACIÓN ALTA (abusable)
COMBINACIÓN PELIGROSA: open resolver + amplificación >= 3x

Reporte HTML generado en: C:\Temp\DNS-Vul-20260928-121834.html
Abriendo el reporte en el navegador...
```

### Códigos de color

| Color | Significado |
|---|---|
| Cyan | Encabezado e información general. |
| Amarillo | Detección de open resolver en curso / amplificación moderada. |
| Rojo | Open resolver detectado / amplificación alta / errores. |
| Verde | Amplificación baja / reporte guardado. |
| DarkGray | Detalles e información de estado. |

---

## Reporte HTML

El reporte incluye:

1. **Encabezado**
   - IP del servidor auditado.
   - Badge `OPEN RESOLVER` o `No open resolver`.

2. **Parámetros**
   - Dominio consultado.
   - Tipos probados.
   - Timeout.
   - Hora de inicio, fin y duración.
   - Estado del test de open resolver.

3. **Tabla de resultados por tipo de registro**
   - Columnas: Tipo, Query (B), Respuesta (B), Factor, Estado, Error.
   - Ordenada de mayor a menor factor.
   - Código de color en la columna **Factor**:
     - Verde: `< 3x`.
     - Amarillo: `3x – 10x`.
     - Rojo: `≥ 10x`.

4. **Veredicto**
   - Factor máximo de amplificación.
   - Aviso destacado si el servidor **es open resolver** y tiene amplificación `≥ 3x`.

5. **Notas**
   - Explicación del cálculo del factor.
   - Mitigación RFC 8482 para `ANY`.
   - Vectores modernos recomendados.

El HTML es autocontenido (CSS embebido), no requiere conexión a internet ni recursos externos.

---

## Interpretación de resultados

### Factor de amplificación

| Factor | Interpretación | Acción |
|---|---|---|
| **< 3x** | Sin amplificación significativa. | Nada urgente. |
| **3x – 10x** | Amplificación moderada. | Revisar si es open resolver. |
| **> 10x** | Amplificación alta. | Si es open resolver, mitigar ya. |

### Combinaciones típicas

| Open resolver | Factor máx | Veredicto |
|---|---|---|
| Sí | ≥ 10x | **Crítico**. Vector de DDoS real. Restringir recursión a IPs autorizadas. |
| Sí | 3x – 10x | **Riesgoso**. Revisar. |
| Sí | < 3x | Aceptable si la red está bien filtrada, pero un open resolver nunca es buena idea. |
| No | ≥ 10x | No explotable desde fuera. Documentar y revisar si cambia. |
| No | < 3x | Correcto. |

### Cómo se calcula

```
Factor = Bytes de respuesta UDP / Bytes de consulta UDP
```

- **Bytes de consulta**: tamaño real del paquete DNS que enviamos (header 12B + QNAME + 4B QTYPE/QCLASS).
- **Bytes de respuesta**: tamaño real del paquete UDP recibido (medido con `UdpClient.Receive`).

Es decir, no se estima ni se serializa: se mide el paquete real en el cable.

### Sobre `ANY` y RFC 8482

Desde 2019, la mayoría de servidores modernos (BIND 9.14+, Unbound, Knot, PowerDNS y todos los resolvers públicos) responden a `ANY` con un único registro `HINFO "RFC8482"`. Eso **no** significa que el servidor esté mitigado en general; solo que `ANY` está mitigado. Los vectores modernos a vigilar son `TXT`, `DNSKEY`, `RRSIG`, `NSEC` y `NSEC3`.

### Sobre open resolver

Un servidor es **open resolver** si responde consultas recursivas a **cualquier origen**, no solo a sus clientes legítimos. Esto se detecta leyendo los flags del header DNS:

- `QR` (bit 15): debe ser 1 (es respuesta).
- `RA` (bit 7 del segundo byte): `Recursion Available` = 1.
- `RCODE` (bits 0-3 del segundo byte): `0` = sin error.

Si las tres condiciones se cumplen para una consulta desde tu origen, el servidor es open resolver.

---

## Notas técnicas

### Construcción manual del paquete DNS

El script arma el paquete a mano con `System.IO.BinaryWriter`:

```
[Header 12B][QNAME variable][QTYPE 2B][QCLASS 2B]
```

- **Header**: ID, flags (`RD=1`), QDCOUNT=1, resto 0.
- **QNAME**: cada etiqueta del dominio se escribe como `[longitud][bytes]`, terminando con un byte `0x00`.
- **QTYPE**: número del tipo (A=1, TXT=16, DNSKEY=48, ANY=255, etc.).
- **QCLASS**: `IN = 1`.

### Mapa de tipos DNS

| Nombre | Número |
|---|---|
| A | 1 |
| NS | 2 |
| CNAME | 5 |
| SOA | 6 |
| PTR | 12 |
| MX | 15 |
| TXT | 16 |
| AAAA | 28 |
| SRV | 33 |
| RRSIG | 46 |
| NSEC | 47 |
| DNSKEY | 48 |
| NSEC3 | 50 |
| ANY | 255 |
| CAA | 257 |

### Por qué no se usa `Resolve-DnsName`

`Resolve-DnsName` no expone el tamaño real del paquete UDP; devuelve objetos ya parseados. Para medir amplificación hay que medir bytes en el cable, y para eso se necesita `UdpClient` directo.

### Por qué no se usa `Out-File -LiteralPath`

En PowerShell 5.1 (y en algunas versiones de PS7 con ciertos proveedores), `Out-File -LiteralPath` puede fallar con `Could not find file` cuando el archivo destino no existe todavía. Este script usa `[System.IO.File]::WriteAllText` como método principal y `New-Item` + `Set-Content` como fallback.

---

## Solución de problemas

### Todos los tipos devuelven `ERROR` con timeout

**Causas posibles:**

1. El servidor no responde desde tu IP (filtra consultas de origen).
2. El puerto **UDP/53 saliente** está bloqueado por tu firewall o el de tu red.
3. La IP del DNS server está mal escrita o el host no es alcanzable.

**Diagnóstico:**

```powershell
Test-NetConnection -ComputerName 10.0.0.53 -Port 53 -InformationLevel Detailed
```

**Solución:**
- Verificá que estás en la misma red del servidor o que tu firewall permite UDP/53 saliente hacia esa IP.
- Si estás detrás de una VPN, verificá que enrute el tráfico UDP.

### `Test-OpenResolver` dice "No respondió" pero el servidor sí responde a otros tipos

Puede ser que el servidor bloquee recursión para `example.com` específicamente, o que tu red tenga un split-horizon que no resuelve `example.com`. Probá con otro dominio raíz.

### El factor máximo es `0x` o el veredicto dice "No hubo respuestas válidas"

Significa que ninguna consulta obtuvo respuesta. Verificá conectividad UDP/53 y que el servidor acepte consultas desde tu IP.

### `El término 'X' no se reconoce...` al correr el script

Probablemente estás en **PowerShell 5.1** o en **PowerShell Core para Linux/macOS**. El script requiere PowerShell 7 en Windows.

```powershell
$PSVersionTable.PSVersion
```

### `Could not find file ...` al guardar el HTML

Mismo problema que en `dns-report.ps1`: **Controlled Folder Access** de Windows Defender o un antivirus/filter driver bloqueando escrituras en `Documents`.

El script ya cae automáticamente al fallback (`%TEMP%` o `C:\Temp`). Para atacar la causa raíz, whitelisteá `pwsh.exe` desde una consola elevada:

```powershell
$pwsh = (Get-Process -Id $PID).Path
Add-MpPreference -ControlledFolderAccessAllowedApplications $pwsh
```

### El reporte no se abre automáticamente

- Verificá que haya un navegador por defecto configurado.
- Para desactivar la apertura automática:

```powershell
.\dns-vul.ps1 -DnsServer 10.0.0.53 -TargetDomain example.com -NoOpen
```

### Los acentos o la `ñ` se ven mal en el reporte

El script guarda el HTML en **UTF-8 sin BOM**. Si tu editor o navegador lo muestra mal, verificá que lo estés abriendo como UTF-8. El HTML ya declara `<meta charset="utf-8">`.

---

## Estructura del proyecto

```
.
├── dns-vul.ps1      # Script principal
└── README.md        # Este archivo
```

---

## Licencia

Uso libre. Modificá y adaptá según tus necesidades.

**Recordatorio**: el uso de este script contra servidores de terceros sin autorización puede ser ilegal. Usalo con responsabilidad.
