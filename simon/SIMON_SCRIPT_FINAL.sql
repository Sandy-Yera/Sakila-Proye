create or replace function fn_capital_en_riesgo return number is
  /*
  ¿A qué problema responde?
    Sakila no sabe cuánto tendría que gastar para reponer las copias
    vencidas que siguen fuera, si no vuelven.

  ¿Qué dicen los datos?
    Al corte hay 183 arriendos sin devolver, pero 182 están dentro del
    plazo. Solo 1 copia está vencida, con un costo de reposición de
    20,99 USD.

  Supuestos
    Contamos los días por calendario, como cobra Sakila (D2), hasta
    FN_FECHA_CORTE. Medimos el riesgo con el costo de reposición y no con
    la tarifa, que ya está pagada.

  Hallazgo e indicador
    H9 y corrección de la P1 sobre copias fugadas.
    IE2.1.3 e IE2.1.4.
  */
   v_fecha_corte     date := fn_fecha_corte;
   v_monto_en_riesgo number;
begin
  -- Sumamos el costo de reposición de las copias fuera y vencidas al corte
   select nvl(
      sum(f.replacement_cost),
      0
   )
     into v_monto_en_riesgo
     from rental r
     join inventory i
   on i.inventory_id = r.inventory_id
     join film f
   on f.film_id = i.film_id
    where r.return_date is null
      and trunc(v_fecha_corte) - trunc(r.rental_date) > f.rental_duration;

   return v_monto_en_riesgo;
end fn_capital_en_riesgo;
/







create or replace function fn_rentabilidad_copia (
   p_inventory_id in inventory.inventory_id%type
) return number is 
/*
  ¿A qué problema responde?
    Sakila no sabe qué copias ya se pagaron solas y cuáles siguen debiendo
    su costo de reposición.

  ¿Qué dicen los datos?
    3.331 de 4.581 copias aún no recuperan su costo de reposición; la brecha
    suma 35.009 USD.

  Supuestos
    Los ingresos de una copia son los pagos de sus arriendos, sumando
    tarifa y multa. Los 5 pagos sin RENTAL_ID (H1) no se pueden asignar a
    ninguna copia y quedan fuera. Una copia nunca arrendada devuelve su
    costo en negativo. Un resultado negativo significa que la copia aún
    no se paga sola.

  Hallazgo e indicador
    H7: copias que no se pagan solas.
    IE2.1.3 e IE2.1.4.
  */
   v_replacement_cost film.replacement_cost%type;
   v_ingresos         number;
begin
  -- Obtenemos el costo de reposición; si la copia no existe, salta NO_DATA_FOUND
   select f.replacement_cost
     into v_replacement_cost
     from inventory i
     join film f
   on f.film_id = i.film_id
    where i.inventory_id = p_inventory_id;

  -- Sumamos los pagos de todos los arriendos de la copia; sin arriendos, 0
   select nvl(
      sum(p.amount),
      0
   )
     into v_ingresos
     from rental r
     join payment p
   on p.rental_id = r.rental_id
    where r.inventory_id = p_inventory_id;


   return v_ingresos - v_replacement_cost;
exception
    -- ERROR PARA CUANDO EL INVENTORY_ID NO COINCIDA,  
   when no_data_found then
      raise_application_error(
         -20202,
         'No existe la copia' || p_inventory_id
      );
end fn_rentabilidad_copia;
/





create or replace function fn_multa_con_tope (
   p_inventory_id in inventory.inventory_id%type,
   p_rental_date  in rental.rental_date%type,
   p_return_date  in rental.return_date%type
) return payment.amount%type is
  /*
  ¿A qué problema responde?
    Sakila cobra 1 USD por cada día de atraso sin límite, así que la multa
    puede superar el valor de la copia.

  ¿Qué dicen los datos?
    Las multas suman 20.192 de 67.417 USD (30% del ingreso). Una copia de
    ACADEMY DINOSAUR acumula 171 días de atraso sobre un costo de 20,99 USD.

  Supuestos
    Contamos los días por calendario, como cobra Sakila (D2). Si la copia no
    se ha devuelto, medimos el atraso hasta FN_FECHA_CORTE. No leemos RENTAL
    para que TRG_TOPE_MULTA_DEVOLUCION pueda llamarnos sin tabla mutante.

  Hallazgo e indicador
    H4: la multa es ingreso, no solo castigo.
    H9: la multa sin tope supera el valor de la copia.
    IE2.1.3 e IE2.1.4.
  */
   c_multa_diaria     constant number := 1;
   v_rental_duration  film.rental_duration%type;
   v_replacement_cost film.replacement_cost%type;
   v_dias_atraso      number;
