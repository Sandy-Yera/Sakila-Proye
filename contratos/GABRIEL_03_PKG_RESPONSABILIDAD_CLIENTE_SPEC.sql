/*
¿A qué problema responde?
    Juntamos en un solo módulo la responsabilidad del cliente: su medalla,
    su límite de copias en casa, el reporte por tienda y el proceso mensual.
¿Qué dicen los datos?
    El 45,8% de las devoluciones llega tarde, pero el atraso depende más del
    plazo de la película que del cliente: 66,9% con plazo de 3 días y 23,3%
    con plazo de 7 (H3).
Supuestos:
    La medalla compara a cada cliente con lo esperado para los plazos que eligió.
    Los umbrales y los límites son decisiones de política, calibradas con los datos.
Público y privado:
    Público: lo que el mesón y otros programas necesitan llamar.
    FN_MEDALLA y FN_LIMITE_ARRIENDOS se pueden usar dentro de un SELECT.
    PR_REPORTE_TIENDA y PR_PROCESO_MENSUAL los llama la gerencia de sucursal.
    Privado: los umbrales ORO y PLATA, los límites por medalla, FN_TASA_ESPERADA,
    FN_INDICE_AJUSTADO y PR_IMPRIMIR. Son reglas y cálculos internos que podemos
    cambiar sin tocar a quien llama al package.
Hallazgo e indicador:
    H3, H5 · IE2.2.1, IE2.2.2
*/
CREATE OR REPLACE PACKAGE PKG_RESPONSABILIDAD_CLIENTE IS
    FUNCTION FN_MEDALLA(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
        RETURN CLIENTE_MEDALLA.MEDALLA%TYPE;

    FUNCTION FN_LIMITE_ARRIENDOS(P_MEDALLA IN CLIENTE_MEDALLA.MEDALLA%TYPE)
        RETURN NUMBER;

    PROCEDURE PR_REPORTE_TIENDA(P_STORE_ID IN STORE.STORE_ID%TYPE);

    PROCEDURE PR_PROCESO_MENSUAL;
END PKG_RESPONSABILIDAD_CLIENTE;
/
