/*
--Este código es la segunda mitad de C5. Su propósito es dejar registro de todo lo que se hace con los pagos
----un trigger solo puede vigilar una tabla. TRG_AUDITA_RENTAL mira los arriendos y TRG_AUDITA_PAYMENT mira los pagos. 
Juntos formarian C5.

A qué problema responde?
    Actualmente en Sakila no queda un registro de quien modifica
    los pagos, por ejemplo si alguien cambia el monto de un pago o lo borra.
    Tampoco se registra que operacion se realizo (INSERT, UPDATE o DELETE).

Qué dicen los datos?
    Las modificaciones realizadas se guardan en LAST_UPDATE pero
    esta solo menciona la hora del ultimo cambio y se sobreescribe en cada cambio,
    no dice quien fue, y si la fila se borra desaparece con ella. 15 de 16 tablas
    tienen solo LAST_UPDATE y ninguna columna guarda el usuario ni la operacion.
    En PAYMENT esto toca dinero: 16.049 pagos por 67.417 USD sin registro de quien los cambia.

Supuestos:
    C5 actua junto a AUDITORIA_SAKILA escribiendose en ella.
    Se activa despues de la operacion (AFTER), anotando solo lo que si ocurrio.
    Al ser de sentencia solo anota una linea por orden, aunque cambie muchas filas.
    Un DELETE en PAYMENT si queda anotado, porque en PAYMENT no hay un trigger que lo bloquee.
    Tambien anota los pagos de multa que insertara C2, asi queda registro de los cobros automaticos.
    Si la operacion termina en un rollback, su linea tambien se borra.

Hallazgo e indicador:
    H10 · IE2.3.1, IE2.3.2
*/

CREATE OR REPLACE TRIGGER TRG_AUDITA_PAYMENT
AFTER INSERT OR UPDATE OR DELETE ON PAYMENT
--Se ejecuta despues de la operacion para anotar lo que ocurrio en PAYMENT
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
    VALUES (SEQ_AUDITORIA_SAKILA.NEXTVAL, 'PAYMENT', V_OPERACION);
    --Anota una linea en auditoria con la tabla, operacion, quien lo hizo y cuando
END TRG_AUDITA_PAYMENT;
/