begin
   select f.rental_duration,
          f.replacement_cost
     into
      v_rental_duration,
      v_replacement_cost
     from inventory i
     join film f
   on f.film_id = i.film_id
    where i.inventory_id = p_inventory_id;

  -- Calculamos los días de atraso por calendario; sin devolución, hasta la fecha de corte
   if p_return_date is null then
      v_dias_atraso := trunc(fn_fecha_corte) - trunc(p_rental_date) - v_rental_duration;
   else
      v_dias_atraso := trunc(p_return_date) - trunc(p_rental_date) - v_rental_duration;
   end if;

  -- Evitamos multas negativas cuando la copia vuelve dentro del plazo
   v_dias_atraso := greatest(
      v_dias_atraso,
      0
   );

  -- Aplicamos el tope: la multa nunca supera el costo de reposición
   return least(
      v_dias_atraso * c_multa_diaria,
      v_replacement_cost
   );
exception
   when no_data_found then
      raise_application_error(
         -20201,
         'No existe la copia ' || p_inventory_id
      );
end fn_multa_con_tope;
/



CREATE OR REPLACE PACKAGE PKG_COBRANZA_INVENTARIO IS 
/*
Problema a solcionar.
- La cobranza, las copias fuera y la rentabilidad del inventario se revisaba
manualmente, y desde la Prueba 1 con bloques sueltos.

Los datos.
- Las multas son el 30% de ingresos (20.192 de 67.417 USD). 183 copias fuera, solo 1 está vencida (20,99 USD).
3.331 de 4.581 copias aún no recuperan su costo, con una brecha de 35.009 USD y 42 películas no tienen copias.

Supuestos
- Contamos los días por calendario hasta FN_FECHA_CORTE.
LAS BANDAS DE ATRASO (0, 30, 90 Y 180) vienen de la P1.
El package no modifica datos

Qué es publico y porqué
    Los reportes que se hacian manualmente. Quien haga el reporte no necesita
    saber como se clasifican las copias.
    
Qué es privado y porqué
    Los varray de bandas y umbrales, FN_CLASIFICA_BANDA y PR_IMPRIMIR.
    Los umbrales pueden cambiar sin tocar a quien llama el package, y nadie fuera
    de el puede clasificar con otros cortes.
*/

    -- Copias fuera de ambas tiendas, clasificadas por banda, con el capital en riesgo total
    PROCEDURE PR_REPORTE_FUGA;

    -- Copias fuera de una tienda, clasificadas por banda de atraso
    PROCEDURE PR_REPORTE_FUGA_TIENDA (p_store_id IN STORE.STORE_ID%TYPE);

    -- Copias de una tienda que no recuperan su costo y películas sin copia
    PROCEDURE PR_REPORTE_RENTABILIDAD (p_store_id IN STORE.STORE_ID%TYPE);

    -- Atrasos evitados contra multa que se deja de cobrar con más días de plazo
    PROCEDURE PR_SIMULA_PLAZO (p_dias_extra IN NUMBER);

    -- Corre los reportes de fuga y rentabilidad para ambas tiendas
    PROCEDURE PR_PROCESO_MENSUAL;
END PKG_COBRANZA_INVENTARIO;
/


