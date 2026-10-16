/*
Conexion:
    cuando alguien intenta registrar un arriendo nuevo, el trigger le pregunta a la función de Gabriel si ese cliente puede arrendar.
    Si la respuesta no es 'SI', rechaza el arriendo y muestra el motivo
    
A qué problema responde?
    Sakila deja arrendar a cualquier cliente, aunque este inactivo o tenga copias
    vencidas en casa. Rechazamos el arriendo nuevo cuando el cliente no puede arrendar
    y mostramos el motivo.

Qué dicen los datos?
    490 clientes hicieron 1.709 arriendos teniendo otra copia vencida en casa
    y 15 clientes inactivos registran 404 arriendos 

Supuestos:
    Es de fila y con BEFORE INSERT revisamos el cliente de cada arriendo antes de guardarlo.
    La decision la toma FN_PUEDE_ARRENDAR de Gabriel, el trigger solo la hace cumplir.
    Funciona con INSERT...VALUES de una fila. con INSERT...SELECT da ORA-04091
    osea una tabla mutante porque la funcion lee RENTAL. 
    Queda como limitacion. la mejora seria un trigger compuesto.
    No corrige los arriendos antiguos y solo revisa los nuevos.

Hallazgo e indicador:
    H5, H6 · IE2.3.1, IE2.3.2
*/

CREATE OR REPLACE TRIGGER TRG_VALIDA_ARRIENDO
BEFORE INSERT ON RENTAL
FOR EACH ROW
--Se ejecuta antes de guardar cada arriendo nuevo
DECLARE
    V_MOTIVO VARCHAR2(10);
    --Guarda la respuesta de FN_PUEDE_ARRENDAR: 'SI' o el motivo del bloqueo
BEGIN
    V_MOTIVO := FN_PUEDE_ARRENDAR(:NEW.CUSTOMER_ID);

    IF V_MOTIVO <> 'SI' THEN
        RAISE_APPLICATION_ERROR(-20303, 'El cliente ' || :NEW.CUSTOMER_ID
                                        || ' no puede arrendar: ' || V_MOTIVO || '.');
    END IF;
END TRG_VALIDA_ARRIENDO;
/