/*
A qué problema responde?
    Actualmente en Sakila no queda un registro de quien modifica
    los datos, por ejemplo en fecha de devolucion o si es que borra un pago
    No se registra que proceso realizo

Qué dicen los datos?
    Se muestra que las modificaciones realizadas se guardan en LAST_UPDATE pero
    esta solo menciona la hora del ultimo cambio y se sobreescribe en cada cambio,
    no dice quien fue, y si la fila se borra desaparece con ella. 15 de 16 tablas
    tienen solo LAST_UPDATE y ninguna columna guarda el usuario ni la operacion
    
Supuestos:
    C5 actua junto a AUDITORIA_SAKILA escribiendose en ella.
    Se activa  AFTER para anotar solo lo que si ocurrio,
    al ser de sentencia solo anota una linea por orden, aunque cambie muchas filas.
    Un DELETE en RENTAL nunca llega a anotarse por que C4 lo rechaza antes y si la operacion
    termina en un rollback, su linea tambien se borra.

Hallazgo e indicador:
    H10 · IE2.3.1, IE2.3.2

*/

CREATE OR REPLACE TRIGGER TRG_AUDITA_RENTAL
AFTER INSERT OR UPDATE OR DELETE ON RENTAL
--Se ejecuta despues de la operacion para anotar lo que esta pasando en el momento
DECLARE
    V_OPERACION AUDITORIA_SAKILA.OPERACION%TYPE;
    --Guarda la operacion utilizada
BEGIN
    IF INSERTING THEN
        V_OPERACION := 'INSERT';
    ELSIF UPDATING THEN
        V_OPERACION := 'UPDATE';
    ELSE
        V_OPERACION := 'DELETE';
    END IF;

    INSERT INTO AUDITORIA_SAKILA (ID_AUDITORIA, TABLA, OPERACION)
    VALUES (SEQ_AUDITORIA_SAKILA.NEXTVAL, 'RENTAL', V_OPERACION);
    --Anota una linea en auditoria con la tabla,operacion, quien lo hizo y cuando
END TRG_AUDITA_RENTAL;
/

SELECT OBJECT_NAME, STATUS FROM USER_OBJECTS WHERE OBJECT_NAME = 'TRG_AUDITA_RENTAL';
SELECT * FROM USER_ERRORS WHERE NAME = 'TRG_AUDITA_RENTAL';