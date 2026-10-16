SET SERVEROUTPUT ON;

--PRUEBA 1----
-- Contamos las líneas de auditoría antes de las pruebas
SELECT COUNT(*) AS LINEAS_ANTES FROM AUDITORIA_SAKILA;

-- Probamos que un UPDATE de varios arriendos deja una sola línea 
--TRG_AUDITA_RENTAL es de sentencia
BEGIN
    UPDATE RENTAL SET STAFF_ID = STAFF_ID WHERE ROWNUM <= 3;

    DBMS_OUTPUT.PUT_LINE('Prueba 1: se actualizaron ' || SQL%ROWCOUNT || ' arriendos con una sola orden');
END;
/

--PRUEBA2
-- Probamos que borrar un pago queda anotado (TRG_AUDITA_PAYMENT)
DECLARE
    V_PAYMENT_ID PAYMENT.PAYMENT_ID%TYPE;
BEGIN
    SELECT MIN(PAYMENT_ID) INTO V_PAYMENT_ID FROM PAYMENT;

    DELETE FROM PAYMENT WHERE PAYMENT_ID = V_PAYMENT_ID;

    DBMS_OUTPUT.PUT_LINE('Prueba 2: se borró el pago ' || V_PAYMENT_ID);
END;
/

--PRUEBA 3----
-- Probamos que una operación rechazada no se anota: C4 frena el DELETE antes de que ocurra
BEGIN
    DELETE FROM RENTAL WHERE ROWNUM = 1;
    -- ROWNUM se refiere a encontrar las primeras 3 filas

    DBMS_OUTPUT.PUT_LINE('Prueba 3 FALLÓ: se borró un arriendo');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 3: C4 rechazó el borrado, así que no debe quedar línea');
END;
/

-- Revisamos lo que anotó la auditoría las cuales deben ser 2 líneas, RENTAL UPDATE y PAYMENT DELETE
SELECT ID_AUDITORIA, TABLA, OPERACION, USUARIO,
       TO_CHAR(FECHA, 'DD/MM/YYYY HH24:MI:SS') AS FECHA
FROM AUDITORIA_SAKILA
ORDER BY ID_AUDITORIA;

ROLLBACK;

-- Comprobamos que el ROLLBACK borró las líneas y devolvió el pago
SELECT (SELECT COUNT(*) FROM AUDITORIA_SAKILA) AS LINEAS_DESPUES,
       (SELECT COUNT(*) FROM PAYMENT)          AS PAGOS
FROM DUAL;
