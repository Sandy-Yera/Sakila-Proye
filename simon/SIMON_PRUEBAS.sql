/*
Este script contiene las pruebas de cada función, procedimiento y package creado llamandolos.

FN_MULTA_CON_TOPE(INVENTORY_ID, RENTAL_DATE, RETURN_DATE)



*/

/* =========================================================
   P1 · FN_MULTA_CON_TOPE (función con parámetros) · H4, H9
   ========================================================= */

/*
Test realizado para "FN_MULTA_CON_TOPE", 
aquí buscamos directamente uno de los rental
Se utilizó un rental que se relacione con una pelicula que 
tiene una multa superior al coste de reemplazo
Esperado: 20,99 USD
*/ 
SELECT R.RENTAL_ID,
       F.TITLE,
       FN_MULTA_CON_TOPE(R.INVENTORY_ID, R.RENTAL_DATE, R.RETURN_DATE) AS MULTA_CON_TOPE
  FROM RENTAL R
  JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
  JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
 WHERE F.TITLE = 'ACADEMY DINOSAUR'
   AND R.RETURN_DATE IS NULL;


-- P1.2 Dentro de otro programa PL/SQL: multa teórica de las copias que siguen fuera.
-- Esperado: 183 copias, 1 con multa y 20,99 USD en total.
DECLARE
  CURSOR C_FUERA IS
    SELECT INVENTORY_ID, RENTAL_DATE
      FROM RENTAL
     WHERE RETURN_DATE IS NULL;
 
  V_MULTA      NUMBER;
  V_COPIAS     NUMBER := 0;
  V_CON_MULTA  NUMBER := 0;
  V_TOTAL      NUMBER := 0;
BEGIN
  FOR R_FUERA IN C_FUERA LOOP
    V_MULTA  := FN_MULTA_CON_TOPE(R_FUERA.INVENTORY_ID, R_FUERA.RENTAL_DATE, NULL);
    V_COPIAS := V_COPIAS + 1;
    V_TOTAL  := V_TOTAL + V_MULTA;
    IF V_MULTA > 0 THEN
      V_CON_MULTA := V_CON_MULTA + 1;
    END IF;
  END LOOP;
 
  DBMS_OUTPUT.PUT_LINE('P1.3 Copias fuera: ' || V_COPIAS ||
                       ' | con multa: ' || V_CON_MULTA ||
                       ' | multa teórica: ' || TO_CHAR(V_TOTAL, 'FM999G990D00') || ' USD');
END;
/


-- P1.3
-- Error controlado: No existe la copia 999999
BEGIN
  DBMS_OUTPUT.PUT_LINE(FN_MULTA_CON_TOPE(999999, SYSDATE, SYSDATE));
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('P1.4 ' || SQLERRM);
END;

/* =========================================================
   P2 · FN_RENTABILIDAD_COPIA (función con parámetro) · H7
   ========================================================= */

-- P2.1 En un SELECT sobre las 4.581 copias. Esperado: 3.331 copias y ~35.009 USD.
-- Para las copias que no són rentables, muestra la cantidad de copias que aún no recuperan su costo
-- y cual es su brecha
SELECT COUNT(*)               AS COPIAS_SIN_RECUPERAR,
       ROUND(-SUM(RESULTADO)) AS BRECHA_USD
  FROM (SELECT FN_RENTABILIDAD_COPIA(INVENTORY_ID) AS RESULTADO FROM INVENTORY)
 WHERE RESULTADO < 0;


-- P2.2 En un SELECT: las 5 copias que más lejos están de pagarse solas.
SELECT *
  FROM (SELECT I.INVENTORY_ID,
               F.TITLE,
               I.STORE_ID,
               FN_RENTABILIDAD_COPIA(I.INVENTORY_ID) AS RENTABILIDAD
          FROM INVENTORY I
          JOIN FILM F ON F.FILM_ID = I.FILM_ID
         ORDER BY RENTABILIDAD)
 WHERE ROWNUM <= 5;


/* =========================================================================
   P3 · FN_CAPITAL_EN_RIESGO (función sin parámetros) · H9, corrección P1
   ========================================================================= */

