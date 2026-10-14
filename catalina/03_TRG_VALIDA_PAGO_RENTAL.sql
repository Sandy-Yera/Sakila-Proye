/*
¿A qué problema responde?
    Encontramos pagos que no indican a qué arriendo corresponden: se ingresaron con
    RENTAL_ID nulo. Creamos este trigger para cerrarle la puerta a esos pagos incompletos.
¿Qué dicen los datos?
    5 de los 16.049 pagos tienen RENTAL_ID nulo (H1). Entraron porque la columna RENTAL_ID
    de PAYMENT acepta valores vacíos y nada lo revisaba.
Supuestos:
    Es de fila y BEFORE INSERT: revisamos cada pago antes de guardarlo para poder rechazarlo.
    Solo miramos :NEW, sin consultar RENTAL: C2 inserta pagos mientras actualiza RENTAL,
    y consultarla lanzaría ORA-04091 (tabla mutante).
    Convive con PAYMENT_BEFORE_TRIGGER de Sakila; Oracle no garantiza el orden entre ambos,
    pero no importa porque no usamos PAYMENT_ID.
    No corregimos los 5 pagos históricos: solo validamos los pagos nuevos.
    No hacemos COMMIT ni ROLLBACK (D7): el error -20301 detiene el INSERT y decide quien llama.
    Es trigger y no una validación manual porque se dispara solo y ningún programa lo salta.
Hallazgo e indicador:
    H1 · IE2.3.1, IE2.3.2
*/
CREATE OR REPLACE TRIGGER TRG_VALIDA_PAGO_RENTAL
BEFORE INSERT ON PAYMENT
FOR EACH ROW
WHEN (NEW.RENTAL_ID IS NULL)
BEGIN
    RAISE_APPLICATION_ERROR(-20301, 'El pago del cliente ' || :NEW.CUSTOMER_ID
                                    || ' no indica a qué arriendo corresponde.');
END TRG_VALIDA_PAGO_RENTAL;
/
