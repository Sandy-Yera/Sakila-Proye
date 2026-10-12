/*
¿A qué problema responde?
    Guardamos la medalla de cada cliente que calcula el proceso mensual,
    para que el mesón la consulte sin recalcularla en cada arriendo.
¿Qué dicen los datos?
    Los 599 clientes tienen arriendos, pero ninguna tabla de Sakila guarda
    cómo devuelven: solo existe LAST_UPDATE (H3, H10).
Supuestos:
    Una fila por cliente, que el proceso mensual reemplaza con MERGE.
    FECHA_CALCULO registra cuándo corrimos el cálculo, no la fecha de corte.
    SIN DATOS queda para un cliente sin arriendos que evaluar.
Hallazgo e indicador:
    H3, H10 · IE2.2.1
*/
CREATE TABLE CLIENTE_MEDALLA (
    CUSTOMER_ID         INT          NOT NULL,
    MEDALLA             VARCHAR2(10) NOT NULL,
    PORCENTAJE_EN_PLAZO NUMBER(4,1),
    FECHA_CALCULO       DATE         DEFAULT SYSDATE NOT NULL,
    CONSTRAINT PK_CLIENTE_MEDALLA PRIMARY KEY (CUSTOMER_ID),
    CONSTRAINT FK_CLIENTE_MEDALLA_CUSTOMER FOREIGN KEY (CUSTOMER_ID)
        REFERENCES CUSTOMER (CUSTOMER_ID),
    CONSTRAINT CK_CLIENTE_MEDALLA_MEDALLA
        CHECK (MEDALLA IN ('ORO', 'PLATA', 'BRONCE', 'SIN DATOS'))
);
