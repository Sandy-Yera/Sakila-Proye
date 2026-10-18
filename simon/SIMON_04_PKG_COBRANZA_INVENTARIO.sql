CREATE OR REPLACE PACKAGE PKG_COBRANZA_INVENTARIO IS 
/*
Problema a solcionar.
- La cobranza, las copias fuera y la rentabilidad del inventario se revisaba
manualmente, y desde la Prueba 1 con bloques sueltos.

Los datos.
- Las multas son el 30% de ingresos (20.192 de 67.417 USD). 183 copias fuera, solo 1 está vencida (20,99 USD).
3.331 de 4.581 copias aún no recuperan su costo, con una brecha de 35.009 USD y 42 películas no tienen copias.

Supuestos
- Contamos los días por calendario hasta FN_FECHA_CORTE.
LAS BANDAS DE ATRASO (0, 30, 90 Y 180) vienen de la P1.
El package no modifica datos

Qué es publico y porqué
    Los reportes que se hacian manualmente. Quien haga el reporte no necesita
    saber como se clasifican las copias.
    
Qué es privado y porqué
    Los varray de bandas y umbrales, FN_CLASIFICA_BANDA y PR_IMPRIMIR.
    Los umbrales pueden cambiar sin tocar a quien llama el package, y nadie fuera
    de el puede clasificar con otros cortes.
*/

    -- COPIAS FUERA DE UNA TIENDA, CLASIFICADAS POR BANDA DE ATRASO
    PROCEDURE PR_REPORTE_FUGA_TIENDA(p_store_id IN STORE.STORE_ID%TYPE);
    
    -- COPIAS DE UNA TIENDA QUE NO RECUPERAN SU COSTO Y PELÍCULAS SIN COPIA
    PROCEDURE PR_REPORTE_RENTABILIDAD (p_store_id IN STORE.STORE_ID%TYPE);
    
    -- HARÁ FUNCIONAR AMBOS PROCEDIMIENTOS
    PROCEDURE PR_PROCESO_MENSUAL;
END PKG_COBRANZA_INVENTARIO;
/
