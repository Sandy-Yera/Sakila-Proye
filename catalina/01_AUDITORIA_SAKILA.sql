/*
¿A qué problema responde?
    Sakila no registra quién cambia un arriendo o un pago, ni qué tipo de cambio hizo.
    Guardamos una línea por cada operación sobre RENTAL y PAYMENT para poder rastrearla.
¿Qué dicen los datos?
    15 de las 16 tablas de Sakila guardan solo LAST_UPDATE, que se sobreescribe en cada
    cambio, y ninguna columna guarda el usuario ni la operación (H10). Un DELETE no deja rastro.
Supuestos:
    Las líneas las escriben TRG_AUDITA_RENTAL y TRG_AUDITA_PAYMENT (C5), una por sentencia.
    FECHA usa SYSDATE porque registramos el momento real del cambio; FN_FECHA_CORTE solo
    sirve para calcular atrasos dentro del dataset.
    USUARIO toma USER, el usuario de Oracle que ejecuta la operación.
    SEQ_AUDITORIA_SAKILA parte en 1 porque la tabla nace vacía.
    Si la transacción termina en ROLLBACK, su línea de auditoría también se deshace:
    los triggers no hacen COMMIT (D7).
Hallazgo e indicador:
    H10 · IE2.3.1, IE2.3.2
*/
CREATE SEQUENCE SEQ_AUDITORIA_SAKILA START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE TABLE AUDITORIA_SAKILA (
    ID_AUDITORIA NUMBER        NOT NULL,
    TABLA        VARCHAR2(30)  NOT NULL,
    OPERACION    VARCHAR2(10)  NOT NULL,
    USUARIO      VARCHAR2(128) DEFAULT USER    NOT NULL,
    FECHA        DATE          DEFAULT SYSDATE NOT NULL,
    CONSTRAINT PK_AUDITORIA_SAKILA PRIMARY KEY (ID_AUDITORIA),
    CONSTRAINT CK_AUDITORIA_SAKILA_OPERACION
        CHECK (OPERACION IN ('INSERT', 'UPDATE', 'DELETE'))
);
