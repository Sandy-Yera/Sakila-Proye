/*
A qué problema responde?
Si se borra un arriendo, sus pagos quedan sin saber a qué arriendo pertenecen.
Se bloquea el borrado de arriendos para que no se creen más pagos huérfanos.


Qué dicen los datos?
    Se encuentra una linea de codigo en el script de Sakila Schema donde
    se meciona que si se borra un arriendo, a los pagos que apuntaban a él
    se les pone un rental_id vacio


Supuestos:
    Se revisa una sola vez por orden, cualquier delete en RENTAL se rechaza.
    Se activa aunque el delete no encuentre ningún arriendo.
    Solo bloquea borrar; crear arriendos o registrar devoluciones sigue funcionando.
    
    No se cambio la llave de Sakila, solo la protegemos desde afuera.
    Si el DBA necesita borrar algo, apaga el trigger con
    ALTER TRIGGER TRG_BLOQUEA_BORRADO_RENTAL DISABLE y después lo vuelve a encender.


Hallazgo e indicador:
    H2 · IE2.3.1, IE2.3.2

*/

CREATE OR REPLACE TRIGGER TRG_BLOQUEA_BORRADO_RENTAL
BEFORE DELETE ON RENTAL 
--Salta antes de que se elimine un arriendo
BEGIN
    RAISE_APPLICATION_ERROR(-20304, 'No se pueden borrar arriendos: sus pagos quedarían sin arriendo (H2).');
END TRG_BLOQUEA_BORRADO_RENTAL;
/

