# Sakila-Proye

Evaluación Parcial 2 de BDY1103 Taller de Base de Datos, sección 003D, grupo G01: Gabriel Sandoval, Simón Inostroza y Catalina Lobos.

La EP2 convierte los hallazgos de la P1 en 2 packages, 8 procedimientos y funciones sueltos (más 9 miembros públicos dentro de los packages) y 6 triggers que viven dentro de la base Sakila, sin tocar su estructura original.

## Requisitos

- Oracle Database 21c XE
- SQL Developer
- Esquema `SAKILA_BDY1103` instalado con los scripts 1 a 4 de `Sakila DB.zip`

## Estructura

| Carpeta | Contenido |
|---|---|
| `contratos/` | Firmas acordadas en F1. Se suben primero |
| `gabriel/` | Tabla `CLIENTE_MEDALLA`, funciones, procedimientos y `PKG_RESPONSABILIDAD_CLIENTE` |
| `simon/` | Funciones, procedimientos y `PKG_COBRANZA_INVENTARIO` |
| `catalina/` | Tabla `AUDITORIA_SAKILA`, su secuencia y los triggers |
| `pruebas/` | Un bloque por objeto, siempre cerrado con `ROLLBACK` |
| `evidencias/` | Capturas para el Anexo C |
| `build/` | Ensamblado del script final en orden |
| `entregables/` | `INFORME.docx`, `PRESENTACION.pptx` y `SCRIPT.sql` |

## Instalar el esquema base

1. Conectado como `SYSTEM` en la PDB, ejecutar `1. user_sakila_local.sql`.
2. Crear en SQL Developer una conexión con el usuario `SAKILA_BDY1103`.
3. Con esa conexión, ejecutar en orden `2. oracle-sakila-schema.sql`, `3. oracle-sakila-schema-pl-sql.sql` y `4. oracle-sakila-insert-data.sql`.

Para reinstalar desde cero: como `SYSTEM`, `DROP USER SAKILA_BDY1103 CASCADE;` y repetir los pasos. `XX. oracle-sakila-drop-objects.sql` no sirve para esto, porque no borra packages, funciones ni tablas nuevas.

No se debe volver a correr el script 4 sobre un esquema que ya tenga los objetos de la EP2: los triggers de validación rechazarían parte de los datos históricos.

## Verificación de cifras (F0)

Con la conexión `SAKILA_BDY1103`, abrir `pruebas/00_VERIFICACION_H1_H10.sql` y ejecutarlo con Ctrl+Enter.

La consulta compara cada cifra calculada en Oracle con la del plan. Las filas `H1` a `H10` y `P1` deben salir `OK`; si alguna sale `REVISAR`, manda Oracle y se corrige la cifra en el informe.

Las filas `RIESGO` confirman que `PAYMENT_SEQUENCE` y `RENTAL_SEQUENCE` de Sakila parten en 1 y chocan con los IDs cargados, que llegan a 16.049. Deben salir `OK`. Por eso ningún `INSERT` en `PAYMENT` o `RENTAL` omite el ID: ver convenciones.

## Orden del script final

1. Tablas y secuencias nuevas: `CLIENTE_MEDALLA`, `AUDITORIA_SAKILA` y su secuencia, `SEQ_PAYMENT_ID`.
2. `FN_FECHA_CORTE`.
3. Especificaciones de los dos packages.
4. Funciones y procedimientos sueltos.
5. Bodies de los packages.
6. Triggers.
7. Bloques de demostración, cada uno cerrado con `ROLLBACK`.
8. Consultas de evidencia de las cifras H1 a H10.

El script parte con un bloque que borra sus propios objetos si ya existen, para poder correrlo varias veces sin errores.

Luego recolecta las estadísticas del esquema con `DBMS_STATS.GATHER_SCHEMA_STATS`. Los scripts del zip no lo hacen y, sin ellas, Oracle elige planes que recorren `RENTAL` completo por cada cliente o copia: las pruebas pasan de varios minutos a menos de uno.

## Prueba integrada (F4)

1. Como `SYSTEM`: `DROP USER SAKILA_BDY1103 CASCADE;`
2. Scripts 1 a 4 del zip.
3. `entregables/003D-SAKILA-EP2-G01-SCRIPT.sql` completo, de una sola vez.
4. Pasa si `SELECT * FROM USER_ERRORS;` no devuelve filas y todos los objetos nuevos aparecen `VALID` en `USER_OBJECTS`.

