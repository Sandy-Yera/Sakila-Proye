/*
A qué problema responde?
        Soluciona el problema cuando sakila no deja un registro cuando se hace un Insert, Update o Delete a un arriendo o pago y tampoco
    se muestra que tipo de cambio se realizo. Se realiza un guardado por cada operacion sobre rental y payment para poder rastrearla.
    
Que dicen los datos?
    15 de las 16 tablas de Sakila guardan solo LAST_UPDATE, que se sobreescribe en cada
    cambio, y ninguna columna guarda el usuario ni la operación. Un DELETE no deja rastro.
    
Supuestos:
    Las líneas las escriben TRG_AUDITA_RENTAL y TRG_AUDITA_PAYMENT, una por sentencia.
    FECHA usa SYSDATE porque registramos el momento real del cambio; FN_FECHA_CORTE solo
    sirve para calcular atrasos
    USUARIO toma USER osea el usuario de Oracle que ejecuta la operación.
    SEQ_AUDITORIA_SAKILA parte en 1 porque la tabla nace vacía.
    
    Hallazgo e indicador:
    H10 · IE2.3.1, IE2.3.2
*/

CREATE SEQUENCE SEQ_AUDITORIA_SAKILA START WITH 1 INCREMENT BY 1 NOCACHE;
-- La secuencia entrega números que nunca se repiten desde el 1 y subiendo de uno en uno, para identificar cada línea de la auditoría.
CREATE TABLE AUDITORIA_SAKILA (
    ID_AUDITORIA NUMBER        NOT NULL,
    TABLA        VARCHAR2(30)  NOT NULL,
    OPERACION    VARCHAR2(10)  NOT NULL, 
    USUARIO      VARCHAR2(128) DEFAULT USER    NOT NULL,
    FECHA        DATE          DEFAULT SYSDATE NOT NULL, 
    --Se registra con SYSDATE debido a que FN_FECHA_CORTE usa la fecha del 2006 y nosotros queremos el momento del cambio.
    CONSTRAINT PK_AUDITORIA_SAKILA PRIMARY KEY (ID_AUDITORIA), 
    --  no se puede repetir el id ni quedar vacío. 
    CONSTRAINT CK_AUDITORIA_SAKILA_OPERACION
        CHECK (OPERACION IN ('INSERT', 'UPDATE', 'DELETE'))
        --Regla de la tabla donde aceptamos solo estas 3 operaciones.
);