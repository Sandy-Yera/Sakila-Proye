/*
¿A qué problema responde?
    En la P1 la responsabilidad de los clientes se veía solo al correr un bloque
    anónimo a mano. Ahora la medalla de todos se calcula una vez al mes y queda
    guardada para el mesón.
¿Qué dicen los datos?
    Procesamos los 599 clientes y sus 16.044 arriendos en un solo MERGE.
    Resultado: 78 ORO, 347 PLATA y 174 BRONCE (H3).
Supuestos:
    El MERGE inserta al cliente que no tenía medalla y actualiza al que ya tenía una.
    No hacemos COMMIT ni ROLLBACK: abrimos un SAVEPOINT y, si algo falla,
    volvemos a él y relanzamos el error. Cierra la transacción quien llama (D7).
    Es procedimiento porque modifica datos y no devuelve un valor.
Hallazgo e indicador:
    H3 · IE2.1.1, IE2.1.2
*/
CREATE OR REPLACE PROCEDURE SP_ACTUALIZA_MEDALLAS
IS
BEGIN
    SAVEPOINT SV_ACTUALIZA_MEDALLAS;

    MERGE INTO CLIENTE_MEDALLA CM
    USING (
        SELECT C.CUSTOMER_ID,
               PKG_RESPONSABILIDAD_CLIENTE.FN_MEDALLA(C.CUSTOMER_ID) AS MEDALLA,
               FN_PORCENTAJE_EN_PLAZO(C.CUSTOMER_ID)                 AS PORCENTAJE_EN_PLAZO
        FROM CUSTOMER C
    ) ORIGEN
    ON (CM.CUSTOMER_ID = ORIGEN.CUSTOMER_ID)
    WHEN MATCHED THEN
        UPDATE SET CM.MEDALLA             = ORIGEN.MEDALLA,
                   CM.PORCENTAJE_EN_PLAZO = ORIGEN.PORCENTAJE_EN_PLAZO,
                   CM.FECHA_CALCULO       = SYSDATE
    WHEN NOT MATCHED THEN
        INSERT (CUSTOMER_ID, MEDALLA, PORCENTAJE_EN_PLAZO, FECHA_CALCULO)
        VALUES (ORIGEN.CUSTOMER_ID, ORIGEN.MEDALLA, ORIGEN.PORCENTAJE_EN_PLAZO, SYSDATE);

    DBMS_OUTPUT.PUT_LINE('SP_ACTUALIZA_MEDALLAS: ' || SQL%ROWCOUNT || ' clientes procesados.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO SAVEPOINT SV_ACTUALIZA_MEDALLAS;
        RAISE;
END SP_ACTUALIZA_MEDALLAS;
/