## Capturas (Anexo C)

Cada prueba se ejecuta con F5 (Ejecutar script) y se captura la ventana de SQL Developer con la salida del script visible. Las capturas van en `evidencias/` con este nombre:

`<PERSONA>_<NN>_<OBJETO>_EVIDENCIA.jpg`, por ejemplo `GABRIEL_01_FN_FECHA_CORTE_EVIDENCIA.jpg`.

`<NN>_<OBJETO>` es el mismo del archivo de prueba en `pruebas/`. Si la salida no cabe en una captura, las siguientes terminan en `_EVIDENCIA_2.jpg`, `_EVIDENCIA_3.jpg`. La verificación de cifras es `GABRIEL_00_VERIFICACION_H1_H10_EVIDENCIA.jpg` y la prueba integrada, `GABRIEL_07_SCRIPT_FINAL_EVIDENCIA.jpg`.

## Forma de trabajo

- Una rama por persona (`gabriel`, `simon`, `catalina`). Se une a `main` cuando la prueba individual pasa.
- Un issue por objeto. Si depende de otro, lleva la etiqueta `bloqueado-por` con el nombre del objeto que espera.
- Toda prueba que modifica datos termina en `ROLLBACK`. Las cifras del informe salen siempre de la base original.
- Estilo de la P1: palabras reservadas y objetos en mayúsculas, variables con `%TYPE`, prefijos `PKG_`, `SP_`, `FN_`, `TRG_` y nombres en español.

## Convenciones acordadas

- **Comentarios:** solo los que pide el plan, escritos en plural y referidos al código. Cada objeto lleva una cabecera con *¿A qué problema responde?*, *¿Qué dicen los datos?* y *Supuestos*. La especificación de cada package dice qué es público, qué es privado y por qué.
- **Fecha de corte:** `FN_FECHA_CORTE` devuelve `MAX(RENTAL_DATE)` sin truncar, 14/02/2006 15:16:03. Es la única fuente de esa fecha; nadie la escribe a mano.
- **Días de atraso:** se cuentan como Sakila, por días de calendario: `TRUNC(fecha final) - TRUNC(RENTAL_DATE) - RENTAL_DURATION`. Con esa regla calzan los 15.861 pagos de arriendos devueltos.
- **Clientes activos:** `ACTIVE` vale `'1'` o `'Y'` para activo y `'0'` o `'N'` para inactivo.
- **IDs nuevos:** los pagos usan `SEQ_PAYMENT_ID.NEXTVAL`. Las pruebas que insertan en `RENTAL` guardan `MAX(RENTAL_ID) + 1` en una variable antes del `INSERT ... VALUES`.
- **Transacciones:** ningún procedimiento, función ni trigger hace `COMMIT` ni `ROLLBACK`. El que escribe abre un `SAVEPOINT` y, si falla, vuelve a él y hace `RAISE`. Cierra quien llama: la prueba con `ROLLBACK` y el proceso mensual con `COMMIT`.

## Objetos por persona

| Persona | Objetos |
|---|---|
| Gabriel | `CLIENTE_MEDALLA`, `FN_FECHA_CORTE`, `FN_PORCENTAJE_EN_PLAZO`, `FN_PUEDE_ARRENDAR`, `SP_MEDALLA_CLIENTE`, `SP_ACTUALIZA_MEDALLAS`, `PKG_RESPONSABILIDAD_CLIENTE` |
| Simón | `FN_MULTA_CON_TOPE`, `FN_RENTABILIDAD_COPIA`, `FN_CAPITAL_EN_RIESGO`, `PKG_COBRANZA_INVENTARIO` (con `PR_REPORTE_FUGA` y `PR_SIMULA_PLAZO`) |
| Catalina | `AUDITORIA_SAKILA` y su secuencia, `SEQ_PAYMENT_ID`, `TRG_VALIDA_PAGO_RENTAL`, `TRG_TOPE_MULTA_DEVOLUCION`, `TRG_VALIDA_ARRIENDO`, `TRG_BLOQUEA_BORRADO_RENTAL`, `TRG_AUDITA_RENTAL`, `TRG_AUDITA_PAYMENT` |

## Entregables

- `003D-SAKILA-EP2-G01-INFORME.docx`
- `003D-SAKILA-EP2-G01-SCRIPT.sql`
- `003D-SAKILA-EP2-G01-PRESENTACION.pptx`
