/*


A qué problema responde?
    Sakila cobra 1 USD por cada dia de atraso sin limite, asi que la multa puede
    superar lo que vale la copia. Cuando se registra una devolucion con atraso,
    cobramos solo la multa con tope y la anotamos como un pago nuevo.

Qué dicen los datos?
    Las multas son 20.192 de los 67.417 USD de ingreso, cerca del 30%.
    Una copia de ACADEMY DINOSAUR acumula 171 dias de atraso sobre un costo de
    20,99 USD sin tope se cobrarian 171 USD por una copia que vale 20,99.

Supuestos:
    Es de fila y con AFTER UPDATE OF RETURN_DATE cobramos cuando la devolucion ya quedo registrada.
    Solo actua si el arriendo no estaba devuelto y ahora si lo esta (OLD vacio y NEW con fecha)
    asi no cobramos dos veces si alguien corrige una fecha.
    
    El pago nuevo usa SEQ_PAYMENT_ID.NEXTVAL y su fecha es la de la devolucion.
    El INSERT en PAYMENT dispara C1, que lo deja pasar porque trae RENTAL_ID, y C5 que lo anota.
    Si la copia vuelve dentro del plazo, la multa es 0 y no se crea ningun pago.
    
 Conexion:
    El monto lo calcula FN_MULTA_CON_TOPE de Simon, que solo lee INVENTORY y FILM cuando
    recibe una fecha de devolucion. Con el WHEN nunca le pasamos una fecha vacia, porque
    en ese caso leeria RENTAL y daria ORA-04091 (tabla mutante).
    
    

Hallazgo e indicador:
    H4, H9 · IE2.3.1, 
    IE2.3.2
*/

CREATE OR REPLACE TRIGGER TRG_TOPE_MULTA_DEVOLUCION
AFTER UPDATE OF RETURN_DATE ON RENTAL
FOR EACH ROW
WHEN (OLD.RETURN_DATE IS NULL AND NEW.RETURN_DATE IS NOT NULL)
--Se ejecuta cuando un arriendo pasa de no devuelto a devuelto
DECLARE
    V_MULTA PAYMENT.AMOUNT%TYPE;
    --Guarda la multa con tope que calcula la funcion de Simon
BEGIN
    V_MULTA := FN_MULTA_CON_TOPE(:NEW.INVENTORY_ID, :NEW.RENTAL_DATE, :NEW.RETURN_DATE);

    IF V_MULTA > 0 THEN
        INSERT INTO PAYMENT (PAYMENT_ID, CUSTOMER_ID, STAFF_ID, RENTAL_ID, AMOUNT, PAYMENT_DATE)
        VALUES (SEQ_PAYMENT_ID.NEXTVAL, :NEW.CUSTOMER_ID, :NEW.STAFF_ID, :NEW.RENTAL_ID,
                V_MULTA, :NEW.RETURN_DATE);
        --Cobramos la multa como un pago nuevo del mismo cliente y del mismo arriendo
    END IF;
END TRG_TOPE_MULTA_DEVOLUCION;
/

