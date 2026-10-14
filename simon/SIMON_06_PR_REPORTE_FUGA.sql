
CREATE OR REPLACE PROCEDURE PR_REPORTE_FUGA
IS
  /*
  ¿A qué problema responde?
    La P1 contó 183 copias fugadas mezclando vigentes con vencidas. La
    gerencia necesita ver por tienda qué copias están fuera y qué hacer.

  ¿Qué dicen los datos?
    183 copias fuera: 182 vigentes y 1 perdida (ACADEMY DINOSAUR, 171
    días, 20,99 USD).

  Supuestos
    Días por calendario hasta FN_FECHA_CORTE (D2). Las bandas son
    privadas del package; aquí solo recorremos tiendas y delegamos.

  Hallazgo e indicador
    Corrección de la P1 y H9. IE2.1.1 e IE2.1.2.
  */
    CURSOR C_TIENDAS IS
    SELECT STORE_ID
      FROM STORE
     ORDER BY STORE_ID;
BEGIN
  DBMS_OUTPUT.PUT_LINE('COPIAS FUERA AL ' ||
                       TO_CHAR(FN_FECHA_CORTE, 'DD/MM/YYYY HH24:MI:SS'));

  -- Delegamos el detalle de cada tienda al procedimineto
  FOR R_TIENDA IN C_TIENDAS LOOP
    PR_REPORTE_FUGA_TIENDA(R_TIENDA.STORE_ID);
  END LOOP;

  -- Cerramos con el total de ambas tiendas
  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('CAPITAL EN RIESGO TOTAL: ' ||
                       TO_CHAR(FN_CAPITAL_EN_RIESGO, 'FM999G990D00') || ' USD');
END PR_REPORTE_FUGA;
/