-- P3.1 En un SELECT. Esperado: 20,99.
-- Mostramos el dinero acumulado de reposición de las copias que están fuera de la tienda y están fuera del plazo de la fecha tope
SELECT FN_CAPITAL_EN_RIESGO AS CAPITAL_EN_RIESGO FROM DUAL;

/* =========================================================================
   P4 · PKG_COBRANZA_INVENTARIO (package con miembros públicos y privados)
   ========================================================================= */

-- P4.1 PR_REPORTE_FUGA (sin parámetros) como sentencia SQL.
-- Esperado: 182 copias en VIGENTE, 1 en PERDIDA y capital total 20,99 USD.
-- Genera el reporte de fuga para todas las tiendas.
CALL PKG_COBRANZA_INVENTARIO.PR_REPORTE_FUGA();


-- P4.2 PR_REPORTE_FUGA_TIENDA (con parámetro) dentro de otro programa PL/SQL.
-- Genera el reporet de fuga para el Id de la tienda.
/*

Encabezado: == Tienda 1 == 

Un reporte de cada una de las copias que no están vigentes de mayor a menor atraso.
Copia 1 | ACADEMY DINOSAUR | 171 días | PERDIDA

Resuemn final del reporte
BANDA        COPIAS    CAPITAL      MULTA  ACCIÓN SUGERIDA
VIGENTE          90   1.795,10       0,00  Sin acción, plazo no vencido
RECUPERABLE       0       0,00       0,00  Recordatorio y cobro de multa
DUDOSA            0       0,00       0,00  Contacto directo, último aviso
PERDIDA           1      20,99      20,99  Facturar reposición al cliente
INCOBRABLE        0       0,00       0,00  Castigar activo y bloquear cliente
*/
BEGIN
  PKG_COBRANZA_INVENTARIO.PR_REPORTE_FUGA_TIENDA(1);
END;
/

-- P4.3 PR_REPORTE_RENTABILIDAD (con parámetro) como sentencia SQL.
-- Genera el reporte de rentabilidad del inventario para el ID de la tienda.
/*

Encabezado: === RENTABILIDAD TIENDA 1 ===

Resumen de las copias de la tienda contra su costo de reposición:
Copias en inventario: 2.270
Copias que aún no recuperan su costo: [N]
Brecha por recuperar: [monto] USD

Resumen del catálogo (H8):
Películas sin copia en esta tienda: [N]
Películas sin copia en ninguna tienda: 42

Esperado: entre las dos tiendas suman 4.581 copias, 3.331 sin recuperar
y una brecha de ~35.009 USD. Las 42 películas sin copia son las mismas
en ambos reportes, porque no dependen de la tienda.
*/
CALL PKG_COBRANZA_INVENTARIO.PR_REPORTE_RENTABILIDAD(1);
CALL PKG_COBRANZA_INVENTARIO.PR_REPORTE_RENTABILIDAD(2);


-- P4.4 PR_SIMULA_PLAZO dentro de otro programa PL/SQL: el dilema de 1 a 3 días extra.
-- Esperado: [Monto Multa Esperado] y [% devoluciones tarde]
BEGIN
  FOR i IN 1 .. 3 LOOP
    PKG_COBRANZA_INVENTARIO.PR_SIMULA_PLAZO(i);
    DBMS_OUTPUT.PUT_LINE(' ');
  END LOOP;
END;
/


-- P4.5 PR_PROCESO_MENSUAL (sin parámetros): orquesta fuga y rentabilidad de ambas tiendas.
BEGIN
  PKG_COBRANZA_INVENTARIO.PR_PROCESO_MENSUAL;
END;
/


-- P4.6 Errores controlados. Esperado: ORA-20203 y ORA-20204.
BEGIN
  PKG_COBRANZA_INVENTARIO.PR_SIMULA_PLAZO(-1);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('P4.7 ' || SQLERRM);
END;
/


-- P4.7 Los privados no son visibles desde fuera. Esperado: PLS-00302
-- (el componente FN_CLASIFICA_BANDA debe ser declarado).
BEGIN
  DBMS_OUTPUT.PUT_LINE(PKG_COBRANZA_INVENTARIO.FN_CLASIFICA_BANDA(171));
END;
/
