/*
¿A qué problema responde?
    En la P1 usamos dos fechas de corte distintas: 01/01/2026 y 14/02/2006.
    Con esta función todos los objetos usan la misma y nadie la escribe a mano.
¿Qué dicen los datos?
    El dataset termina con el último arriendo, el 14/02/2006 a las 15:16:03.
    Con SYSDATE cada atraso crecería en más de 20 años.
Supuestos:
    Devolvemos la hora exacta del último arriendo, sin truncar (D3).
    La leemos de RENTAL en cada llamada: si llega un arriendo nuevo, el corte avanza con él.
Hallazgo e indicador:
    Corrección a la P1 · IE2.1.3, IE2.1.4
*/
CREATE OR REPLACE FUNCTION FN_FECHA_CORTE
RETURN DATE
IS
    V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE;
BEGIN
    SELECT MAX(RENTAL_DATE)
    INTO V_FECHA_CORTE
    FROM RENTAL;

    RETURN V_FECHA_CORTE;
END FN_FECHA_CORTE;
/
