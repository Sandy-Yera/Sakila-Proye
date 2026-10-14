
/*
A qué problema responde?
    Debido a que PAYMENT_ID esta ocupado, necesitan uno libre. Existe PAYMENT_SEQUENCE de Sakila pero
    este parte en 1 provocando que choque con los pagos ya hechos, no se puede modificar por lo que se crea una nueva
    secuencia que empieza justo despues del pago mas alto. -> MAX(PAYMENT_ID) + 1
    
Qué dicen los datos?
    PAYMENT tiene 16.049 pagos y su PAYMENT_ID más alto es 16049. Un pago nuevo con
    PAYMENT_SEQUENCE recibiría el 1 y fallaría con ORA-00001
    
Supuestos:
    Calculamos el inicio con MAX(PAYMENT_ID) + 1 al crearla
    pensando que PAYMENT ya tiene sus datos cargados seguimos con un
    START WITH el cual solo acepta un número fijo por eso armamos la orden como texto y la
    ejecutamos dentro de un EXECUTE IMMEDIATE.
    
    La usa TRG_TOPE_MULTA_DEVOLUCION para insertar el pago de la multa.
    Los números que gastan las pruebas cerradas con ROLLBACK no se recuperan; NOCACHE
    evita saltos mayores.
Hallazgo e indicador:
    H4, H9 (la usa C2) y decisión D1 · IE2.3.1
*/
SET SERVEROUTPUT ON;

DECLARE
    V_INICIO PAYMENT.PAYMENT_ID%TYPE;
BEGIN
    -- Buscamos el primer número libre después del pago más alto
    SELECT MAX(PAYMENT_ID) + 1
    INTO V_INICIO
    --Se guarda el PAYMENT_ID dentro de la Variable anonima
    FROM PAYMENT;

    -- Armamos la orden como texto porque START WITH no acepta una consulta
    EXECUTE IMMEDIATE 'CREATE SEQUENCE SEQ_PAYMENT_ID START WITH ' || V_INICIO
                      || ' INCREMENT BY 1 NOCACHE';
END;
/