SET SERVEROUTPUT ON;



--PRUEBA 1------
-- Probamos que borrar un arriendo dispara el trigger y se rechaza
DECLARE
    V_RENTAL_ID RENTAL.RENTAL_ID%TYPE;
BEGIN
    SELECT MIN(RENTAL_ID) INTO V_RENTAL_ID FROM RENTAL;
    --Busca el primer arriendo Y intenta borrarlo.
    DELETE FROM RENTAL WHERE RENTAL_ID = V_RENTAL_ID;

    DBMS_OUTPUT.PUT_LINE('Prueba 1 FALLÓ: se borró el arriendo ' || V_RENTAL_ID);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 1 LOGRADO, borrado rechazado: ' || SQLERRM);
END;
/
----------------------------------------------------------------------------------------
--PRUEBA 2---
---El trigger se dispara apenas alguien escribe la orden DELETE aunque afecte a 0 filas
-- Probamos que se dispara aunque el DELETE no encuentre arriendos, porque es de sentencia
BEGIN
    DELETE FROM RENTAL WHERE RENTAL_ID = -1;
    --No existe ningún arriendo con número -1, así que este DELETE no borraría nada. Pero aun así C4 lo rechazaria

    DBMS_OUTPUT.PUT_LINE('Prueba 2 FALLÓ: el DELETE sin filas no se rechazó');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 2 LOGRADO, se rechazó aunque no había filas: ' || SQLERRM);
END;
/
-------------------------------------------------------------------------------
---PRUEBA 3---
-- Probamos que un UPDATE en RENTAL no dispara el trigger
DECLARE
    V_RENTAL_ID RENTAL.RENTAL_ID%TYPE;
BEGIN
    SELECT MIN(RENTAL_ID) INTO V_RENTAL_ID FROM RENTAL;

    UPDATE RENTAL SET STAFF_ID = STAFF_ID WHERE RENTAL_ID = V_RENTAL_ID;

    DBMS_OUTPUT.PUT_LINE('Prueba 3 LOGRADO: se actualizó el arriendo ' || V_RENTAL_ID);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 3 FALLIDO: ' || SQLERRM);
END;
/

-----------PRUEBA DE QUE NO SE BORRO NADA-----
SELECT (SELECT COUNT(*) FROM RENTAL)AS ARRIENDOS,
       (SELECT COUNT(*) FROM PAYMENT WHERE RENTAL_ID IS NULL) AS PAGOS_SIN_ARRIENDO
FROM DUAL;

ROLLBACK;