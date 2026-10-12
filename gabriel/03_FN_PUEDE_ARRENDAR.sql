/*
¿A qué problema responde?
    Sakila deja arrendar a cualquiera, aunque esté inactivo o tenga copias
    vencidas en casa. Damos una sola respuesta para el mesón y para el
    trigger C3: 'SI' o el motivo del bloqueo.
¿Qué dicen los datos?
    490 clientes hicieron 1.709 arriendos teniendo otra copia vencida en casa (H5).
    15 clientes inactivos registran 404 arriendos (H6).
    En 9 de cada 10 arriendos el cliente tenía 5 copias o menos en casa.
Supuestos:
    Revisamos en orden INACTIVO, ATRASO y LIMITE, y devolvemos el primer motivo que aplique.
    ACTIVE '0' o 'N' es inactivo; '1' o 'Y' es activo (D6).
    ATRASO: tiene una copia sin devolver vencida a FN_FECHA_CORTE, en días de calendario (D2).
    LIMITE: sus copias sin devolver ya llegan al límite de su medalla vigente.
    Lanzamos el error -20102 si el cliente no existe.
    Es función porque devuelve un valor y la usamos en un SELECT y en el trigger C3.
Hallazgo e indicador:
    H5, H6 · IE2.1.3, IE2.1.4
*/
CREATE OR REPLACE FUNCTION FN_PUEDE_ARRENDAR(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
RETURN VARCHAR2
IS
    V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
    V_ACTIVO      CUSTOMER.ACTIVE%TYPE;
    V_VENCIDAS    NUMBER;
    V_EN_CASA     NUMBER;
    V_MEDALLA     CLIENTE_MEDALLA.MEDALLA%TYPE;
BEGIN
    BEGIN
        SELECT ACTIVE
        INTO V_ACTIVO
        FROM CUSTOMER
        WHERE CUSTOMER_ID = P_CUSTOMER_ID;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20102, 'El cliente ' || P_CUSTOMER_ID || ' no existe.');
    END;

    IF V_ACTIVO IN ('0', 'N') THEN
        RETURN 'INACTIVO';
    END IF;

    SELECT COUNT(CASE WHEN TRUNC(V_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) > F.RENTAL_DURATION
                      THEN 1 END),
           COUNT(*)
    INTO V_VENCIDAS, V_EN_CASA
    FROM RENTAL R
    JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
    JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
    WHERE R.CUSTOMER_ID = P_CUSTOMER_ID
      AND R.RETURN_DATE IS NULL;

    IF V_VENCIDAS > 0 THEN
        RETURN 'ATRASO';
    END IF;

    SP_MEDALLA_CLIENTE(P_CUSTOMER_ID, V_MEDALLA);

    IF V_EN_CASA >= PKG_RESPONSABILIDAD_CLIENTE.FN_LIMITE_ARRIENDOS(V_MEDALLA) THEN
        RETURN 'LIMITE';
    END IF;

    RETURN 'SI';
END FN_PUEDE_ARRENDAR;
/
