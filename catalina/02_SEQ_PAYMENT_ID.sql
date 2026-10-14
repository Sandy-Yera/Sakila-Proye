/*
¿A qué problema responde?
    Los pagos nuevos necesitan un PAYMENT_ID libre. PAYMENT_SEQUENCE de Sakila parte en 1
    y choca con los pagos ya cargados, y no podemos modificarla. Creamos una secuencia
    propia que parte justo después del pago más alto.
¿Qué dicen los datos?
    PAYMENT tiene 16.049 pagos y su PAYMENT_ID más alto es 16049. Un pago nuevo con
    PAYMENT_SEQUENCE recibiría el 1 y fallaría con ORA-00001 (fila RIESGO de la verificación).
Supuestos:
    Calculamos el inicio con MAX(PAYMENT_ID) + 1 al crearla, sin escribir el número a mano (D1).
    Suponemos que PAYMENT ya tiene sus datos, cargados con los scripts 1 a 4 del zip.
    START WITH solo acepta un número fijo: por eso armamos la orden como texto y la
    ejecutamos con EXECUTE IMMEDIATE.
    La usa TRG_TOPE_MULTA_DEVOLUCION (C2) para insertar el pago de la multa.
    Los números que gastan las pruebas cerradas con ROLLBACK no se recuperan; NOCACHE
    evita saltos mayores.
Hallazgo e indicador:
    H4, H9 (la usa C2) y decisión D1 · IE2.3.1
*/
DECLARE
    V_INICIO PAYMENT.PAYMENT_ID%TYPE;
BEGIN
    -- Buscamos el primer número libre después del pago más alto
    SELECT MAX(PAYMENT_ID) + 1
    INTO V_INICIO
    FROM PAYMENT;

    -- Armamos la orden como texto porque START WITH no acepta una consulta
    EXECUTE IMMEDIATE 'CREATE SEQUENCE SEQ_PAYMENT_ID START WITH ' || V_INICIO
                      || ' INCREMENT BY 1 NOCACHE';
END;
/