CREATE OR REPLACE PACKAGE BODY PKG_COBRANZA_INVENTARIO IS

  -- Privados: la política de bandas de la P1. Cambiar un umbral es editar un literal.
  TYPE T_UMBRALES IS VARRAY(5) OF NUMBER;
  TYPE T_TEXTOS   IS VARRAY(5) OF VARCHAR2(60);
  TYPE T_MONTOS   IS VARRAY(5) OF NUMBER;

  C_UMBRALES CONSTANT T_UMBRALES := T_UMBRALES(0, 30, 90, 180, 999999);

  C_BANDAS   CONSTANT T_TEXTOS := T_TEXTOS('VIGENTE', 'RECUPERABLE', 'DUDOSA',
                                           'PERDIDA', 'INCOBRABLE');

  C_ACCIONES CONSTANT T_TEXTOS := T_TEXTOS('Sin acción, plazo no vencido',
                                           'Recordatorio y cobro de multa',
                                           'Contacto directo, último aviso',
                                           'Facturar reposición al cliente',
                                           'Castigar activo y bloquear cliente');

  -- Devolvemos la posición de la banda: con ella se obtiene su nombre, su acción y su contador
    FUNCTION FN_CLASIFICA_BANDA (p_dias_atraso IN NUMBER) RETURN PLS_INTEGER IS
    BEGIN
        FOR i IN 1 .. C_UMBRALES.COUNT LOOP
        IF p_dias_atraso <= C_UMBRALES(i) THEN
            RETURN i;
        END IF;
        END LOOP;
        RETURN C_UMBRALES.COUNT;
    END FN_CLASIFICA_BANDA;

  -- Concentramos la salida en un solo lugar: si mañana va a una tabla, cambia solo aquí
    PROCEDURE PR_IMPRIMIR (p_texto IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_texto);
    END PR_IMPRIMIR;

  -- Rechazamos una tienda inexistente con un mensaje claro en vez de un reporte vacío
    PROCEDURE PR_VALIDA_TIENDA (p_store_id IN STORE.STORE_ID%TYPE) IS
        V_STORE_ID STORE.STORE_ID%TYPE;
    BEGIN
        SELECT STORE_ID
        INTO V_STORE_ID
        FROM STORE
        WHERE STORE_ID = p_store_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20204, 'No existe la tienda ' || p_store_id);
    END PR_VALIDA_TIENDA;

    PROCEDURE PR_REPORTE_FUGA_TIENDA (p_store_id IN STORE.STORE_ID%TYPE) IS
    V_FECHA_CORTE DATE := FN_FECHA_CORTE;

    CURSOR C_FUERA (p_tienda STORE.STORE_ID%TYPE) IS
        SELECT R.INVENTORY_ID,
                R.RENTAL_DATE,
                F.TITLE,
                F.REPLACEMENT_COST,
                TRUNC(V_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) - F.RENTAL_DURATION AS DIAS_ATRASO
            FROM RENTAL R
            JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
            JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
        WHERE R.RETURN_DATE IS NULL
            AND I.STORE_ID = p_tienda
        ORDER BY DIAS_ATRASO DESC;

    V_COPIAS  T_MONTOS := T_MONTOS(0, 0, 0, 0, 0);
    V_CAPITAL T_MONTOS := T_MONTOS(0, 0, 0, 0, 0);
    V_MULTA   T_MONTOS := T_MONTOS(0, 0, 0, 0, 0);
    V_BANDA   PLS_INTEGER;

    BEGIN
        PR_VALIDA_TIENDA(p_store_id);

        PR_IMPRIMIR(' ');
        PR_IMPRIMIR('=== TIENDA ' || p_store_id || ' ===');

        -- Clasificamos cada copia fuera y detallamos las que ya vencieron
        FOR R_COPIA IN C_FUERA(p_store_id) LOOP
        V_BANDA := FN_CLASIFICA_BANDA(R_COPIA.DIAS_ATRASO);

        V_COPIAS(V_BANDA)  := V_COPIAS(V_BANDA) + 1;
        V_CAPITAL(V_BANDA) := V_CAPITAL(V_BANDA) + R_COPIA.REPLACEMENT_COST;
        V_MULTA(V_BANDA)   := V_MULTA(V_BANDA) +
                                FN_MULTA_CON_TOPE(R_COPIA.INVENTORY_ID, R_COPIA.RENTAL_DATE, NULL);

        IF V_BANDA > 1 THEN
            PR_IMPRIMIR('  Copia ' || R_COPIA.INVENTORY_ID || ' | ' || R_COPIA.TITLE ||
                        ' | ' || R_COPIA.DIAS_ATRASO || ' días | ' || C_BANDAS(V_BANDA));
        END IF;
        END LOOP;

        PR_IMPRIMIR(RPAD('BANDA', 12) || LPAD('COPIAS', 7) || LPAD('CAPITAL', 11) ||
                    LPAD('MULTA', 11) || '  ACCIÓN SUGERIDA');

        FOR i IN 1 .. C_BANDAS.COUNT LOOP
        PR_IMPRIMIR(RPAD(C_BANDAS(i), 12) ||
                    LPAD(V_COPIAS(i), 7) ||
                    LPAD(TO_CHAR(V_CAPITAL(i), 'FM999G990D00'), 11) ||
                    LPAD(TO_CHAR(V_MULTA(i), 'FM999G990D00'), 11) ||
                    '  ' || C_ACCIONES(i));
        END LOOP;
    END PR_REPORTE_FUGA_TIENDA;

    PROCEDURE PR_REPORTE_FUGA IS
        CURSOR C_TIENDAS IS
        SELECT STORE_ID
            FROM STORE
        ORDER BY STORE_ID;
    BEGIN
        PR_IMPRIMIR('COPIAS FUERA AL ' || TO_CHAR(FN_FECHA_CORTE, 'DD/MM/YYYY HH24:MI:SS'));

        -- Delegamos el detalle de cada tienda a PR_REPORTE_FUGA_TIENDA
        FOR R_TIENDA IN C_TIENDAS LOOP
            PR_REPORTE_FUGA_TIENDA(R_TIENDA.STORE_ID);
        END LOOP;

        -- Cerramos con el total de ambas tiendas
        PR_IMPRIMIR(' ');
        PR_IMPRIMIR('CAPITAL EN RIESGO TOTAL: ' ||
            TO_CHAR(FN_CAPITAL_EN_RIESGO, 'FM999G990D00') || ' USD');
    END PR_REPORTE_FUGA;

    PROCEDURE PR_REPORTE_RENTABILIDAD (p_store_id IN STORE.STORE_ID%TYPE) IS
        CURSOR C_COPIAS (p_tienda STORE.STORE_ID%TYPE) IS
        SELECT INVENTORY_ID
            FROM INVENTORY
        WHERE STORE_ID = p_tienda;

    V_COPIAS          NUMBER := 0;
    V_SIN_RECUPERAR   NUMBER := 0;
    V_BRECHA          NUMBER := 0;
    V_RESULTADO       NUMBER;
    V_SIN_COPIA_TDA   NUMBER;
    V_SIN_COPIA_TOTAL NUMBER;

    BEGIN
        PR_VALIDA_TIENDA(p_store_id);

        -- Medimos cada copia de la tienda contra su costo de reposición
        FOR R_COPIA IN C_COPIAS(p_store_id) LOOP
        V_COPIAS    := V_COPIAS + 1;
        V_RESULTADO := FN_RENTABILIDAD_COPIA(R_COPIA.INVENTORY_ID);

        IF V_RESULTADO < 0 THEN
            V_SIN_RECUPERAR := V_SIN_RECUPERAR + 1;
            V_BRECHA        := V_BRECHA - V_RESULTADO;
        END IF;
        END LOOP;

        -- Películas del catálogo sin copia en esta tienda y sin copia en ninguna (H8)
        SELECT COUNT(*)
        INTO V_SIN_COPIA_TDA
        FROM FILM F
        WHERE NOT EXISTS (SELECT 1
                            FROM INVENTORY I
                            WHERE I.FILM_ID  = F.FILM_ID
                            AND I.STORE_ID = p_store_id);

        SELECT COUNT(*)
        INTO V_SIN_COPIA_TOTAL
        FROM FILM F
        WHERE NOT EXISTS (SELECT 1 FROM INVENTORY I WHERE I.FILM_ID = F.FILM_ID);

        PR_IMPRIMIR(' ');
        PR_IMPRIMIR('=== RENTABILIDAD TIENDA ' || p_store_id || ' ===');
        PR_IMPRIMIR('Copias en inventario: ' || V_COPIAS);
        PR_IMPRIMIR('Copias que aún no recuperan su costo: ' || V_SIN_RECUPERAR);
        PR_IMPRIMIR('Brecha por recuperar: ' || TO_CHAR(V_BRECHA, 'FM999G990D00') || ' USD');
        PR_IMPRIMIR('Películas sin copia en esta tienda: ' || V_SIN_COPIA_TDA);
        PR_IMPRIMIR('Películas sin copia en ninguna tienda: ' || V_SIN_COPIA_TOTAL);
    END PR_REPORTE_RENTABILIDAD;

    PROCEDURE PR_SIMULA_PLAZO (p_dias_extra IN NUMBER) IS
    V_DEVUELTOS        NUMBER;
    V_ATRASOS_ACTUAL   NUMBER;
    V_ATRASOS_SIMULADO NUMBER;
    V_MULTA_ACTUAL     NUMBER;
    V_MULTA_SIMULADA   NUMBER;
    V_INGRESO_TOTAL    NUMBER;
    E_DIAS_INVALIDOS   EXCEPTION;
  BEGIN
    IF p_dias_extra IS NULL OR p_dias_extra < 0 THEN
      RAISE E_DIAS_INVALIDOS;
    END IF;

    -- Calculamos la multa actual y la simulada una vez por arriendo
    SELECT COUNT(*),
           COUNT(CASE WHEN M_ACTUAL   > 0 THEN 1 END),
           COUNT(CASE WHEN M_SIMULADA > 0 THEN 1 END),
           NVL(SUM(M_ACTUAL), 0),
           NVL(SUM(M_SIMULADA), 0)
      INTO V_DEVUELTOS, V_ATRASOS_ACTUAL, V_ATRASOS_SIMULADO,
           V_MULTA_ACTUAL, V_MULTA_SIMULADA
      FROM (SELECT FN_MULTA_CON_TOPE(R.INVENTORY_ID, R.RENTAL_DATE, R.RETURN_DATE) AS M_ACTUAL,
                   FN_MULTA_CON_TOPE(R.INVENTORY_ID, R.RENTAL_DATE + p_dias_extra, R.RETURN_DATE) AS M_SIMULADA
              FROM RENTAL R
             WHERE R.RETURN_DATE IS NOT NULL);

    SELECT SUM(AMOUNT) INTO V_INGRESO_TOTAL FROM PAYMENT;

    PR_IMPRIMIR('SIMULACIÓN CON ' || p_dias_extra || ' DÍAS EXTRA DE PLAZO');
    PR_IMPRIMIR('Arriendos devueltos analizados: ' || V_DEVUELTOS);
    PR_IMPRIMIR('Devoluciones tarde: ' || V_ATRASOS_ACTUAL ||
      ' (' || TO_CHAR(ROUND(V_ATRASOS_ACTUAL / V_DEVUELTOS * 100, 1), 'FM990D0') || '%) -> ' ||
      V_ATRASOS_SIMULADO ||
      ' (' || TO_CHAR(ROUND(V_ATRASOS_SIMULADO / V_DEVUELTOS * 100, 1), 'FM990D0') || '%)');
    PR_IMPRIMIR('Atrasos evitados: ' || (V_ATRASOS_ACTUAL - V_ATRASOS_SIMULADO));
    PR_IMPRIMIR('Multa cobrada: ' || TO_CHAR(V_MULTA_ACTUAL, 'FM999G990D00') ||
      ' USD -> ' || TO_CHAR(V_MULTA_SIMULADA, 'FM999G990D00') || ' USD');
    PR_IMPRIMIR('Multa que se deja de cobrar: ' ||
      TO_CHAR(V_MULTA_ACTUAL - V_MULTA_SIMULADA, 'FM999G990D00') || ' USD (' ||
      TO_CHAR(ROUND((V_MULTA_ACTUAL - V_MULTA_SIMULADA) / V_INGRESO_TOTAL * 100, 1), 'FM990D0') ||
      '% del ingreso)');
  EXCEPTION
    WHEN E_DIAS_INVALIDOS THEN
      RAISE_APPLICATION_ERROR(-20203, 'Los días extra deben ser 0 o más, se recibió: ' ||
                                      NVL(TO_CHAR(p_dias_extra), 'NULL'));
  END PR_SIMULA_PLAZO;

    PROCEDURE PR_PROCESO_MENSUAL IS
        CURSOR C_TIENDAS IS
        SELECT STORE_ID
            FROM STORE
        ORDER BY STORE_ID;
    BEGIN
        PR_REPORTE_FUGA;

        FOR R_TIENDA IN C_TIENDAS LOOP
            PR_REPORTE_RENTABILIDAD(R_TIENDA.STORE_ID);
        END LOOP;
    END PR_PROCESO_MENSUAL;

END PKG_COBRANZA_INVENTARIO;
/
