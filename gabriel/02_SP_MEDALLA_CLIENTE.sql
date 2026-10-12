/*
¿A qué problema responde?
    En el mesón necesitamos la medalla vigente de un cliente para saber
    cuántas copias puede llevarse.
¿Qué dicen los datos?
    Con los umbrales del package, de los 599 clientes 78 son ORO, 347 PLATA
    y 174 BRONCE (H3).
Supuestos:
    La medalla vigente es la que dejó el último proceso mensual en CLIENTE_MEDALLA.
    Si el cliente todavía no tiene una, la calculamos en el momento con
    PKG_RESPONSABILIDAD_CLIENTE.FN_MEDALLA, sin guardarla.
    No escribe en la base: así FN_PUEDE_ARRENDAR puede usarlo dentro de un SELECT.
    Es procedimiento con parámetro OUT porque es una consulta que hace otro
    programa PL/SQL; para usar la medalla en un SELECT existe FN_MEDALLA.
    Lanzamos el error -20101 si el cliente no existe.
Hallazgo e indicador:
    H3 · IE2.1.1, IE2.1.2
*/
CREATE OR REPLACE PROCEDURE SP_MEDALLA_CLIENTE(
    P_CUSTOMER_ID IN  CUSTOMER.CUSTOMER_ID%TYPE,
    P_MEDALLA     OUT CLIENTE_MEDALLA.MEDALLA%TYPE
)
IS
    V_CLIENTES NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO V_CLIENTES
    FROM CUSTOMER
    WHERE CUSTOMER_ID = P_CUSTOMER_ID;

    IF V_CLIENTES = 0 THEN
        RAISE_APPLICATION_ERROR(-20101, 'El cliente ' || P_CUSTOMER_ID || ' no existe.');
    END IF;

    BEGIN
        SELECT MEDALLA
        INTO P_MEDALLA
        FROM CLIENTE_MEDALLA
        WHERE CUSTOMER_ID = P_CUSTOMER_ID;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            P_MEDALLA := PKG_RESPONSABILIDAD_CLIENTE.FN_MEDALLA(P_CUSTOMER_ID);
    END;
END SP_MEDALLA_CLIENTE;
/
