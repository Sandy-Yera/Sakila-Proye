CREATE OR REPLACE PROCEDURE PR_SIMULA_PLAZO(
    P_DIAS_EXTRA IN NUMBER
) IS
/*
  ¿A qué problema responde?
    El 45,8% de las devoluciones llega tarde, pero la multa es el 30% del
    ingreso: alargar el plazo reduce atrasos y también reduce ingresos.

  ¿Qué dicen los datos?
    Con plazo de 3 días el 66,9% llega tarde; con 7 días, el 23,3%. Las
    multas suman 20.192 de 67.417 USD.

  Supuestos
    Recorremos los 15.861 arriendos devueltos. Dar más plazo equivale a
    correr la fecha de arriendo; la multa la calcula FN_MULTA_CON_TOPE.
    Solo lee e imprime.

  Hallazgo e indicador
    H3 y H4. IE2.1.1 e IE2.1.2.

*/
    V_DEVUELTOS        NUMBER;
    V_ATRASOS_ACTUAL   NUMBER;
    V_ATRASOS_SIMULADO NUMBER;
    V_MULTA_ACTUAL     NUMBER;
    V_MULTA_SIMULADA   NUMBER;
    V_INGRESO_TOTAL    NUMBER;
    E_DIAS_INVALIDOS   EXCEPTION;
BEGIN
    IF p_dias_extra IS NULL OR p_dias_extra < 0 THEN
        RAISE E_DIAS_INVALIDOS;
    END IF;
    
    -- Calculamos la multa actual y la simulada una vez por arriendo
    SELECT COUNT(*),
         COUNT(CASE WHEN M_ACTUAL   > 0 THEN 1 END),
         COUNT(CASE WHEN M_SIMULADA > 0 THEN 1 END),
         NVL(SUM(M_ACTUAL), 0),
         NVL(SUM(M_SIMULADA), 0)
    INTO V_DEVUELTOS, V_ATRASOS_ACTUAL, V_ATRASOS_SIMULADO,
         V_MULTA_ACTUAL, V_MULTA_SIMULADA
    FROM (SELECT FN_MULTA_CON_TOPE(R.INVENTORY_ID, R.RENTAL_DATE, R.RETURN_DATE) AS M_ACTUAL,
                 FN_MULTA_CON_TOPE(R.INVENTORY_ID, R.RENTAL_DATE + p_dias_extra, R.RETURN_DATE) AS M_SIMULADA
            FROM RENTAL R
           WHERE R.RETURN_DATE IS NOT NULL);

    SELECT SUM(AMOUNT) INTO V_INGRESO_TOTAL FROM PAYMENT;
    
    DBMS_OUTPUT.PUT_LINE('SIMULACIÓN CON ' || p_dias_extra || ' DÍAS EXTRA DE PLAZO');
    DBMS_OUTPUT.PUT_LINE('Arriendos devueltos analizados: ' || V_DEVUELTOS);
    DBMS_OUTPUT.PUT_LINE('Devoluciones tarde: ' || V_ATRASOS_ACTUAL ||
                        ' (' || TO_CHAR(ROUND(V_ATRASOS_ACTUAL / V_DEVUELTOS * 100, 1), 'FM990D0') || '%) -> ' ||
                        V_ATRASOS_SIMULADO ||
                        ' (' || TO_CHAR(ROUND(V_ATRASOS_SIMULADO / V_DEVUELTOS * 100, 1), 'FM990D0') || '%)');
    DBMS_OUTPUT.PUT_LINE('Atrasos evitados: ' || (V_ATRASOS_ACTUAL - V_ATRASOS_SIMULADO));
    DBMS_OUTPUT.PUT_LINE('Multa cobrada: ' || TO_CHAR(V_MULTA_ACTUAL, 'FM999G990D00') ||
                        ' USD -> ' || TO_CHAR(V_MULTA_SIMULADA, 'FM999G990D00') || ' USD');
    DBMS_OUTPUT.PUT_LINE('Multa que se deja de cobrar: ' ||
                        TO_CHAR(V_MULTA_ACTUAL - V_MULTA_SIMULADA, 'FM999G990D00') || ' USD (' ||
                        TO_CHAR(ROUND((V_MULTA_ACTUAL - V_MULTA_SIMULADA) / V_INGRESO_TOTAL * 100, 1), 'FM990D0') ||
                        '% del ingreso)');

EXCEPTION
  WHEN E_DIAS_INVALIDOS THEN
    RAISE_APPLICATION_ERROR(-20203, 'Los días extra deben ser 0 o más, se recibió: ' || NVL(TO_CHAR(p_dias_extra), 'NULL'));
END PR_SIMULA_PLAZO;
