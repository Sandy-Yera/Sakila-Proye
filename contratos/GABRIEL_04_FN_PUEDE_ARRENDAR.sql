/*
¿A qué problema responde?
    Catalina necesita esta firma para compilar el trigger C3 antes de que exista
    la versión final de gabriel/03_FN_PUEDE_ARRENDAR.sql.
¿Qué dicen los datos?
    490 clientes hicieron 1.709 arriendos teniendo otra copia vencida en casa (H5)
    y 15 clientes inactivos registran 404 arriendos (H6).
Supuestos:
    Versión provisional: responde 'SI' para todo cliente.
    La final devuelve 'SI' o el motivo del bloqueo: 'INACTIVO', 'ATRASO' o 'LIMITE',
    y lanza el error -20102 si el cliente no existe.
Hallazgo e indicador:
    H5, H6 · IE2.1.3, IE2.1.4
*/
CREATE OR REPLACE FUNCTION FN_PUEDE_ARRENDAR(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
RETURN VARCHAR2
IS
BEGIN
    RETURN 'SI';
END FN_PUEDE_ARRENDAR;
/
