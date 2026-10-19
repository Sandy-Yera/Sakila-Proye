/*
¿A qué problema responde?
    Implementamos la responsabilidad del cliente: las funciones sueltas calculan,
    el package decide la medalla y el límite, y orquesta el proceso mensual.
¿Qué dicen los datos?
    Lo esperado cambia según el plazo: en plazo devuelve el 33,1% con 3 días
    y el 76,7% con 7 (H3). Por eso comparamos a cada cliente contra lo esperado
    para las películas que arrendó, y no contra un promedio general.
    En 9 de cada 10 arriendos el cliente tenía 5 copias o menos en casa,
    y en 19 de cada 20, 6 o menos.
Supuestos:
    Índice ajustado = porcentaje en plazo del cliente / porcentaje esperado.
    1,00 es comportarse como el promedio para los plazos que eligió.
    ORO desde 1,20, PLATA desde 0,90 y BRONCE bajo 0,90: quedan 78, 347 y 174 clientes.
    Copias en casa a la vez: BRONCE 5, PLATA 6 y ORO 8. SIN DATOS usa el de BRONCE.
    Umbrales y límites son decisiones de política, no datos: por eso son privados.
    FN_TASA_ESPERADA usa la caché de resultados de Oracle: la tasa de cada plazo
    se calcula una vez y se recalcula sola si cambian RENTAL, INVENTORY o FILM.
    Ningún procedimiento hace COMMIT ni ROLLBACK: usamos SAVEPOINT y RAISE (D7).
Hallazgo e indicador:
    H3, H5 · IE2.2.1, IE2.2.2
*/
CREATE OR REPLACE PACKAGE BODY PKG_RESPONSABILIDAD_CLIENTE IS
    C_UMBRAL_ORO    CONSTANT NUMBER := 1.20;
    C_UMBRAL_PLATA  CONSTANT NUMBER := 0.90;
    C_LIMITE_ORO    CONSTANT NUMBER := 8;
    C_LIMITE_PLATA  CONSTANT NUMBER := 6;
    C_LIMITE_BRONCE CONSTANT NUMBER := 5;

    TYPE T_NOMBRES IS VARRAY(4) OF VARCHAR2(10);
    TYPE T_CONTEO  IS TABLE OF NUMBER INDEX BY VARCHAR2(10);

    PROCEDURE PR_IMPRIMIR(P_TEXTO IN VARCHAR2)
    IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(P_TEXTO);
    END PR_IMPRIMIR;

    FUNCTION FN_TASA_ESPERADA(
        P_RENTAL_DURATION IN FILM.RENTAL_DURATION%TYPE,
        P_FECHA_CORTE     IN RENTAL.RENTAL_DATE%TYPE
    )
        RETURN NUMBER
        RESULT_CACHE
    IS
        V_TASA NUMBER;
    BEGIN
        SELECT AVG(CASE WHEN R.RETURN_DATE IS NOT NULL
                         AND TRUNC(R.RETURN_DATE) - TRUNC(R.RENTAL_DATE) <= F.RENTAL_DURATION
                        THEN 1 ELSE 0 END)
        INTO V_TASA
        FROM RENTAL R
        JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
        JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
        WHERE F.RENTAL_DURATION = P_RENTAL_DURATION
          AND (R.RETURN_DATE IS NOT NULL
               OR TRUNC(P_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) > F.RENTAL_DURATION);

        RETURN V_TASA;
    END FN_TASA_ESPERADA;

    FUNCTION FN_INDICE_AJUSTADO(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
        RETURN NUMBER
    IS
        V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
        V_REAL        NUMBER := FN_PORCENTAJE_EN_PLAZO(P_CUSTOMER_ID);
        V_ESPERADO    NUMBER := 0;
        V_ARRIENDOS   NUMBER := 0;
    BEGIN
        IF V_REAL IS NULL THEN
            RETURN NULL;
        END IF;

        FOR R_PLAZO IN (
            SELECT F.RENTAL_DURATION,
                   COUNT(*) AS ARRIENDOS
            FROM RENTAL R
            JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
            JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
            WHERE R.CUSTOMER_ID = P_CUSTOMER_ID
              AND (R.RETURN_DATE IS NOT NULL
                   OR TRUNC(V_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) > F.RENTAL_DURATION)
            GROUP BY F.RENTAL_DURATION
        ) LOOP
            V_ESPERADO  := V_ESPERADO
                           + R_PLAZO.ARRIENDOS * FN_TASA_ESPERADA(R_PLAZO.RENTAL_DURATION, V_FECHA_CORTE);
            V_ARRIENDOS := V_ARRIENDOS + R_PLAZO.ARRIENDOS;
        END LOOP;

        IF V_ESPERADO = 0 THEN
            RETURN NULL;
        END IF;

        RETURN V_REAL / (100 * V_ESPERADO / V_ARRIENDOS);
    END FN_INDICE_AJUSTADO;

    FUNCTION FN_MEDALLA(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
        RETURN CLIENTE_MEDALLA.MEDALLA%TYPE
    IS
        V_INDICE NUMBER := FN_INDICE_AJUSTADO(P_CUSTOMER_ID);
    BEGIN
        IF V_INDICE IS NULL THEN
            RETURN 'SIN DATOS';
        ELSIF V_INDICE >= C_UMBRAL_ORO THEN
            RETURN 'ORO';
        ELSIF V_INDICE >= C_UMBRAL_PLATA THEN
            RETURN 'PLATA';
        END IF;

        RETURN 'BRONCE';
    END FN_MEDALLA;

    FUNCTION FN_LIMITE_ARRIENDOS(P_MEDALLA IN CLIENTE_MEDALLA.MEDALLA%TYPE)
        RETURN NUMBER
    IS
    BEGIN
        RETURN CASE P_MEDALLA
                   WHEN 'ORO'   THEN C_LIMITE_ORO
                   WHEN 'PLATA' THEN C_LIMITE_PLATA
                   ELSE C_LIMITE_BRONCE
               END;
    END FN_LIMITE_ARRIENDOS;

    PROCEDURE PR_REPORTE_TIENDA(P_STORE_ID IN STORE.STORE_ID%TYPE)
    IS
        CURSOR C_CLIENTES(P_TIENDA STORE.STORE_ID%TYPE) IS
            SELECT CUSTOMER_ID
            FROM CUSTOMER
            WHERE STORE_ID = P_TIENDA
            ORDER BY CUSTOMER_ID;

        V_MEDALLAS T_NOMBRES := T_NOMBRES('ORO', 'PLATA', 'BRONCE', 'SIN DATOS');
        V_MOTIVOS  T_NOMBRES := T_NOMBRES('SI', 'INACTIVO', 'ATRASO', 'LIMITE');
        V_POR_MEDALLA T_CONTEO;
        V_POR_MOTIVO  T_CONTEO;
        V_CIUDAD      CITY.CITY%TYPE;
        V_PAIS        COUNTRY.COUNTRY%TYPE;
        V_MEDALLA     CLIENTE_MEDALLA.MEDALLA%TYPE;
        V_MOTIVO      VARCHAR2(10);
        V_PROMEDIO    NUMBER;
        V_TOTAL       NUMBER := 0;
    BEGIN
        BEGIN
            SELECT CI.CITY, CO.COUNTRY
            INTO V_CIUDAD, V_PAIS
            FROM STORE ST
            JOIN ADDRESS AD ON AD.ADDRESS_ID = ST.ADDRESS_ID
            JOIN CITY CI    ON CI.CITY_ID    = AD.CITY_ID
            JOIN COUNTRY CO ON CO.COUNTRY_ID = CI.COUNTRY_ID
            WHERE ST.STORE_ID = P_STORE_ID;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20103, 'La tienda ' || P_STORE_ID || ' no existe.');
        END;

        FOR I IN 1 .. V_MEDALLAS.COUNT LOOP
            V_POR_MEDALLA(V_MEDALLAS(I)) := 0;
        END LOOP;

        FOR I IN 1 .. V_MOTIVOS.COUNT LOOP
            V_POR_MOTIVO(V_MOTIVOS(I)) := 0;
        END LOOP;

        FOR R_CLIENTE IN C_CLIENTES(P_STORE_ID) LOOP
            SP_MEDALLA_CLIENTE(R_CLIENTE.CUSTOMER_ID, V_MEDALLA);
            V_MOTIVO := FN_PUEDE_ARRENDAR(R_CLIENTE.CUSTOMER_ID);

            V_POR_MEDALLA(V_MEDALLA) := V_POR_MEDALLA(V_MEDALLA) + 1;
            V_POR_MOTIVO(V_MOTIVO)   := V_POR_MOTIVO(V_MOTIVO) + 1;
            V_TOTAL := V_TOTAL + 1;
        END LOOP;

        SELECT ROUND(AVG(FN_PORCENTAJE_EN_PLAZO(CUSTOMER_ID)), 1)
        INTO V_PROMEDIO
        FROM CUSTOMER
        WHERE STORE_ID = P_STORE_ID;

        PR_IMPRIMIR(' ');
        PR_IMPRIMIR('=== TIENDA ' || P_STORE_ID || ' | ' || V_CIUDAD || ', ' || V_PAIS || ' ===');
        PR_IMPRIMIR('Clientes: ' || V_TOTAL || ' | % en plazo promedio: ' || V_PROMEDIO);
        PR_IMPRIMIR('Medallas vigentes:');
        FOR I IN 1 .. V_MEDALLAS.COUNT LOOP
            PR_IMPRIMIR('  ' || RPAD(V_MEDALLAS(I), 12) || LPAD(V_POR_MEDALLA(V_MEDALLAS(I)), 5));
        END LOOP;
        PR_IMPRIMIR('Puede arrendar hoy:');
        FOR I IN 1 .. V_MOTIVOS.COUNT LOOP
            PR_IMPRIMIR('  ' || RPAD(V_MOTIVOS(I), 12) || LPAD(V_POR_MOTIVO(V_MOTIVOS(I)), 5));
        END LOOP;
    END PR_REPORTE_TIENDA;

    PROCEDURE PR_PROCESO_MENSUAL
    IS
    BEGIN
        SAVEPOINT SV_PROCESO_MENSUAL;

        PR_IMPRIMIR('PROCESO MENSUAL DE RESPONSABILIDAD DEL CLIENTE');
        PR_IMPRIMIR('Fecha de corte: ' || TO_CHAR(FN_FECHA_CORTE, 'DD/MM/YYYY HH24:MI:SS'));

        SP_ACTUALIZA_MEDALLAS;

        FOR R_TIENDA IN (SELECT STORE_ID FROM STORE ORDER BY STORE_ID) LOOP
            PR_REPORTE_TIENDA(R_TIENDA.STORE_ID);
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO SAVEPOINT SV_PROCESO_MENSUAL;
            RAISE;
    END PR_PROCESO_MENSUAL;
END PKG_RESPONSABILIDAD_CLIENTE;
/
