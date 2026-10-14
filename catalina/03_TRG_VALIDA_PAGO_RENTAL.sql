/*
A qué problema responde?
    Se encontraron pagos sin mencion a que arriendo es dirigido, ingresandose con RENTAL_ID nulo. Se crea este
    trigger para cerrarle la puerta a estos registros de pagos incompletos.
    
Qué dicen los datos?
    Los datos dicen que se encontraron 5 registros con un rental_id nulo. Se les habia permitido su ingreso debido a que la tabla
    acepta columnas vacias.
    
Supuestos:
    Se revisa cada pago antes[BEFORE] de que se registren en PAYMENT para lograr rechazarlos en caso de ser nulos, en 
    caso de ser nulo se lanzaria un error.
    No se corregio los 5 pagos nulos solo validamos los pagos nuevos.
    Es trigger y no una validación manual porque se dispara solo y ningún programa lo salta.
    
Hallazgo e indicador:
    H1 · IE2.3.1, IE2.3.2
*/


CREATE OR REPLACE TRIGGER TRG_VALIDA_PAGO_RENTAL
BEFORE INSERT ON PAYMENT
FOR EACH ROW
WHEN (NEW.RENTAL_ID IS NULL) 
--Verficamos que antes de ingresar el registro de pago en PAYMENT, se verifique a donde esta dirigido el arriendo(RENTAL_ID).
BEGIN
    RAISE_APPLICATION_ERROR(-20301, 'El pago del cliente ' || :NEW.CUSTOMER_ID
                                    || ' no indica a qué arriendo corresponde');
END TRG_VALIDA_PAGO_RENTAL;
/

