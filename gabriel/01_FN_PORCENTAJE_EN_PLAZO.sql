/*
¿A qué problema responde?
    Necesitamos medir qué tan puntual es cada cliente para darle su medalla,
    y poder consultarlo dentro de un SELECT sobre CUSTOMER.
¿Qué dicen los datos?
    El 45,8% de las devoluciones llega tarde. Por cliente, el porcentaje en
    plazo va de 16,7% a 88,9%, con mediana de 53,8% (H3).
Supuestos:
    Contamos los días como Sakila, por calendario: TRUNC(fecha final) - TRUNC(RENTAL_DATE) (D2).
    Un arriendo devuelto está en plazo si esos días no superan RENTAL_DURATION.
    Un arriendo sin devolver y ya vencido a FN_FECHA_CORTE cuenta como tarde.
    Uno sin devolver que sigue vigente todavía no se evalúa.
    Devolvemos NULL si el cliente no tiene arriendos que evaluar.
    Es función porque devuelve un valor y la usamos en un SELECT y en el package.
Hallazgo e indicador:
    H3 · IE2.1.3, IE2.1.4
*/
CREATE OR REPLACE FUNCTION FN_PORCENTAJE_EN_PLAZO(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
RETURN NUMBER
IS
    V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
    V_EN_PLAZO    NUMBER;
    V_EVALUABLES  NUMBER;
BEGIN
    SELECT COUNT(CASE WHEN R.RETURN_DATE IS NOT NULL
                       AND TRUNC(R.RETURN_DATE) - TRUNC(R.RENTAL_DATE) <= F.RENTAL_DURATION
                      THEN 1 END),
           COUNT(CASE WHEN R.RETURN_DATE IS NOT NULL
                        OR TRUNC(V_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) > F.RENTAL_DURATION
                      THEN 1 END)
    INTO V_EN_PLAZO, V_EVALUABLES
    FROM RENTAL R
    JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
    JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
    WHERE R.CUSTOMER_ID = P_CUSTOMER_ID;

    IF V_EVALUABLES = 0 THEN
        RETURN NULL;
    END IF;

    RETURN ROUND(100 * V_EN_PLAZO / V_EVALUABLES, 1);
END FN_PORCENTAJE_EN_PLAZO;
/
