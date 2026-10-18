SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 200

PROMPT 003D-SAKILA-EP2-G01 · Script final del grupo G01

PROMPT Borramos los objetos de la EP2 si ya existen

BEGIN
    FOR R_OBJETO IN (
        SELECT OBJECT_NAME, OBJECT_TYPE
        FROM USER_OBJECTS
        WHERE OBJECT_TYPE IN ('TRIGGER', 'PACKAGE', 'PROCEDURE',
                              'FUNCTION', 'TABLE', 'SEQUENCE')
          AND OBJECT_NAME IN ('TRG_TOPE_MULTA_DEVOLUCION', 'TRG_VALIDA_ARRIENDO',
                              'TRG_AUDITA_PAYMENT', 'TRG_AUDITA_RENTAL',
                              'TRG_BLOQUEA_BORRADO_RENTAL', 'TRG_VALIDA_PAGO_RENTAL',
                              'PKG_COBRANZA_INVENTARIO', 'PKG_RESPONSABILIDAD_CLIENTE',
                              'FN_CAPITAL_EN_RIESGO', 'FN_RENTABILIDAD_COPIA',
                              'FN_MULTA_CON_TOPE', 'SP_ACTUALIZA_MEDALLAS',
                              'FN_PUEDE_ARRENDAR', 'SP_MEDALLA_CLIENTE',
                              'FN_PORCENTAJE_EN_PLAZO', 'FN_FECHA_CORTE',
                              'AUDITORIA_SAKILA', 'CLIENTE_MEDALLA',
                              'SEQ_AUDITORIA_SAKILA', 'SEQ_PAYMENT_ID')
        ORDER BY DECODE(OBJECT_TYPE, 'TRIGGER', 1, 'PACKAGE', 2, 'PROCEDURE', 3,
                                     'FUNCTION', 3, 'TABLE', 4, 5)
    ) LOOP
        EXECUTE IMMEDIATE 'DROP ' || R_OBJETO.OBJECT_TYPE || ' ' || R_OBJETO.OBJECT_NAME
            || CASE WHEN R_OBJETO.OBJECT_TYPE = 'TABLE' THEN ' CASCADE CONSTRAINTS' END;
    END LOOP;
END;
/

PROMPT Estadísticas del esquema para que Oracle elija buenos planes

EXEC DBMS_STATS.GATHER_SCHEMA_STATS(USER, NO_INVALIDATE => FALSE)

PROMPT Tablas y secuencias nuevas

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


/*
A qué problema responde?
    Debido a que PAYMENT_ID esta ocupado, necesitan uno libre. Existe PAYMENT_SEQUENCE de Sakila pero
    este parte en 1 provocando que choque con los pagos ya hechos, no se puede modificar por lo que se crea una nueva
    secuencia que empieza justo despues del pago mas alto. -> MAX(PAYMENT_ID) + 1
    
Qué dicen los datos?
    PAYMENT tiene 16.049 pagos y su PAYMENT_ID más alto es 16049. Un pago nuevo con
    PAYMENT_SEQUENCE recibiría el 1 y fallaría con ORA-00001
    
Supuestos:
    Calculamos el inicio con MAX(PAYMENT_ID) + 1 al crearla
    pensando que PAYMENT ya tiene sus datos cargados seguimos con un
    START WITH el cual solo acepta un número fijo por eso armamos la orden como texto y la
    ejecutamos dentro de un EXECUTE IMMEDIATE.
    
    La usa TRG_TOPE_MULTA_DEVOLUCION para insertar el pago de la multa.
    Los números que gastan las pruebas cerradas con ROLLBACK no se recuperan; NOCACHE
    evita saltos mayores.
Hallazgo e indicador:
    H4, H9 (la usa C2) y decisión D1 · IE2.3.1
*/
SET SERVEROUTPUT ON;

DECLARE
    V_INICIO PAYMENT.PAYMENT_ID%TYPE;
BEGIN
    -- Buscamos el primer número libre después del pago más alto
    SELECT MAX(PAYMENT_ID) + 1
    INTO V_INICIO
    --Se guarda el PAYMENT_ID dentro de la Variable anonima
    FROM PAYMENT;

    -- Armamos la orden como texto porque START WITH no acepta una consulta
    EXECUTE IMMEDIATE 'CREATE SEQUENCE SEQ_PAYMENT_ID START WITH ' || V_INICIO
                      || ' INCREMENT BY 1 NOCACHE';
END;
/

PROMPT Fecha de corte

/*
¿A qué problema responde?
    En la P1 usamos dos fechas de corte distintas: 01/01/2026 y 14/02/2006.
    Con esta función todos los objetos usan la misma y nadie la escribe a mano.
¿Qué dicen los datos?
    El dataset termina con el último arriendo, el 14/02/2006 a las 15:16:03.
    Con SYSDATE cada atraso crecería en más de 20 años.
Supuestos:
    Devolvemos la hora exacta del último arriendo, sin truncar (D3).
    La leemos de RENTAL en cada llamada: si llega un arriendo nuevo, el corte avanza con él.
Hallazgo e indicador:
    Corrección a la P1 · IE2.1.3, IE2.1.4
*/
CREATE OR REPLACE FUNCTION FN_FECHA_CORTE
RETURN DATE
IS
    V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE;
BEGIN
    SELECT MAX(RENTAL_DATE)
    INTO V_FECHA_CORTE
    FROM RENTAL;

    RETURN V_FECHA_CORTE;
END FN_FECHA_CORTE;
/

PROMPT Especificaciones de los packages

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

    -- Copias fuera de ambas tiendas, clasificadas por banda, con el capital en riesgo total
    PROCEDURE PR_REPORTE_FUGA;

    -- Copias fuera de una tienda, clasificadas por banda de atraso
    PROCEDURE PR_REPORTE_FUGA_TIENDA (p_store_id IN STORE.STORE_ID%TYPE);

    -- Copias de una tienda que no recuperan su costo y películas sin copia
    PROCEDURE PR_REPORTE_RENTABILIDAD (p_store_id IN STORE.STORE_ID%TYPE);

    -- Atrasos evitados contra multa que se deja de cobrar con más días de plazo
    PROCEDURE PR_SIMULA_PLAZO (p_dias_extra IN NUMBER);

    -- Corre los reportes de fuga y rentabilidad para ambas tiendas
    PROCEDURE PR_PROCESO_MENSUAL;
END PKG_COBRANZA_INVENTARIO;
/

PROMPT Funciones y procedimientos

/*
¿A qué problema responde?
    Necesitamos medir qué tan puntual es cada cliente para darle su medalla,
    y poder consultarlo dentro de un SELECT sobre CUSTOMER.
¿Qué dicen los datos?
    El 45,8% de las devoluciones llega tarde. Por cliente, el porcentaje en
    plazo va de 16,7% a 88,9%, con mediana de 53,8% (H3).
Supuestos:
    Contamos los días como Sakila, por calendario: TRUNC(fecha final) - TRUNC(RENTAL_DATE) (D2).
    Un arriendo devuelto está en plazo si esos días no superan RENTAL_DURATION.
    Un arriendo sin devolver y ya vencido a FN_FECHA_CORTE cuenta como tarde.
    Uno sin devolver que sigue vigente todavía no se evalúa.
    Devolvemos NULL si el cliente no tiene arriendos que evaluar.
    Es función porque devuelve un valor y la usamos en un SELECT y en el package.
Hallazgo e indicador:
    H3 · IE2.1.3, IE2.1.4
*/
CREATE OR REPLACE FUNCTION FN_PORCENTAJE_EN_PLAZO(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
RETURN NUMBER
IS
    V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
    V_EN_PLAZO    NUMBER;
    V_EVALUABLES  NUMBER;
BEGIN
    SELECT COUNT(CASE WHEN R.RETURN_DATE IS NOT NULL
                       AND TRUNC(R.RETURN_DATE) - TRUNC(R.RENTAL_DATE) <= F.RENTAL_DURATION
                      THEN 1 END),
           COUNT(CASE WHEN R.RETURN_DATE IS NOT NULL
                        OR TRUNC(V_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) > F.RENTAL_DURATION
                      THEN 1 END)
    INTO V_EN_PLAZO, V_EVALUABLES
    FROM RENTAL R
    JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
    JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
    WHERE R.CUSTOMER_ID = P_CUSTOMER_ID;

    IF V_EVALUABLES = 0 THEN
        RETURN NULL;
    END IF;

    RETURN ROUND(100 * V_EN_PLAZO / V_EVALUABLES, 1);
END FN_PORCENTAJE_EN_PLAZO;
/

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

/*
¿A qué problema responde?
    Sakila deja arrendar a cualquiera, aunque esté inactivo o tenga copias
    vencidas en casa. Damos una sola respuesta para el mesón y para el
    trigger C3: 'SI' o el motivo del bloqueo.
¿Qué dicen los datos?
    490 clientes hicieron 1.709 arriendos teniendo otra copia vencida en casa (H5).
    15 clientes inactivos registran 404 arriendos (H6).
    En 9 de cada 10 arriendos el cliente tenía 5 copias o menos en casa.
Supuestos:
    Revisamos en orden INACTIVO, ATRASO y LIMITE, y devolvemos el primer motivo que aplique.
    ACTIVE '0' o 'N' es inactivo; '1' o 'Y' es activo (D6).
    ATRASO: tiene una copia sin devolver vencida a FN_FECHA_CORTE, en días de calendario (D2).
    LIMITE: sus copias sin devolver ya llegan al límite de su medalla vigente.
    Lanzamos el error -20102 si el cliente no existe.
    Es función porque devuelve un valor y la usamos en un SELECT y en el trigger C3.
Hallazgo e indicador:
    H5, H6 · IE2.1.3, IE2.1.4
*/
CREATE OR REPLACE FUNCTION FN_PUEDE_ARRENDAR(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
RETURN VARCHAR2
IS
    V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
    V_ACTIVO      CUSTOMER.ACTIVE%TYPE;
    V_VENCIDAS    NUMBER;
    V_EN_CASA     NUMBER;
    V_MEDALLA     CLIENTE_MEDALLA.MEDALLA%TYPE;
BEGIN
    BEGIN
        SELECT ACTIVE
        INTO V_ACTIVO
        FROM CUSTOMER
        WHERE CUSTOMER_ID = P_CUSTOMER_ID;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20102, 'El cliente ' || P_CUSTOMER_ID || ' no existe.');
    END;

    IF V_ACTIVO IN ('0', 'N') THEN
        RETURN 'INACTIVO';
    END IF;

    SELECT COUNT(CASE WHEN TRUNC(V_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) > F.RENTAL_DURATION
                      THEN 1 END),
           COUNT(*)
    INTO V_VENCIDAS, V_EN_CASA
    FROM RENTAL R
    JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
    JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
    WHERE R.CUSTOMER_ID = P_CUSTOMER_ID
      AND R.RETURN_DATE IS NULL;

    IF V_VENCIDAS > 0 THEN
        RETURN 'ATRASO';
    END IF;

    SP_MEDALLA_CLIENTE(P_CUSTOMER_ID, V_MEDALLA);

    IF V_EN_CASA >= PKG_RESPONSABILIDAD_CLIENTE.FN_LIMITE_ARRIENDOS(V_MEDALLA) THEN
        RETURN 'LIMITE';
    END IF;

    RETURN 'SI';
END FN_PUEDE_ARRENDAR;
/

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

create or replace function fn_capital_en_riesgo return number is
  /*
  ¿A qué problema responde?
    Sakila no sabe cuánto tendría que gastar para reponer las copias
    vencidas que siguen fuera, si no vuelven.

  ¿Qué dicen los datos?
    Al corte hay 183 arriendos sin devolver, pero 182 están dentro del
    plazo. Solo 1 copia está vencida, con un costo de reposición de
    20,99 USD.

  Supuestos
    Contamos los días por calendario, como cobra Sakila (D2), hasta
    FN_FECHA_CORTE. Medimos el riesgo con el costo de reposición y no con
    la tarifa, que ya está pagada.

  Hallazgo e indicador
    H9 y corrección de la P1 sobre copias fugadas.
    IE2.1.3 e IE2.1.4.
  */
   v_fecha_corte     date := fn_fecha_corte;
   v_monto_en_riesgo number;
begin
  -- Sumamos el costo de reposición de las copias fuera y vencidas al corte
   select nvl(
      sum(f.replacement_cost),
      0
   )
     into v_monto_en_riesgo
     from rental r
     join inventory i
   on i.inventory_id = r.inventory_id
     join film f
   on f.film_id = i.film_id
    where r.return_date is null
      and trunc(v_fecha_corte) - trunc(r.rental_date) > f.rental_duration;

   return v_monto_en_riesgo;
end fn_capital_en_riesgo;
/

create or replace function fn_rentabilidad_copia (
   p_inventory_id in inventory.inventory_id%type
) return number is 
/*
  ¿A qué problema responde?
    Sakila no sabe qué copias ya se pagaron solas y cuáles siguen debiendo
    su costo de reposición.

  ¿Qué dicen los datos?
    3.331 de 4.581 copias aún no recuperan su costo de reposición; la brecha
    suma 35.009 USD.

  Supuestos
    Los ingresos de una copia son los pagos de sus arriendos, sumando
    tarifa y multa. Los 5 pagos sin RENTAL_ID (H1) no se pueden asignar a
    ninguna copia y quedan fuera. Una copia nunca arrendada devuelve su
    costo en negativo. Un resultado negativo significa que la copia aún
    no se paga sola.

  Hallazgo e indicador
    H7: copias que no se pagan solas.
    IE2.1.3 e IE2.1.4.
  */
   v_replacement_cost film.replacement_cost%type;
   v_ingresos         number;
begin
  -- Obtenemos el costo de reposición; si la copia no existe, salta NO_DATA_FOUND
   select f.replacement_cost
     into v_replacement_cost
     from inventory i
     join film f
   on f.film_id = i.film_id
    where i.inventory_id = p_inventory_id;

  -- Sumamos los pagos de todos los arriendos de la copia; sin arriendos, 0
   select nvl(
      sum(p.amount),
      0
   )
     into v_ingresos
     from rental r
     join payment p
   on p.rental_id = r.rental_id
    where r.inventory_id = p_inventory_id;


   return v_ingresos - v_replacement_cost;
exception
    -- ERROR PARA CUANDO EL INVENTORY_ID NO COINCIDA,  
   when no_data_found then
      raise_application_error(
         -20202,
         'No existe la copia' || p_inventory_id
      );
end fn_rentabilidad_copia;
/

create or replace function fn_multa_con_tope (
   p_inventory_id in inventory.inventory_id%type,
   p_rental_date  in rental.rental_date%type,
   p_return_date  in rental.return_date%type
) return payment.amount%type is
  /*
  ¿A qué problema responde?
    Sakila cobra 1 USD por cada día de atraso sin límite, así que la multa
    puede superar el valor de la copia.

  ¿Qué dicen los datos?
    Las multas suman 20.192 de 67.417 USD (30% del ingreso). Una copia de
    ACADEMY DINOSAUR acumula 171 días de atraso sobre un costo de 20,99 USD.

  Supuestos
    Contamos los días por calendario, como cobra Sakila (D2). Si la copia no
    se ha devuelto, medimos el atraso hasta FN_FECHA_CORTE. No leemos RENTAL
    para que TRG_TOPE_MULTA_DEVOLUCION pueda llamarnos sin tabla mutante.

  Hallazgo e indicador
    H4: la multa es ingreso, no solo castigo.
    H9: la multa sin tope supera el valor de la copia.
    IE2.1.3 e IE2.1.4.
  */
   c_multa_diaria     constant number := 1;
   v_rental_duration  film.rental_duration%type;
   v_replacement_cost film.replacement_cost%type;
   v_dias_atraso      number;
begin
   select f.rental_duration,
          f.replacement_cost
     into
      v_rental_duration,
      v_replacement_cost
     from inventory i
     join film f
   on f.film_id = i.film_id
    where i.inventory_id = p_inventory_id;

  -- Calculamos los días de atraso por calendario; sin devolución, hasta la fecha de corte
   if p_return_date is null then
      v_dias_atraso := trunc(fn_fecha_corte) - trunc(p_rental_date) - v_rental_duration;
   else
      v_dias_atraso := trunc(p_return_date) - trunc(p_rental_date) - v_rental_duration;
   end if;

  -- Evitamos multas negativas cuando la copia vuelve dentro del plazo
   v_dias_atraso := greatest(
      v_dias_atraso,
      0
   );

  -- Aplicamos el tope: la multa nunca supera el costo de reposición
   return least(
      v_dias_atraso * c_multa_diaria,
      v_replacement_cost
   );
exception
   when no_data_found then
      raise_application_error(
         -20201,
         'No existe la copia ' || p_inventory_id
      );
end fn_multa_con_tope;
/

PROMPT Bodies de los packages

/*
¿A qué problema responde?
    Implementamos la responsabilidad del cliente: las funciones sueltas calculan,
    el package decide la medalla y el límite, y orquesta el proceso mensual.
¿Qué dicen los datos?
    Lo esperado cambia según el plazo: en plazo devuelve el 33,1% con 3 días
    y el 76,7% con 7 (H3). Por eso comparamos a cada cliente contra lo esperado
    para las películas que arrendó, y no contra un promedio general.
    En 9 de cada 10 arriendos el cliente tenía 5 copias o menos en casa,
    y en 19 de cada 20, 6 o menos.
Supuestos:
    Índice ajustado = porcentaje en plazo del cliente / porcentaje esperado.
    1,00 es comportarse como el promedio para los plazos que eligió.
    ORO desde 1,20, PLATA desde 0,90 y BRONCE bajo 0,90: quedan 78, 347 y 174 clientes.
    Copias en casa a la vez: BRONCE 5, PLATA 6 y ORO 8. SIN DATOS usa el de BRONCE.
    Umbrales y límites son decisiones de política, no datos: por eso son privados.
    FN_TASA_ESPERADA usa la caché de resultados de Oracle: la tasa de cada plazo
    se calcula una vez y se recalcula sola si cambian RENTAL, INVENTORY o FILM.
    Ningún procedimiento hace COMMIT ni ROLLBACK: usamos SAVEPOINT y RAISE (D7).
Hallazgo e indicador:
    H3, H5 · IE2.2.1, IE2.2.2
*/
CREATE OR REPLACE PACKAGE BODY PKG_RESPONSABILIDAD_CLIENTE IS
    C_UMBRAL_ORO    CONSTANT NUMBER := 1.20;
    C_UMBRAL_PLATA  CONSTANT NUMBER := 0.90;
    C_LIMITE_ORO    CONSTANT NUMBER := 8;
    C_LIMITE_PLATA  CONSTANT NUMBER := 6;
    C_LIMITE_BRONCE CONSTANT NUMBER := 5;

    TYPE T_NOMBRES IS VARRAY(4) OF VARCHAR2(10);
    TYPE T_CONTEO  IS TABLE OF NUMBER INDEX BY VARCHAR2(10);

    PROCEDURE PR_IMPRIMIR(P_TEXTO IN VARCHAR2)
    IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(P_TEXTO);
    END PR_IMPRIMIR;

    FUNCTION FN_TASA_ESPERADA(
        P_RENTAL_DURATION IN FILM.RENTAL_DURATION%TYPE,
        P_FECHA_CORTE     IN RENTAL.RENTAL_DATE%TYPE
    )
        RETURN NUMBER
        RESULT_CACHE
    IS
        V_TASA NUMBER;
    BEGIN
        SELECT AVG(CASE WHEN R.RETURN_DATE IS NOT NULL
                         AND TRUNC(R.RETURN_DATE) - TRUNC(R.RENTAL_DATE) <= F.RENTAL_DURATION
                        THEN 1 ELSE 0 END)
        INTO V_TASA
        FROM RENTAL R
        JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
        JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
        WHERE F.RENTAL_DURATION = P_RENTAL_DURATION
          AND (R.RETURN_DATE IS NOT NULL
               OR TRUNC(P_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) > F.RENTAL_DURATION);

        RETURN V_TASA;
    END FN_TASA_ESPERADA;

    FUNCTION FN_INDICE_AJUSTADO(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
        RETURN NUMBER
    IS
        V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
        V_REAL        NUMBER := FN_PORCENTAJE_EN_PLAZO(P_CUSTOMER_ID);
        V_ESPERADO    NUMBER := 0;
        V_ARRIENDOS   NUMBER := 0;
    BEGIN
        IF V_REAL IS NULL THEN
            RETURN NULL;
        END IF;

        FOR R_PLAZO IN (
            SELECT F.RENTAL_DURATION,
                   COUNT(*) AS ARRIENDOS
            FROM RENTAL R
            JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
            JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
            WHERE R.CUSTOMER_ID = P_CUSTOMER_ID
              AND (R.RETURN_DATE IS NOT NULL
                   OR TRUNC(V_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) > F.RENTAL_DURATION)
            GROUP BY F.RENTAL_DURATION
        ) LOOP
            V_ESPERADO  := V_ESPERADO
                           + R_PLAZO.ARRIENDOS * FN_TASA_ESPERADA(R_PLAZO.RENTAL_DURATION, V_FECHA_CORTE);
            V_ARRIENDOS := V_ARRIENDOS + R_PLAZO.ARRIENDOS;
        END LOOP;

        IF V_ESPERADO = 0 THEN
            RETURN NULL;
        END IF;

        RETURN V_REAL / (100 * V_ESPERADO / V_ARRIENDOS);
    END FN_INDICE_AJUSTADO;

    FUNCTION FN_MEDALLA(P_CUSTOMER_ID IN CUSTOMER.CUSTOMER_ID%TYPE)
        RETURN CLIENTE_MEDALLA.MEDALLA%TYPE
    IS
        V_INDICE NUMBER := FN_INDICE_AJUSTADO(P_CUSTOMER_ID);
    BEGIN
        IF V_INDICE IS NULL THEN
            RETURN 'SIN DATOS';
        ELSIF V_INDICE >= C_UMBRAL_ORO THEN
            RETURN 'ORO';
        ELSIF V_INDICE >= C_UMBRAL_PLATA THEN
            RETURN 'PLATA';
        END IF;

        RETURN 'BRONCE';
    END FN_MEDALLA;

    FUNCTION FN_LIMITE_ARRIENDOS(P_MEDALLA IN CLIENTE_MEDALLA.MEDALLA%TYPE)
        RETURN NUMBER
    IS
    BEGIN
        RETURN CASE P_MEDALLA
                   WHEN 'ORO'   THEN C_LIMITE_ORO
                   WHEN 'PLATA' THEN C_LIMITE_PLATA
                   ELSE C_LIMITE_BRONCE
               END;
    END FN_LIMITE_ARRIENDOS;

    PROCEDURE PR_REPORTE_TIENDA(P_STORE_ID IN STORE.STORE_ID%TYPE)
    IS
        CURSOR C_CLIENTES(P_TIENDA STORE.STORE_ID%TYPE) IS
            SELECT CUSTOMER_ID
            FROM CUSTOMER
            WHERE STORE_ID = P_TIENDA
            ORDER BY CUSTOMER_ID;

        V_MEDALLAS T_NOMBRES := T_NOMBRES('ORO', 'PLATA', 'BRONCE', 'SIN DATOS');
        V_MOTIVOS  T_NOMBRES := T_NOMBRES('SI', 'INACTIVO', 'ATRASO', 'LIMITE');
        V_POR_MEDALLA T_CONTEO;
        V_POR_MOTIVO  T_CONTEO;
        V_CIUDAD      CITY.CITY%TYPE;
        V_PAIS        COUNTRY.COUNTRY%TYPE;
        V_MEDALLA     CLIENTE_MEDALLA.MEDALLA%TYPE;
        V_MOTIVO      VARCHAR2(10);
        V_PROMEDIO    NUMBER;
        V_TOTAL       NUMBER := 0;
    BEGIN
        BEGIN
            SELECT CI.CITY, CO.COUNTRY
            INTO V_CIUDAD, V_PAIS
            FROM STORE ST
            JOIN ADDRESS AD ON AD.ADDRESS_ID = ST.ADDRESS_ID
            JOIN CITY CI    ON CI.CITY_ID    = AD.CITY_ID
            JOIN COUNTRY CO ON CO.COUNTRY_ID = CI.COUNTRY_ID
            WHERE ST.STORE_ID = P_STORE_ID;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20103, 'La tienda ' || P_STORE_ID || ' no existe.');
        END;

        FOR I IN 1 .. V_MEDALLAS.COUNT LOOP
            V_POR_MEDALLA(V_MEDALLAS(I)) := 0;
        END LOOP;

        FOR I IN 1 .. V_MOTIVOS.COUNT LOOP
            V_POR_MOTIVO(V_MOTIVOS(I)) := 0;
        END LOOP;

        FOR R_CLIENTE IN C_CLIENTES(P_STORE_ID) LOOP
            SP_MEDALLA_CLIENTE(R_CLIENTE.CUSTOMER_ID, V_MEDALLA);
            V_MOTIVO := FN_PUEDE_ARRENDAR(R_CLIENTE.CUSTOMER_ID);

            V_POR_MEDALLA(V_MEDALLA) := V_POR_MEDALLA(V_MEDALLA) + 1;
            V_POR_MOTIVO(V_MOTIVO)   := V_POR_MOTIVO(V_MOTIVO) + 1;
            V_TOTAL := V_TOTAL + 1;
        END LOOP;

        SELECT ROUND(AVG(FN_PORCENTAJE_EN_PLAZO(CUSTOMER_ID)), 1)
        INTO V_PROMEDIO
        FROM CUSTOMER
        WHERE STORE_ID = P_STORE_ID;

        PR_IMPRIMIR(' ');
        PR_IMPRIMIR('=== TIENDA ' || P_STORE_ID || ' | ' || V_CIUDAD || ', ' || V_PAIS || ' ===');
        PR_IMPRIMIR('Clientes: ' || V_TOTAL || ' | % en plazo promedio: ' || V_PROMEDIO);
        PR_IMPRIMIR('Medallas vigentes:');
        FOR I IN 1 .. V_MEDALLAS.COUNT LOOP
            PR_IMPRIMIR('  ' || RPAD(V_MEDALLAS(I), 12) || LPAD(V_POR_MEDALLA(V_MEDALLAS(I)), 5));
        END LOOP;
        PR_IMPRIMIR('Puede arrendar hoy:');
        FOR I IN 1 .. V_MOTIVOS.COUNT LOOP
            PR_IMPRIMIR('  ' || RPAD(V_MOTIVOS(I), 12) || LPAD(V_POR_MOTIVO(V_MOTIVOS(I)), 5));
        END LOOP;
    END PR_REPORTE_TIENDA;

    PROCEDURE PR_PROCESO_MENSUAL
    IS
    BEGIN
        SAVEPOINT SV_PROCESO_MENSUAL;

        PR_IMPRIMIR('PROCESO MENSUAL DE RESPONSABILIDAD DEL CLIENTE');
        PR_IMPRIMIR('Fecha de corte: ' || TO_CHAR(FN_FECHA_CORTE, 'DD/MM/YYYY HH24:MI:SS'));

        SP_ACTUALIZA_MEDALLAS;

        FOR R_TIENDA IN (SELECT STORE_ID FROM STORE ORDER BY STORE_ID) LOOP
            PR_REPORTE_TIENDA(R_TIENDA.STORE_ID);
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO SAVEPOINT SV_PROCESO_MENSUAL;
            RAISE;
    END PR_PROCESO_MENSUAL;
END PKG_RESPONSABILIDAD_CLIENTE;
/

CREATE OR REPLACE PACKAGE BODY PKG_COBRANZA_INVENTARIO IS

  -- Privados: la política de bandas de la P1. Cambiar un umbral es editar un literal.
  TYPE T_UMBRALES IS VARRAY(5) OF NUMBER;
  TYPE T_TEXTOS   IS VARRAY(5) OF VARCHAR2(60);
  TYPE T_MONTOS   IS VARRAY(5) OF NUMBER;

  C_UMBRALES CONSTANT T_UMBRALES := T_UMBRALES(0, 30, 90, 180, 999999);

  C_BANDAS   CONSTANT T_TEXTOS := T_TEXTOS('VIGENTE', 'RECUPERABLE', 'DUDOSA',
                                           'PERDIDA', 'INCOBRABLE');

  C_ACCIONES CONSTANT T_TEXTOS := T_TEXTOS('Sin acción, plazo no vencido',
                                           'Recordatorio y cobro de multa',
                                           'Contacto directo, último aviso',
                                           'Facturar reposición al cliente',
                                           'Castigar activo y bloquear cliente');

  -- Devolvemos la posición de la banda: con ella se obtiene su nombre, su acción y su contador
    FUNCTION FN_CLASIFICA_BANDA (p_dias_atraso IN NUMBER) RETURN PLS_INTEGER IS
    BEGIN
        FOR i IN 1 .. C_UMBRALES.COUNT LOOP
        IF p_dias_atraso <= C_UMBRALES(i) THEN
            RETURN i;
        END IF;
        END LOOP;
        RETURN C_UMBRALES.COUNT;
    END FN_CLASIFICA_BANDA;

  -- Concentramos la salida en un solo lugar: si mañana va a una tabla, cambia solo aquí
    PROCEDURE PR_IMPRIMIR (p_texto IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_texto);
    END PR_IMPRIMIR;

  -- Rechazamos una tienda inexistente con un mensaje claro en vez de un reporte vacío
    PROCEDURE PR_VALIDA_TIENDA (p_store_id IN STORE.STORE_ID%TYPE) IS
        V_STORE_ID STORE.STORE_ID%TYPE;
    BEGIN
        SELECT STORE_ID
        INTO V_STORE_ID
        FROM STORE
        WHERE STORE_ID = p_store_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20204, 'No existe la tienda ' || p_store_id);
    END PR_VALIDA_TIENDA;

    PROCEDURE PR_REPORTE_FUGA_TIENDA (p_store_id IN STORE.STORE_ID%TYPE) IS
    V_FECHA_CORTE DATE := FN_FECHA_CORTE;

    CURSOR C_FUERA (p_tienda STORE.STORE_ID%TYPE) IS
        SELECT R.INVENTORY_ID,
                R.RENTAL_DATE,
                F.TITLE,
                F.REPLACEMENT_COST,
                TRUNC(V_FECHA_CORTE) - TRUNC(R.RENTAL_DATE) - F.RENTAL_DURATION AS DIAS_ATRASO
            FROM RENTAL R
            JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
            JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
        WHERE R.RETURN_DATE IS NULL
            AND I.STORE_ID = p_tienda
        ORDER BY DIAS_ATRASO DESC;

    V_COPIAS  T_MONTOS := T_MONTOS(0, 0, 0, 0, 0);
    V_CAPITAL T_MONTOS := T_MONTOS(0, 0, 0, 0, 0);
    V_MULTA   T_MONTOS := T_MONTOS(0, 0, 0, 0, 0);
    V_BANDA   PLS_INTEGER;

    BEGIN
        PR_VALIDA_TIENDA(p_store_id);

        PR_IMPRIMIR(' ');
        PR_IMPRIMIR('=== TIENDA ' || p_store_id || ' ===');

        -- Clasificamos cada copia fuera y detallamos las que ya vencieron
        FOR R_COPIA IN C_FUERA(p_store_id) LOOP
        V_BANDA := FN_CLASIFICA_BANDA(R_COPIA.DIAS_ATRASO);

        V_COPIAS(V_BANDA)  := V_COPIAS(V_BANDA) + 1;
        V_CAPITAL(V_BANDA) := V_CAPITAL(V_BANDA) + R_COPIA.REPLACEMENT_COST;
        V_MULTA(V_BANDA)   := V_MULTA(V_BANDA) +
                                FN_MULTA_CON_TOPE(R_COPIA.INVENTORY_ID, R_COPIA.RENTAL_DATE, NULL);

        IF V_BANDA > 1 THEN
            PR_IMPRIMIR('  Copia ' || R_COPIA.INVENTORY_ID || ' | ' || R_COPIA.TITLE ||
                        ' | ' || R_COPIA.DIAS_ATRASO || ' días | ' || C_BANDAS(V_BANDA));
        END IF;
        END LOOP;

        PR_IMPRIMIR(RPAD('BANDA', 12) || LPAD('COPIAS', 7) || LPAD('CAPITAL', 11) ||
                    LPAD('MULTA', 11) || '  ACCIÓN SUGERIDA');

        FOR i IN 1 .. C_BANDAS.COUNT LOOP
        PR_IMPRIMIR(RPAD(C_BANDAS(i), 12) ||
                    LPAD(V_COPIAS(i), 7) ||
                    LPAD(TO_CHAR(V_CAPITAL(i), 'FM999G990D00'), 11) ||
                    LPAD(TO_CHAR(V_MULTA(i), 'FM999G990D00'), 11) ||
                    '  ' || C_ACCIONES(i));
        END LOOP;
    END PR_REPORTE_FUGA_TIENDA;

    PROCEDURE PR_REPORTE_FUGA IS
        CURSOR C_TIENDAS IS
        SELECT STORE_ID
            FROM STORE
        ORDER BY STORE_ID;
    BEGIN
        PR_IMPRIMIR('COPIAS FUERA AL ' || TO_CHAR(FN_FECHA_CORTE, 'DD/MM/YYYY HH24:MI:SS'));

        -- Delegamos el detalle de cada tienda a PR_REPORTE_FUGA_TIENDA
        FOR R_TIENDA IN C_TIENDAS LOOP
            PR_REPORTE_FUGA_TIENDA(R_TIENDA.STORE_ID);
        END LOOP;

        -- Cerramos con el total de ambas tiendas
        PR_IMPRIMIR(' ');
        PR_IMPRIMIR('CAPITAL EN RIESGO TOTAL: ' ||
            TO_CHAR(FN_CAPITAL_EN_RIESGO, 'FM999G990D00') || ' USD');
    END PR_REPORTE_FUGA;

    PROCEDURE PR_REPORTE_RENTABILIDAD (p_store_id IN STORE.STORE_ID%TYPE) IS
        CURSOR C_COPIAS (p_tienda STORE.STORE_ID%TYPE) IS
        SELECT INVENTORY_ID
            FROM INVENTORY
        WHERE STORE_ID = p_tienda;

    V_COPIAS          NUMBER := 0;
    V_SIN_RECUPERAR   NUMBER := 0;
    V_BRECHA          NUMBER := 0;
    V_RESULTADO       NUMBER;
    V_SIN_COPIA_TDA   NUMBER;
    V_SIN_COPIA_TOTAL NUMBER;

    BEGIN
        PR_VALIDA_TIENDA(p_store_id);

        -- Medimos cada copia de la tienda contra su costo de reposición
        FOR R_COPIA IN C_COPIAS(p_store_id) LOOP
        V_COPIAS    := V_COPIAS + 1;
        V_RESULTADO := FN_RENTABILIDAD_COPIA(R_COPIA.INVENTORY_ID);

        IF V_RESULTADO < 0 THEN
            V_SIN_RECUPERAR := V_SIN_RECUPERAR + 1;
            V_BRECHA        := V_BRECHA - V_RESULTADO;
        END IF;
        END LOOP;

        -- Películas del catálogo sin copia en esta tienda y sin copia en ninguna (H8)
        SELECT COUNT(*)
        INTO V_SIN_COPIA_TDA
        FROM FILM F
        WHERE NOT EXISTS (SELECT 1
                            FROM INVENTORY I
                            WHERE I.FILM_ID  = F.FILM_ID
                            AND I.STORE_ID = p_store_id);

        SELECT COUNT(*)
        INTO V_SIN_COPIA_TOTAL
        FROM FILM F
        WHERE NOT EXISTS (SELECT 1 FROM INVENTORY I WHERE I.FILM_ID = F.FILM_ID);

        PR_IMPRIMIR(' ');
        PR_IMPRIMIR('=== RENTABILIDAD TIENDA ' || p_store_id || ' ===');
        PR_IMPRIMIR('Copias en inventario: ' || V_COPIAS);
        PR_IMPRIMIR('Copias que aún no recuperan su costo: ' || V_SIN_RECUPERAR);
        PR_IMPRIMIR('Brecha por recuperar: ' || TO_CHAR(V_BRECHA, 'FM999G990D00') || ' USD');
        PR_IMPRIMIR('Películas sin copia en esta tienda: ' || V_SIN_COPIA_TDA);
        PR_IMPRIMIR('Películas sin copia en ninguna tienda: ' || V_SIN_COPIA_TOTAL);
    END PR_REPORTE_RENTABILIDAD;

    PROCEDURE PR_SIMULA_PLAZO (p_dias_extra IN NUMBER) IS
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

    PR_IMPRIMIR('SIMULACIÓN CON ' || p_dias_extra || ' DÍAS EXTRA DE PLAZO');
    PR_IMPRIMIR('Arriendos devueltos analizados: ' || V_DEVUELTOS);
    PR_IMPRIMIR('Devoluciones tarde: ' || V_ATRASOS_ACTUAL ||
      ' (' || TO_CHAR(ROUND(V_ATRASOS_ACTUAL / V_DEVUELTOS * 100, 1), 'FM990D0') || '%) -> ' ||
      V_ATRASOS_SIMULADO ||
      ' (' || TO_CHAR(ROUND(V_ATRASOS_SIMULADO / V_DEVUELTOS * 100, 1), 'FM990D0') || '%)');
    PR_IMPRIMIR('Atrasos evitados: ' || (V_ATRASOS_ACTUAL - V_ATRASOS_SIMULADO));
    PR_IMPRIMIR('Multa cobrada: ' || TO_CHAR(V_MULTA_ACTUAL, 'FM999G990D00') ||
      ' USD -> ' || TO_CHAR(V_MULTA_SIMULADA, 'FM999G990D00') || ' USD');
    PR_IMPRIMIR('Multa que se deja de cobrar: ' ||
      TO_CHAR(V_MULTA_ACTUAL - V_MULTA_SIMULADA, 'FM999G990D00') || ' USD (' ||
      TO_CHAR(ROUND((V_MULTA_ACTUAL - V_MULTA_SIMULADA) / V_INGRESO_TOTAL * 100, 1), 'FM990D0') ||
      '% del ingreso)');
  EXCEPTION
    WHEN E_DIAS_INVALIDOS THEN
      RAISE_APPLICATION_ERROR(-20203, 'Los días extra deben ser 0 o más, se recibió: ' ||
                                      NVL(TO_CHAR(p_dias_extra), 'NULL'));
  END PR_SIMULA_PLAZO;

    PROCEDURE PR_PROCESO_MENSUAL IS
        CURSOR C_TIENDAS IS
        SELECT STORE_ID
            FROM STORE
        ORDER BY STORE_ID;
    BEGIN
        PR_REPORTE_FUGA;

        FOR R_TIENDA IN C_TIENDAS LOOP
            PR_REPORTE_RENTABILIDAD(R_TIENDA.STORE_ID);
        END LOOP;
    END PR_PROCESO_MENSUAL;

END PKG_COBRANZA_INVENTARIO;
/

PROMPT Triggers

/*
A qué problema responde?
    Se encontraron pagos sin mencion a que arriendo es dirigido, ingresandose con RENTAL_ID nulo. Se crea este
    trigger para cerrarle la puerta a estos registros de pagos incompletos.
    
Qué dicen los datos?
    Los datos dicen que se encontraron 5 registros con un rental_id nulo. Se les habia permitido su ingreso debido a que la tabla
    acepta columnas vacias.
    
Supuestos:
    Se revisa cada pago antes[BEFORE] de que se registren en PAYMENT para lograr rechazarlos en caso de ser nulos, en 
    caso de ser nulo se lanzaria un error.
    C1 solo revisa el pago que entra y no consulta RENTAL; así no falla cuando C2
    inserta una multa mientras se modifica RENTAL (error de tabla mutante).
    Sakila ya tiene otro trigger en PAYMENT; no importa cuál corra primero
    porque cada uno revisa columnas distintas.
    
    No se corregio los 5 pagos nulos solo validamos los pagos nuevos.
    Es trigger y no una validación manual porque se dispara solo y ningún programa lo salta.
    
Hallazgo e indicador:
    H1 · IE2.3.1, IE2.3.2
*/


CREATE OR REPLACE TRIGGER TRG_VALIDA_PAGO_RENTAL
BEFORE INSERT ON PAYMENT
FOR EACH ROW
WHEN (NEW.RENTAL_ID IS NULL) 
--Verficamos que antes de ingresar el registro de pago en PAYMENT, se verifique a donde esta dirigido el arriendo(RENTAL_ID).
BEGIN
    RAISE_APPLICATION_ERROR(-20301, 'El pago del cliente ' || :NEW.CUSTOMER_ID
                                    || ' no indica a qué arriendo corresponde');
END TRG_VALIDA_PAGO_RENTAL;
/

/*
A qué problema responde?
Si se borra un arriendo, sus pagos quedan sin saber a qué arriendo pertenecen.
Se bloquea el borrado de arriendos para que no se creen más pagos huérfanos.


Qué dicen los datos?
    Se encuentra una linea de codigo en el script de Sakila Schema donde
    se meciona que si se borra un arriendo, a los pagos que apuntaban a él
    se les pone un rental_id vacio


Supuestos:
    Se revisa una sola vez por orden, cualquier delete en RENTAL se rechaza.
    Se activa aunque el delete no encuentre ningún arriendo.
    Solo bloquea borrar; crear arriendos o registrar devoluciones sigue funcionando.
    
    No se cambio la llave de Sakila, solo la protegemos desde afuera.
    Si el DBA necesita borrar algo, apaga el trigger con
    ALTER TRIGGER TRG_BLOQUEA_BORRADO_RENTAL DISABLE y después lo vuelve a encender.


Hallazgo e indicador:
    H2 · IE2.3.1, IE2.3.2

*/

CREATE OR REPLACE TRIGGER TRG_BLOQUEA_BORRADO_RENTAL
BEFORE DELETE ON RENTAL 
--Salta antes de que se elimine un arriendo
BEGIN
    RAISE_APPLICATION_ERROR(-20304, 'No se pueden borrar arriendos: sus pagos quedarían sin arriendo (H2).');
END TRG_BLOQUEA_BORRADO_RENTAL;
/

/*
A qué problema responde?
    Actualmente en Sakila no queda un registro de quien modifica
    los datos, por ejemplo en fecha de devolucion o si es que borra un pago
    No se registra que proceso realizo

Qué dicen los datos?
    Se muestra que las modificaciones realizadas se guardan en LAST_UPDATE pero
    esta solo menciona la hora del ultimo cambio y se sobreescribe en cada cambio,
    no dice quien fue, y si la fila se borra desaparece con ella. 15 de 16 tablas
    tienen solo LAST_UPDATE y ninguna columna guarda el usuario ni la operacion
    
Supuestos:
    C5 actua junto a AUDITORIA_SAKILA escribiendose en ella.
    Se activa  AFTER para anotar solo lo que si ocurrio,
    al ser de sentencia solo anota una linea por orden, aunque cambie muchas filas.
    Un DELETE en RENTAL nunca llega a anotarse por que C4 lo rechaza antes y si la operacion
    termina en un rollback, su linea tambien se borra.

Hallazgo e indicador:
    H10 · IE2.3.1, IE2.3.2

*/

CREATE OR REPLACE TRIGGER TRG_AUDITA_RENTAL
AFTER INSERT OR UPDATE OR DELETE ON RENTAL
--Se ejecuta despues de la operacion para anotar lo que esta pasando en el momento
DECLARE
    V_OPERACION AUDITORIA_SAKILA.OPERACION%TYPE;
    --Guarda la operacion utilizada
BEGIN
    IF INSERTING THEN
        V_OPERACION := 'INSERT';
    ELSIF UPDATING THEN
        V_OPERACION := 'UPDATE';
    ELSE
        V_OPERACION := 'DELETE';
    END IF;

    INSERT INTO AUDITORIA_SAKILA (ID_AUDITORIA, TABLA, OPERACION)
    VALUES (SEQ_AUDITORIA_SAKILA.NEXTVAL, 'RENTAL', V_OPERACION);
    --Anota una linea en auditoria con la tabla,operacion, quien lo hizo y cuando
END TRG_AUDITA_RENTAL;
/

SELECT OBJECT_NAME, STATUS FROM USER_OBJECTS WHERE OBJECT_NAME = 'TRG_AUDITA_RENTAL';
SELECT * FROM USER_ERRORS WHERE NAME = 'TRG_AUDITA_RENTAL';

/*
--Este código es la segunda mitad de C5. Su propósito es dejar registro de todo lo que se hace con los pagos
----un trigger solo puede vigilar una tabla. TRG_AUDITA_RENTAL mira los arriendos y TRG_AUDITA_PAYMENT mira los pagos. 
Juntos formarian C5.

A qué problema responde?
    Actualmente en Sakila no queda un registro de quien modifica
    los pagos, por ejemplo si alguien cambia el monto de un pago o lo borra.
    Tampoco se registra que operacion se realizo (INSERT, UPDATE o DELETE).

Qué dicen los datos?
    Las modificaciones realizadas se guardan en LAST_UPDATE pero
    esta solo menciona la hora del ultimo cambio y se sobreescribe en cada cambio,
    no dice quien fue, y si la fila se borra desaparece con ella. 15 de 16 tablas
    tienen solo LAST_UPDATE y ninguna columna guarda el usuario ni la operacion.
    En PAYMENT esto toca dinero: 16.049 pagos por 67.417 USD sin registro de quien los cambia.

Supuestos:
    C5 actua junto a AUDITORIA_SAKILA escribiendose en ella.
    Se activa despues de la operacion (AFTER), anotando solo lo que si ocurrio.
    Al ser de sentencia solo anota una linea por orden, aunque cambie muchas filas.
    Un DELETE en PAYMENT si queda anotado, porque en PAYMENT no hay un trigger que lo bloquee.
    Tambien anota los pagos de multa que insertara C2, asi queda registro de los cobros automaticos.
    Si la operacion termina en un rollback, su linea tambien se borra.

Hallazgo e indicador:
    H10 · IE2.3.1, IE2.3.2
*/

CREATE OR REPLACE TRIGGER TRG_AUDITA_PAYMENT
AFTER INSERT OR UPDATE OR DELETE ON PAYMENT
--Se ejecuta despues de la operacion para anotar lo que ocurrio en PAYMENT
DECLARE
    V_OPERACION AUDITORIA_SAKILA.OPERACION%TYPE;
    --Guarda la operacion utilizada
BEGIN
    IF INSERTING THEN
        V_OPERACION := 'INSERT';
    ELSIF UPDATING THEN
        V_OPERACION := 'UPDATE';
    ELSE
        V_OPERACION := 'DELETE';
    END IF;

    INSERT INTO AUDITORIA_SAKILA (ID_AUDITORIA, TABLA, OPERACION)
    VALUES (SEQ_AUDITORIA_SAKILA.NEXTVAL, 'PAYMENT', V_OPERACION);
    --Anota una linea en auditoria con la tabla, operacion, quien lo hizo y cuando
END TRG_AUDITA_PAYMENT;
/

/*
Conexion:
    cuando alguien intenta registrar un arriendo nuevo, el trigger le pregunta a la función de Gabriel si ese cliente puede arrendar.
    Si la respuesta no es 'SI', rechaza el arriendo y muestra el motivo
    
A qué problema responde?
    Sakila deja arrendar a cualquier cliente, aunque este inactivo o tenga copias
    vencidas en casa. Rechazamos el arriendo nuevo cuando el cliente no puede arrendar
    y mostramos el motivo.

Qué dicen los datos?
    490 clientes hicieron 1.709 arriendos teniendo otra copia vencida en casa
    y 15 clientes inactivos registran 404 arriendos 

Supuestos:
    Es de fila y con BEFORE INSERT revisamos el cliente de cada arriendo antes de guardarlo.
    La decision la toma FN_PUEDE_ARRENDAR de Gabriel, el trigger solo la hace cumplir.
    Funciona con INSERT...VALUES de una fila. con INSERT...SELECT da ORA-04091
    osea una tabla mutante porque la funcion lee RENTAL. 
    Queda como limitacion. la mejora seria un trigger compuesto.
    No corrige los arriendos antiguos y solo revisa los nuevos.

Hallazgo e indicador:
    H5, H6 · IE2.3.1, IE2.3.2
*/

CREATE OR REPLACE TRIGGER TRG_VALIDA_ARRIENDO
BEFORE INSERT ON RENTAL
FOR EACH ROW
--Se ejecuta antes de guardar cada arriendo nuevo
DECLARE
    V_MOTIVO VARCHAR2(10);
    --Guarda la respuesta de FN_PUEDE_ARRENDAR: 'SI' o el motivo del bloqueo
BEGIN
    V_MOTIVO := FN_PUEDE_ARRENDAR(:NEW.CUSTOMER_ID);

    IF V_MOTIVO <> 'SI' THEN
        RAISE_APPLICATION_ERROR(-20303, 'El cliente ' || :NEW.CUSTOMER_ID
                                        || ' no puede arrendar: ' || V_MOTIVO || '.');
    END IF;
END TRG_VALIDA_ARRIENDO;
/

/*


A qué problema responde?
    Sakila cobra 1 USD por cada dia de atraso sin limite, asi que la multa puede
    superar lo que vale la copia. Cuando se registra una devolucion con atraso,
    cobramos solo la multa con tope y la anotamos como un pago nuevo.

Qué dicen los datos?
    Las multas son 20.192 de los 67.417 USD de ingreso, cerca del 30%.
    Una copia de ACADEMY DINOSAUR acumula 171 dias de atraso sobre un costo de
    20,99 USD sin tope se cobrarian 171 USD por una copia que vale 20,99.

Supuestos:
    Es de fila y con AFTER UPDATE OF RETURN_DATE cobramos cuando la devolucion ya quedo registrada.
    Solo actua si el arriendo no estaba devuelto y ahora si lo esta (OLD vacio y NEW con fecha)
    asi no cobramos dos veces si alguien corrige una fecha.
    
    El pago nuevo usa SEQ_PAYMENT_ID.NEXTVAL y su fecha es la de la devolucion.
    El INSERT en PAYMENT dispara C1, que lo deja pasar porque trae RENTAL_ID, y C5 que lo anota.
    Si la copia vuelve dentro del plazo, la multa es 0 y no se crea ningun pago.
    
 Conexion:
    El monto lo calcula FN_MULTA_CON_TOPE de Simon, que solo lee INVENTORY y FILM cuando
    recibe una fecha de devolucion. Con el WHEN nunca le pasamos una fecha vacia, porque
    en ese caso leeria RENTAL y daria ORA-04091 (tabla mutante).
    
    

Hallazgo e indicador:
    H4, H9 · IE2.3.1, 
    IE2.3.2
*/

CREATE OR REPLACE TRIGGER TRG_TOPE_MULTA_DEVOLUCION
AFTER UPDATE OF RETURN_DATE ON RENTAL
FOR EACH ROW
WHEN (OLD.RETURN_DATE IS NULL AND NEW.RETURN_DATE IS NOT NULL)
--Se ejecuta cuando un arriendo pasa de no devuelto a devuelto
DECLARE
    V_MULTA PAYMENT.AMOUNT%TYPE;
    --Guarda la multa con tope que calcula la funcion de Simon
BEGIN
    V_MULTA := FN_MULTA_CON_TOPE(:NEW.INVENTORY_ID, :NEW.RENTAL_DATE, :NEW.RETURN_DATE);

    IF V_MULTA > 0 THEN
        INSERT INTO PAYMENT (PAYMENT_ID, CUSTOMER_ID, STAFF_ID, RENTAL_ID, AMOUNT, PAYMENT_DATE)
        VALUES (SEQ_PAYMENT_ID.NEXTVAL, :NEW.CUSTOMER_ID, :NEW.STAFF_ID, :NEW.RENTAL_ID,
                V_MULTA, :NEW.RETURN_DATE);
        --Cobramos la multa como un pago nuevo del mismo cliente y del mismo arriendo
    END IF;
END TRG_TOPE_MULTA_DEVOLUCION;
/

PROMPT Estado de los objetos: todos VALID y USER_ERRORS vacío

SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME IN ('TRG_TOPE_MULTA_DEVOLUCION', 'TRG_VALIDA_ARRIENDO',
                      'TRG_AUDITA_PAYMENT', 'TRG_AUDITA_RENTAL',
                      'TRG_BLOQUEA_BORRADO_RENTAL', 'TRG_VALIDA_PAGO_RENTAL',
                      'PKG_COBRANZA_INVENTARIO', 'PKG_RESPONSABILIDAD_CLIENTE',
                      'FN_CAPITAL_EN_RIESGO', 'FN_RENTABILIDAD_COPIA',
                      'FN_MULTA_CON_TOPE', 'SP_ACTUALIZA_MEDALLAS',
                      'FN_PUEDE_ARRENDAR', 'SP_MEDALLA_CLIENTE',
                      'FN_PORCENTAJE_EN_PLAZO', 'FN_FECHA_CORTE',
                      'AUDITORIA_SAKILA', 'CLIENTE_MEDALLA',
                      'SEQ_AUDITORIA_SAKILA', 'SEQ_PAYMENT_ID')
ORDER BY OBJECT_TYPE, OBJECT_NAME;

SELECT NAME, TYPE, LINE, POSITION, TEXT
FROM USER_ERRORS
ORDER BY NAME, TYPE, SEQUENCE;

PROMPT Demostración: FN_FECHA_CORTE

SET SERVEROUTPUT ON

SELECT TO_CHAR(FN_FECHA_CORTE, 'DD/MM/YYYY HH24:MI:SS') AS FECHA_CORTE,
       COUNT(*)                                          AS SIN_DEVOLVER,
       COUNT(CASE WHEN R.RENTAL_DATE = FN_FECHA_CORTE
                  THEN 1 END)                            AS ARRENDADOS_EN_EL_CORTE
FROM RENTAL R
WHERE R.RETURN_DATE IS NULL;

DECLARE
    V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
    V_VIGENTES    NUMBER := 0;
    V_VENCIDOS    NUMBER := 0;
BEGIN
    FOR R_ARRIENDO IN (
        SELECT R.RENTAL_DATE,
               F.RENTAL_DURATION
        FROM RENTAL R
        JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
        JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
        WHERE R.RETURN_DATE IS NULL
    ) LOOP
        IF TRUNC(V_FECHA_CORTE) - TRUNC(R_ARRIENDO.RENTAL_DATE) > R_ARRIENDO.RENTAL_DURATION THEN
            V_VENCIDOS := V_VENCIDOS + 1;
        ELSE
            V_VIGENTES := V_VIGENTES + 1;
        END IF;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Fecha de corte : ' || TO_CHAR(V_FECHA_CORTE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('Sin devolver vigentes al corte: ' || V_VIGENTES);
    DBMS_OUTPUT.PUT_LINE('Sin devolver vencidos al corte: ' || V_VENCIDOS);
END;
/

ROLLBACK;

PROMPT Demostración: FN_PORCENTAJE_EN_PLAZO

SET SERVEROUTPUT ON

SELECT MIN(PORCENTAJE)    AS MINIMO,
       MEDIAN(PORCENTAJE) AS MEDIANA,
       MAX(PORCENTAJE)    AS MAXIMO,
       COUNT(PORCENTAJE)  AS CLIENTES
FROM (SELECT FN_PORCENTAJE_EN_PLAZO(CUSTOMER_ID) AS PORCENTAJE
      FROM CUSTOMER);

SELECT C.CUSTOMER_ID,
       C.FIRST_NAME || ' ' || C.LAST_NAME     AS CLIENTE,
       FN_PORCENTAJE_EN_PLAZO(C.CUSTOMER_ID) AS PORCENTAJE_EN_PLAZO
FROM CUSTOMER C
ORDER BY PORCENTAJE_EN_PLAZO DESC, C.CUSTOMER_ID
FETCH FIRST 5 ROWS ONLY;

DECLARE
    V_PORCENTAJE NUMBER;
    V_SUMA       NUMBER;
    V_CLIENTES   NUMBER;
BEGIN
    FOR R_TIENDA IN (SELECT STORE_ID FROM STORE ORDER BY STORE_ID) LOOP
        V_SUMA     := 0;
        V_CLIENTES := 0;

        FOR R_CLIENTE IN (SELECT CUSTOMER_ID FROM CUSTOMER WHERE STORE_ID = R_TIENDA.STORE_ID) LOOP
            V_PORCENTAJE := FN_PORCENTAJE_EN_PLAZO(R_CLIENTE.CUSTOMER_ID);
            IF V_PORCENTAJE IS NOT NULL THEN
                V_SUMA     := V_SUMA + V_PORCENTAJE;
                V_CLIENTES := V_CLIENTES + 1;
            END IF;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('Tienda ' || R_TIENDA.STORE_ID || ': ' || V_CLIENTES
                             || ' clientes, % en plazo promedio ' || ROUND(V_SUMA / V_CLIENTES, 1));
    END LOOP;
END;
/

ROLLBACK;

PROMPT Demostración: SP_MEDALLA_CLIENTE

SET SERVEROUTPUT ON

DECLARE
    V_MEDALLA CLIENTE_MEDALLA.MEDALLA%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Sin proceso mensual, la medalla se calcula en el momento:');
    FOR R_CLIENTE IN (SELECT CUSTOMER_ID FROM CUSTOMER WHERE CUSTOMER_ID <= 5 ORDER BY CUSTOMER_ID) LOOP
        SP_MEDALLA_CLIENTE(R_CLIENTE.CUSTOMER_ID, V_MEDALLA);
        DBMS_OUTPUT.PUT_LINE('  Cliente ' || R_CLIENTE.CUSTOMER_ID || ': ' || V_MEDALLA);
    END LOOP;

    INSERT INTO CLIENTE_MEDALLA (CUSTOMER_ID, MEDALLA, PORCENTAJE_EN_PLAZO)
    VALUES (1, 'ORO', FN_PORCENTAJE_EN_PLAZO(1));

    SP_MEDALLA_CLIENTE(1, V_MEDALLA);
    DBMS_OUTPUT.PUT_LINE('Con medalla guardada para el cliente 1, manda la guardada: ' || V_MEDALLA);

    BEGIN
        SP_MEDALLA_CLIENTE(99999, V_MEDALLA);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Cliente inexistente: ' || SQLERRM);
    END;
END;
/

SELECT CUSTOMER_ID, MEDALLA, PORCENTAJE_EN_PLAZO
FROM CLIENTE_MEDALLA;

ROLLBACK;

SELECT COUNT(*) AS FILAS_TRAS_ROLLBACK
FROM CLIENTE_MEDALLA;

PROMPT Demostración: FN_PUEDE_ARRENDAR

SET SERVEROUTPUT ON

SELECT RESPUESTA,
       COUNT(*) AS CLIENTES
FROM (SELECT FN_PUEDE_ARRENDAR(CUSTOMER_ID) AS RESPUESTA
      FROM CUSTOMER)
GROUP BY RESPUESTA
ORDER BY RESPUESTA;

SELECT C.CUSTOMER_ID,
       C.ACTIVE,
       FN_PUEDE_ARRENDAR(C.CUSTOMER_ID) AS RESPUESTA
FROM CUSTOMER C
WHERE C.CUSTOMER_ID IN (554, (SELECT MIN(CUSTOMER_ID) FROM CUSTOMER WHERE ACTIVE IN ('0', 'N')))
ORDER BY C.CUSTOMER_ID;

DECLARE
    V_FECHA_CORTE RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
    V_CLIENTE     CUSTOMER.CUSTOMER_ID%TYPE;
    V_MEDALLA     CLIENTE_MEDALLA.MEDALLA%TYPE;
    V_RENTAL_ID   RENTAL.RENTAL_ID%TYPE;
    V_RESPUESTA   VARCHAR2(10);
    V_EN_CASA     NUMBER := 0;
BEGIN
    SELECT MIN(C.CUSTOMER_ID)
    INTO V_CLIENTE
    FROM CUSTOMER C
    WHERE C.ACTIVE IN ('1', 'Y')
      AND NOT EXISTS (SELECT 1
                      FROM RENTAL R
                      WHERE R.CUSTOMER_ID = C.CUSTOMER_ID
                        AND R.RETURN_DATE IS NULL)
      AND PKG_RESPONSABILIDAD_CLIENTE.FN_MEDALLA(C.CUSTOMER_ID) = 'BRONCE';

    SP_MEDALLA_CLIENTE(V_CLIENTE, V_MEDALLA);
    SELECT MAX(RENTAL_ID) INTO V_RENTAL_ID FROM RENTAL;

    DBMS_OUTPUT.PUT_LINE('Cliente ' || V_CLIENTE || ', medalla ' || V_MEDALLA
                         || ', limite ' || PKG_RESPONSABILIDAD_CLIENTE.FN_LIMITE_ARRIENDOS(V_MEDALLA));

    FOR R_COPIA IN (
        SELECT I.INVENTORY_ID
        FROM INVENTORY I
        WHERE NOT EXISTS (SELECT 1
                          FROM RENTAL R
                          WHERE R.INVENTORY_ID = I.INVENTORY_ID
                            AND R.RETURN_DATE IS NULL)
        ORDER BY I.INVENTORY_ID
        FETCH FIRST 10 ROWS ONLY
    ) LOOP
        V_RESPUESTA := FN_PUEDE_ARRENDAR(V_CLIENTE);
        DBMS_OUTPUT.PUT_LINE('  Copias en casa: ' || V_EN_CASA || ' -> ' || V_RESPUESTA);
        EXIT WHEN V_RESPUESTA <> 'SI';

        V_RENTAL_ID := V_RENTAL_ID + 1;
        INSERT INTO RENTAL (RENTAL_ID, RENTAL_DATE, INVENTORY_ID, CUSTOMER_ID, RETURN_DATE, STAFF_ID)
        VALUES (V_RENTAL_ID, V_FECHA_CORTE, R_COPIA.INVENTORY_ID, V_CLIENTE, NULL, 1);
        V_EN_CASA := V_EN_CASA + 1;
    END LOOP;

    BEGIN
        V_RESPUESTA := FN_PUEDE_ARRENDAR(99999);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Cliente inexistente: ' || SQLERRM);
    END;
END;
/

ROLLBACK;

PROMPT Demostración: SP_ACTUALIZA_MEDALLAS

SET SERVEROUTPUT ON

BEGIN
    SP_ACTUALIZA_MEDALLAS;
    SP_ACTUALIZA_MEDALLAS;
END;
/

SELECT MEDALLA,
       COUNT(*)                          AS CLIENTES,
       ROUND(AVG(PORCENTAJE_EN_PLAZO), 1) AS PORCENTAJE_PROMEDIO
FROM CLIENTE_MEDALLA
GROUP BY MEDALLA
ORDER BY PORCENTAJE_PROMEDIO DESC;

ROLLBACK;

SELECT COUNT(*) AS FILAS_TRAS_ROLLBACK
FROM CLIENTE_MEDALLA;

PROMPT Demostración: PKG_RESPONSABILIDAD_CLIENTE

SET SERVEROUTPUT ON

SELECT C.CUSTOMER_ID,
       FN_PORCENTAJE_EN_PLAZO(C.CUSTOMER_ID)                       AS PORCENTAJE_EN_PLAZO,
       PKG_RESPONSABILIDAD_CLIENTE.FN_MEDALLA(C.CUSTOMER_ID)       AS MEDALLA,
       PKG_RESPONSABILIDAD_CLIENTE.FN_LIMITE_ARRIENDOS(
           PKG_RESPONSABILIDAD_CLIENTE.FN_MEDALLA(C.CUSTOMER_ID))  AS LIMITE_COPIAS
FROM CUSTOMER C
WHERE C.CUSTOMER_ID <= 5
ORDER BY C.CUSTOMER_ID;

SELECT MEDALLA,
       COUNT(*) AS CLIENTES
FROM (SELECT PKG_RESPONSABILIDAD_CLIENTE.FN_MEDALLA(CUSTOMER_ID) AS MEDALLA
      FROM CUSTOMER)
GROUP BY MEDALLA
ORDER BY CLIENTES;

BEGIN
    PKG_RESPONSABILIDAD_CLIENTE.PR_PROCESO_MENSUAL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DECLARE V_INDICE NUMBER; '
                   || 'BEGIN V_INDICE := PKG_RESPONSABILIDAD_CLIENTE.FN_INDICE_AJUSTADO(1); END;';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Miembro privado desde fuera del package: ' || SQLERRM);
END;
/

ROLLBACK;

SELECT COUNT(*) AS FILAS_TRAS_ROLLBACK
FROM CLIENTE_MEDALLA;

PROMPT Demostración: funciones y PKG_COBRANZA_INVENTARIO

/*
Este script contiene las pruebas de cada función, procedimiento y package creado llamandolos.

FN_MULTA_CON_TOPE(INVENTORY_ID, RENTAL_DATE, RETURN_DATE)



*/

/* =========================================================
   P1 · FN_MULTA_CON_TOPE (función con parámetros) · H4, H9
   ========================================================= */

/*
Test realizado para "FN_MULTA_CON_TOPE", 
aquí buscamos directamente uno de los rental
Se utilizó un rental que se relacione con una pelicula que 
tiene una multa superior al coste de reemplazo
Esperado: 20,99 USD
*/ 
SELECT R.RENTAL_ID,
       F.TITLE,
       FN_MULTA_CON_TOPE(R.INVENTORY_ID, R.RENTAL_DATE, R.RETURN_DATE) AS MULTA_CON_TOPE
  FROM RENTAL R
  JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
  JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
 WHERE F.TITLE = 'ACADEMY DINOSAUR'
   AND R.RETURN_DATE IS NULL;


-- P1.2 Dentro de otro programa PL/SQL: multa teórica de las copias que siguen fuera.
-- Esperado: 183 copias, 1 con multa y 20,99 USD en total.
DECLARE
  CURSOR C_FUERA IS
    SELECT INVENTORY_ID, RENTAL_DATE
      FROM RENTAL
     WHERE RETURN_DATE IS NULL;
 
  V_MULTA      NUMBER;
  V_COPIAS     NUMBER := 0;
  V_CON_MULTA  NUMBER := 0;
  V_TOTAL      NUMBER := 0;
BEGIN
  FOR R_FUERA IN C_FUERA LOOP
    V_MULTA  := FN_MULTA_CON_TOPE(R_FUERA.INVENTORY_ID, R_FUERA.RENTAL_DATE, NULL);
    V_COPIAS := V_COPIAS + 1;
    V_TOTAL  := V_TOTAL + V_MULTA;
    IF V_MULTA > 0 THEN
      V_CON_MULTA := V_CON_MULTA + 1;
    END IF;
  END LOOP;
 
  DBMS_OUTPUT.PUT_LINE('P1.3 Copias fuera: ' || V_COPIAS ||
                       ' | con multa: ' || V_CON_MULTA ||
                       ' | multa teórica: ' || TO_CHAR(V_TOTAL, 'FM999G990D00') || ' USD');
END;
/


-- P1.3
-- Error controlado: No existe la copia 999999
BEGIN
  DBMS_OUTPUT.PUT_LINE(FN_MULTA_CON_TOPE(999999, SYSDATE, SYSDATE));
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('P1.4 ' || SQLERRM);
END;
/

/* =========================================================
   P2 · FN_RENTABILIDAD_COPIA (función con parámetro) · H7
   ========================================================= */

-- P2.1 En un SELECT sobre las 4.581 copias. Esperado: 3.331 copias y ~35.009 USD.
-- Para las copias que no són rentables, muestra la cantidad de copias que aún no recuperan su costo
-- y cual es su brecha
SELECT COUNT(*)               AS COPIAS_SIN_RECUPERAR,
       ROUND(-SUM(RESULTADO)) AS BRECHA_USD
  FROM (SELECT FN_RENTABILIDAD_COPIA(INVENTORY_ID) AS RESULTADO FROM INVENTORY)
 WHERE RESULTADO < 0;


-- P2.2 En un SELECT: las 5 copias que más lejos están de pagarse solas.
SELECT *
  FROM (SELECT I.INVENTORY_ID,
               F.TITLE,
               I.STORE_ID,
               FN_RENTABILIDAD_COPIA(I.INVENTORY_ID) AS RENTABILIDAD
          FROM INVENTORY I
          JOIN FILM F ON F.FILM_ID = I.FILM_ID
         ORDER BY RENTABILIDAD)
 WHERE ROWNUM <= 5;


/* =========================================================================
   P3 · FN_CAPITAL_EN_RIESGO (función sin parámetros) · H9, corrección P1
   ========================================================================= */

-- P3.1 En un SELECT. Esperado: 20,99.
-- Mostramos el dinero acumulado de reposición de las copias que están fuera de la tienda y están fuera del plazo de la fecha tope
SELECT FN_CAPITAL_EN_RIESGO AS CAPITAL_EN_RIESGO FROM DUAL;

/* =========================================================================
   P4 · PKG_COBRANZA_INVENTARIO (package con miembros públicos y privados)
   ========================================================================= */

-- P4.1 PR_REPORTE_FUGA (sin parámetros) como sentencia SQL.
-- Esperado: 182 copias en VIGENTE, 1 en PERDIDA y capital total 20,99 USD.
-- Genera el reporte de fuga para todas las tiendas.
CALL PKG_COBRANZA_INVENTARIO.PR_REPORTE_FUGA();


-- P4.2 PR_REPORTE_FUGA_TIENDA (con parámetro) dentro de otro programa PL/SQL.
-- Genera el reporet de fuga para el Id de la tienda.
/*

Encabezado: == Tienda 1 == 

Un reporte de cada una de las copias que no están vigentes de mayor a menor atraso.
Copia 1 | ACADEMY DINOSAUR | 171 días | PERDIDA

Resuemn final del reporte
BANDA        COPIAS    CAPITAL      MULTA  ACCIÓN SUGERIDA
VIGENTE          90   1.795,10       0,00  Sin acción, plazo no vencido
RECUPERABLE       0       0,00       0,00  Recordatorio y cobro de multa
DUDOSA            0       0,00       0,00  Contacto directo, último aviso
PERDIDA           1      20,99      20,99  Facturar reposición al cliente
INCOBRABLE        0       0,00       0,00  Castigar activo y bloquear cliente
*/
BEGIN
  PKG_COBRANZA_INVENTARIO.PR_REPORTE_FUGA_TIENDA(1);
END;
/

-- P4.3 PR_REPORTE_RENTABILIDAD (con parámetro) como sentencia SQL.
-- Genera el reporte de rentabilidad del inventario para el ID de la tienda.
/*

Encabezado: === RENTABILIDAD TIENDA 1 ===

Resumen de las copias de la tienda contra su costo de reposición:
Copias en inventario: 2.270
Copias que aún no recuperan su costo: [N]
Brecha por recuperar: [monto] USD

Resumen del catálogo (H8):
Películas sin copia en esta tienda: [N]
Películas sin copia en ninguna tienda: 42

Esperado: entre las dos tiendas suman 4.581 copias, 3.331 sin recuperar
y una brecha de ~35.009 USD. Las 42 películas sin copia son las mismas
en ambos reportes, porque no dependen de la tienda.
*/
CALL PKG_COBRANZA_INVENTARIO.PR_REPORTE_RENTABILIDAD(1);
CALL PKG_COBRANZA_INVENTARIO.PR_REPORTE_RENTABILIDAD(2);


-- P4.4 PR_SIMULA_PLAZO dentro de otro programa PL/SQL: el dilema de 1 a 3 días extra.
-- Esperado: [Monto Multa Esperado] y [% devoluciones tarde]
BEGIN
  FOR i IN 1 .. 3 LOOP
    PKG_COBRANZA_INVENTARIO.PR_SIMULA_PLAZO(i);
    DBMS_OUTPUT.PUT_LINE(' ');
  END LOOP;
END;
/


-- P4.5 PR_PROCESO_MENSUAL (sin parámetros): orquesta fuga y rentabilidad de ambas tiendas.
BEGIN
  PKG_COBRANZA_INVENTARIO.PR_PROCESO_MENSUAL;
END;
/


-- P4.6 Errores controlados. Esperado: ORA-20203 y ORA-20204.
BEGIN
  PKG_COBRANZA_INVENTARIO.PR_SIMULA_PLAZO(-1);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('P4.7 ' || SQLERRM);
END;
/


-- P4.7 Los privados no son visibles desde fuera. Esperado: PLS-00302
-- (el componente FN_CLASIFICA_BANDA debe ser declarado).
BEGIN
  DBMS_OUTPUT.PUT_LINE(PKG_COBRANZA_INVENTARIO.FN_CLASIFICA_BANDA(171));
END;
/

ROLLBACK;

PROMPT Demostración: C1 TRG_VALIDA_PAGO_RENTAL

SET SERVEROUTPUT ON


--PRUEBA 1--
-- Probamos que un pago sin RENTAL_ID dispara el trigger y se rechaza.
BEGIN
    INSERT INTO PAYMENT (PAYMENT_ID, CUSTOMER_ID, STAFF_ID, RENTAL_ID, AMOUNT, PAYMENT_DATE)
    VALUES (SEQ_PAYMENT_ID.NEXTVAL, 1, 1, NULL, 2.99, SYSDATE); --> Con un RENTAL_ID nulo

    DBMS_OUTPUT.PUT_LINE('Prueba 1 FALLÓ: el pago sin arriendo entró');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 1 LOGRADO, pago rechazado: ' || SQLERRM);
END;
/

--PRUEBA 2--
-- Probamos que un pago con RENTAL_ID no se rechaza y entra
DECLARE
    V_RENTAL_ID   RENTAL.RENTAL_ID%TYPE;
    V_CUSTOMER_ID RENTAL.CUSTOMER_ID%TYPE;
    V_STAFF_ID    RENTAL.STAFF_ID%TYPE;
BEGIN
   
    SELECT RENTAL_ID, CUSTOMER_ID, STAFF_ID
    INTO V_RENTAL_ID, V_CUSTOMER_ID, V_STAFF_ID
    FROM RENTAL
    WHERE RENTAL_ID = (SELECT MIN(RENTAL_ID) FROM RENTAL);
 -- Buscamos el primer arriendo para que el pago sea verídico
 
    INSERT INTO PAYMENT (PAYMENT_ID, CUSTOMER_ID, STAFF_ID, RENTAL_ID, AMOUNT, PAYMENT_DATE)
    VALUES (SEQ_PAYMENT_ID.NEXTVAL, V_CUSTOMER_ID, V_STAFF_ID, V_RENTAL_ID, 2.99, SYSDATE);

    DBMS_OUTPUT.PUT_LINE('Prueba 2 LOGRADO: entró el pago ' || SEQ_PAYMENT_ID.CURRVAL
                         || ' del arriendo ' || V_RENTAL_ID);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 2 FALLÓ: ' || SQLERRM);
END;
/

SELECT COUNT(*) AS PAGOS_ANTES_DEL_ROLLBACK FROM PAYMENT;

ROLLBACK;

SELECT COUNT(*) AS PAGOS_DESPUES_DEL_ROLLBACK FROM PAYMENT;

PROMPT Demostración: C4 TRG_BLOQUEA_BORRADO_RENTAL

SET SERVEROUTPUT ON;



--PRUEBA 1------
-- Probamos que borrar un arriendo dispara el trigger y se rechaza
DECLARE
    V_RENTAL_ID RENTAL.RENTAL_ID%TYPE;
BEGIN
    SELECT MIN(RENTAL_ID) INTO V_RENTAL_ID FROM RENTAL;
    --Busca el primer arriendo Y intenta borrarlo.
    DELETE FROM RENTAL WHERE RENTAL_ID = V_RENTAL_ID;

    DBMS_OUTPUT.PUT_LINE('Prueba 1 FALLÓ: se borró el arriendo ' || V_RENTAL_ID);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 1 LOGRADO, borrado rechazado: ' || SQLERRM);
END;
/
----------------------------------------------------------------------------------------
--PRUEBA 2---
---El trigger se dispara apenas alguien escribe la orden DELETE aunque afecte a 0 filas
-- Probamos que se dispara aunque el DELETE no encuentre arriendos, porque es de sentencia
BEGIN
    DELETE FROM RENTAL WHERE RENTAL_ID = -1;
    --No existe ningún arriendo con número -1, así que este DELETE no borraría nada. Pero aun así C4 lo rechazaria

    DBMS_OUTPUT.PUT_LINE('Prueba 2 FALLÓ: el DELETE sin filas no se rechazó');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 2 LOGRADO, se rechazó aunque no había filas: ' || SQLERRM);
END;
/
-------------------------------------------------------------------------------
---PRUEBA 3---
-- Probamos que un UPDATE en RENTAL no dispara el trigger
DECLARE
    V_RENTAL_ID RENTAL.RENTAL_ID%TYPE;
BEGIN
    SELECT MIN(RENTAL_ID) INTO V_RENTAL_ID FROM RENTAL;

    UPDATE RENTAL SET STAFF_ID = STAFF_ID WHERE RENTAL_ID = V_RENTAL_ID;

    DBMS_OUTPUT.PUT_LINE('Prueba 3 LOGRADO: se actualizó el arriendo ' || V_RENTAL_ID);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 3 FALLIDO: ' || SQLERRM);
END;
/

-----------PRUEBA DE QUE NO SE BORRO NADA-----
SELECT (SELECT COUNT(*) FROM RENTAL)AS ARRIENDOS,
       (SELECT COUNT(*) FROM PAYMENT WHERE RENTAL_ID IS NULL) AS PAGOS_SIN_ARRIENDO
FROM DUAL;

ROLLBACK;

PROMPT Demostración: C5 TRG_AUDITA_RENTAL y TRG_AUDITA_PAYMENT

SET SERVEROUTPUT ON;

--PRUEBA 1----
-- Contamos las líneas de auditoría antes de las pruebas
SELECT COUNT(*) AS LINEAS_ANTES FROM AUDITORIA_SAKILA;

-- Probamos que un UPDATE de varios arriendos deja una sola línea 
--TRG_AUDITA_RENTAL es de sentencia
BEGIN
    UPDATE RENTAL SET STAFF_ID = STAFF_ID WHERE ROWNUM <= 3;

    DBMS_OUTPUT.PUT_LINE('Prueba 1: se actualizaron ' || SQL%ROWCOUNT || ' arriendos con una sola orden');
END;
/

--PRUEBA2
-- Probamos que borrar un pago queda anotado (TRG_AUDITA_PAYMENT)
DECLARE
    V_PAYMENT_ID PAYMENT.PAYMENT_ID%TYPE;
BEGIN
    SELECT MIN(PAYMENT_ID) INTO V_PAYMENT_ID FROM PAYMENT;

    DELETE FROM PAYMENT WHERE PAYMENT_ID = V_PAYMENT_ID;

    DBMS_OUTPUT.PUT_LINE('Prueba 2: se borró el pago ' || V_PAYMENT_ID);
END;
/

--PRUEBA 3----
-- Probamos que una operación rechazada no se anota: C4 frena el DELETE antes de que ocurra
BEGIN
    DELETE FROM RENTAL WHERE ROWNUM = 1;
    -- ROWNUM se refiere a encontrar las primeras 3 filas

    DBMS_OUTPUT.PUT_LINE('Prueba 3 FALLÓ: se borró un arriendo');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 3: C4 rechazó el borrado, así que no debe quedar línea');
END;
/

-- Revisamos lo que anotó la auditoría las cuales deben ser 2 líneas, RENTAL UPDATE y PAYMENT DELETE
SELECT ID_AUDITORIA, TABLA, OPERACION, USUARIO,
       TO_CHAR(FECHA, 'DD/MM/YYYY HH24:MI:SS') AS FECHA
FROM AUDITORIA_SAKILA
ORDER BY ID_AUDITORIA;

ROLLBACK;

-- Comprobamos que el ROLLBACK borró las líneas y devolvió el pago
SELECT (SELECT COUNT(*) FROM AUDITORIA_SAKILA) AS LINEAS_DESPUES,
       (SELECT COUNT(*) FROM PAYMENT)AS PAGOS
FROM DUAL;

PROMPT Demostración: C3 TRG_VALIDA_ARRIENDO

SET SERVEROUTPUT ON




--PRUEBA1---
-- Probamos que un cliente que puede arrendar pasa INSERT..VALUES de una fila
DECLARE
    V_RENTAL_ID  RENTAL.RENTAL_ID%TYPE;
    V_CLIENTE    RENTAL.CUSTOMER_ID%TYPE;
    V_COPIA      RENTAL.INVENTORY_ID%TYPE;
    V_EMPLEADO   RENTAL.STAFF_ID%TYPE;
    V_FECHA      RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
BEGIN
    SELECT MAX(RENTAL_ID) + 1 INTO V_RENTAL_ID FROM RENTAL;
    SELECT MIN(CUSTOMER_ID) INTO V_CLIENTE FROM CUSTOMER WHERE FN_PUEDE_ARRENDAR(CUSTOMER_ID) = 'SI';
    SELECT MIN(INVENTORY_ID) INTO V_COPIA FROM INVENTORY I
    WHERE NOT EXISTS (SELECT 1 FROM RENTAL R WHERE R.INVENTORY_ID = I.INVENTORY_ID AND R.RETURN_DATE IS NULL);
    SELECT MIN(STAFF_ID) INTO V_EMPLEADO FROM STAFF;

    INSERT INTO RENTAL (RENTAL_ID, RENTAL_DATE, INVENTORY_ID, CUSTOMER_ID, RETURN_DATE, STAFF_ID)
    VALUES (V_RENTAL_ID, V_FECHA, V_COPIA, V_CLIENTE, NULL, V_EMPLEADO);

    DBMS_OUTPUT.PUT_LINE('Prueba 1 LOGRADO: el cliente ' || V_CLIENTE || ' arrendó la copia ' || V_COPIA);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 1 FALLÓ: ' || SQLERRM);
END;
/
--PRUEBA 2--
-- Probamos que un cliente inactivo dispara el trigger y se rechaza
DECLARE
    V_RENTAL_ID  RENTAL.RENTAL_ID%TYPE;
    V_CLIENTE    RENTAL.CUSTOMER_ID%TYPE;
    V_COPIA      RENTAL.INVENTORY_ID%TYPE;
    V_EMPLEADO   RENTAL.STAFF_ID%TYPE;
    V_FECHA      RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
BEGIN
    SELECT MAX(RENTAL_ID) + 1 INTO V_RENTAL_ID FROM RENTAL;
    SELECT MIN(CUSTOMER_ID) INTO V_CLIENTE FROM CUSTOMER WHERE ACTIVE IN ('0', 'N');
    SELECT MIN(INVENTORY_ID) INTO V_COPIA FROM INVENTORY I
    WHERE NOT EXISTS (SELECT 1 FROM RENTAL R WHERE R.INVENTORY_ID = I.INVENTORY_ID AND R.RETURN_DATE IS NULL);
    SELECT MIN(STAFF_ID) INTO V_EMPLEADO FROM STAFF;

    INSERT INTO RENTAL (RENTAL_ID, RENTAL_DATE, INVENTORY_ID, CUSTOMER_ID, RETURN_DATE, STAFF_ID)
    VALUES (V_RENTAL_ID, V_FECHA, V_COPIA, V_CLIENTE, NULL, V_EMPLEADO);

    DBMS_OUTPUT.PUT_LINE('Prueba 2 FALLÓ: el cliente inactivo ' || V_CLIENTE || ' pudo arrendar');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 2 LOGRADO, arriendo rechazado: ' || SQLERRM);
END;
/

--PRUEBA3---
-- Probamos el riesgo de tabla mutante, el mismo arriendo válido, pero con INSERT..SELECT
DECLARE
    V_RENTAL_ID  RENTAL.RENTAL_ID%TYPE;
    V_CLIENTE    RENTAL.CUSTOMER_ID%TYPE;
    V_COPIA      RENTAL.INVENTORY_ID%TYPE;
    V_EMPLEADO   RENTAL.STAFF_ID%TYPE;
    V_FECHA      RENTAL.RENTAL_DATE%TYPE := FN_FECHA_CORTE;
BEGIN
    SELECT MAX(RENTAL_ID) + 1 INTO V_RENTAL_ID FROM RENTAL;
    SELECT MIN(CUSTOMER_ID) INTO V_CLIENTE FROM CUSTOMER WHERE FN_PUEDE_ARRENDAR(CUSTOMER_ID) = 'SI';
    SELECT MAX(INVENTORY_ID) INTO V_COPIA FROM INVENTORY I
    WHERE NOT EXISTS (SELECT 1 FROM RENTAL R WHERE R.INVENTORY_ID = I.INVENTORY_ID AND R.RETURN_DATE IS NULL);
    SELECT MIN(STAFF_ID) INTO V_EMPLEADO FROM STAFF;

    INSERT INTO RENTAL (RENTAL_ID, RENTAL_DATE, INVENTORY_ID, CUSTOMER_ID, RETURN_DATE, STAFF_ID)
    SELECT V_RENTAL_ID, V_FECHA, V_COPIA, V_CLIENTE, NULL, V_EMPLEADO FROM DUAL;

    DBMS_OUTPUT.PUT_LINE('Prueba 3: el INSERT..SELECT entró sin error');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 3 LIMITACIÓN CONFIRMADA: ' || SQLERRM);
END;
/
/*
 la prueba 3 se lee de abajo hacia arriba, el trigger llamó a la función de Gabriel, 
 que llamó a FN_FECHA_CORTE, que intentó leer RENTAL. Ahí Oracle dijo “tabla mutante”
*/



-- Revisamos los arriendos y la auditoría antes de deshacer
SELECT (SELECT COUNT(*) FROM RENTAL)AS ARRIENDOS,
       (SELECT COUNT(*) FROM AUDITORIA_SAKILA) AS LINEAS_AUDITORIA
FROM DUAL;

SELECT TABLA, OPERACION FROM AUDITORIA_SAKILA ORDER BY ID_AUDITORIA;

ROLLBACK;

SELECT (SELECT COUNT(*) FROM RENTAL)AS ARRIENDOS,
       (SELECT COUNT(*) FROM AUDITORIA_SAKILA) AS LINEAS_AUDITORIA
FROM DUAL;

PROMPT Demostración: C2 TRG_TOPE_MULTA_DEVOLUCION

SET SERVEROUTPUT ON


--PRUEBA 1---
-- Probamos que devolver con mucho atraso cobra la multa con tope 
DECLARE
    V_RENTAL_ID RENTAL.RENTAL_ID%TYPE;
    V_FECHA     RENTAL.RETURN_DATE%TYPE := FN_FECHA_CORTE;
    V_DIAS      NUMBER;
    V_COSTO     FILM.REPLACEMENT_COST%TYPE;
    V_COBRADO   PAYMENT.AMOUNT%TYPE;
BEGIN
    SELECT R.RENTAL_ID, TRUNC(V_FECHA) - TRUNC(R.RENTAL_DATE) - F.RENTAL_DURATION, F.REPLACEMENT_COST
    INTO V_RENTAL_ID, V_DIAS, V_COSTO
    FROM RENTAL R
    JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
    JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
    WHERE R.RETURN_DATE IS NULL
      AND TRUNC(V_FECHA) - TRUNC(R.RENTAL_DATE) - F.RENTAL_DURATION > F.REPLACEMENT_COST;

    UPDATE RENTAL SET RETURN_DATE = V_FECHA WHERE RENTAL_ID = V_RENTAL_ID;

    SELECT AMOUNT INTO V_COBRADO
    FROM PAYMENT
    WHERE PAYMENT_ID = 
    (SELECT MAX(PAYMENT_ID) FROM PAYMENT WHERE RENTAL_ID = V_RENTAL_ID);

    DBMS_OUTPUT.PUT_LINE('Prueba 1 LOGRADO: el arriendo ' || V_RENTAL_ID || ' tenía ' || V_DIAS
                         || ' días de atraso y se cobraron ' || V_COBRADO || ' USD, el costo de la copia');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 1 FALLÓ: ' || SQLERRM);
END;
/


-- PRUEBA 2 Probamos que devolver dentro del plazo no crea ningún pago
DECLARE
    V_RENTAL_ID RENTAL.RENTAL_ID%TYPE;
    V_FECHA     RENTAL.RETURN_DATE%TYPE := FN_FECHA_CORTE;
    V_PAGOS     NUMBER;
BEGIN
    SELECT MIN(RENTAL_ID) INTO V_RENTAL_ID
    FROM RENTAL
    WHERE RETURN_DATE IS NULL AND RENTAL_DATE = V_FECHA;

    UPDATE RENTAL SET RETURN_DATE = V_FECHA WHERE RENTAL_ID = V_RENTAL_ID;

    SELECT COUNT(*) 
    INTO V_PAGOS FROM PAYMENT WHERE RENTAL_ID = V_RENTAL_ID;

    DBMS_OUTPUT.PUT_LINE('Prueba 2 LOGRADO: el arriendo ' || V_RENTAL_ID
                         || ' volvió a tiempo y sigue con ' || V_PAGOS || ' pago (el original)');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 2 FALLÓ: ' || SQLERRM);
END;
/

-- Revisamos el pago nuevo y la cadena de triggers antes de deshacer
SELECT PAYMENT_ID, CUSTOMER_ID, RENTAL_ID, AMOUNT, TO_CHAR(PAYMENT_DATE, 'DD/MM/YYYY') AS FECHA_PAGO
FROM PAYMENT
WHERE PAYMENT_ID = (SELECT MAX(PAYMENT_ID) FROM PAYMENT);

SELECT 
    TABLA, OPERACION 
    FROM AUDITORIA_SAKILA ORDER BY ID_AUDITORIA;

ROLLBACK; 

SELECT (SELECT COUNT(*) FROM PAYMENT) AS PAGOS,
       (SELECT COUNT(*) FROM RENTAL WHERE RETURN_DATE IS NULL) AS SIN_DEVOLVER,
       (SELECT COUNT(*) FROM AUDITORIA_SAKILA) AS LINEAS_AUDITORIA
FROM DUAL;

PROMPT Consultas de evidencia: cifras H1 a H10

WITH
ARRIENDO AS (
    SELECT R.RENTAL_ID,
           R.CUSTOMER_ID,
           R.RENTAL_DATE,
           R.RETURN_DATE,
           F.RENTAL_DURATION,
           F.RENTAL_RATE,
           F.REPLACEMENT_COST
    FROM RENTAL R
    JOIN INVENTORY I ON I.INVENTORY_ID = R.INVENTORY_ID
    JOIN FILM F      ON F.FILM_ID      = I.FILM_ID
),
CORTE AS (
    SELECT MAX(RENTAL_DATE) AS FECHA_CORTE
    FROM RENTAL
),
DEVUELTO AS (
    SELECT A.*,
           TRUNC(A.RETURN_DATE) - TRUNC(A.RENTAL_DATE) AS DIAS
    FROM ARRIENDO A
    WHERE A.RETURN_DATE IS NOT NULL
),
SIN_DEVOLVER AS (
    SELECT A.*,
           TRUNC(C.FECHA_CORTE) - TRUNC(A.RENTAL_DATE) - A.RENTAL_DURATION AS DIAS_ATRASO
    FROM ARRIENDO A
    CROSS JOIN CORTE C
    WHERE A.RETURN_DATE IS NULL
),
CON_VENCIDA AS (
    SELECT B.RENTAL_ID,
           B.CUSTOMER_ID
    FROM ARRIENDO B
    WHERE EXISTS (
        SELECT 1
        FROM ARRIENDO A
        WHERE A.CUSTOMER_ID = B.CUSTOMER_ID
          AND A.RENTAL_ID  <> B.RENTAL_ID
          AND TRUNC(B.RENTAL_DATE) - TRUNC(A.RENTAL_DATE) > A.RENTAL_DURATION
          AND (A.RETURN_DATE IS NULL OR A.RETURN_DATE > B.RENTAL_DATE)
    )
),
COPIA AS (
    SELECT I.INVENTORY_ID,
           F.REPLACEMENT_COST,
           NVL(SUM(P.AMOUNT), 0) AS INGRESO
    FROM INVENTORY I
    JOIN FILM F         ON F.FILM_ID      = I.FILM_ID
    LEFT JOIN RENTAL R  ON R.INVENTORY_ID = I.INVENTORY_ID
    LEFT JOIN PAYMENT P ON P.RENTAL_ID    = R.RENTAL_ID
    GROUP BY I.INVENTORY_ID, F.REPLACEMENT_COST
),
TABLA_SAKILA AS (
    SELECT TABLE_NAME
    FROM USER_TABLES
    WHERE TABLE_NAME IN ('ACTOR', 'ADDRESS', 'CATEGORY', 'CITY', 'COUNTRY',
                         'CUSTOMER', 'FILM', 'FILM_ACTOR', 'FILM_CATEGORY',
                         'FILM_TEXT', 'INVENTORY', 'LANGUAGE', 'PAYMENT',
                         'RENTAL', 'STAFF', 'STORE')
)
SELECT ORDEN,
       HALLAZGO,
       DATO,
       VALOR_ORACLE,
       VALOR_PLAN,
       CASE WHEN VALOR_ORACLE = VALOR_PLAN THEN 'OK' ELSE 'REVISAR' END AS ESTADO
FROM (
    SELECT 1 AS ORDEN, 'H1' AS HALLAZGO, 'Pagos con RENTAL_ID nulo' AS DATO,
           COUNT(CASE WHEN RENTAL_ID IS NULL THEN 1 END) AS VALOR_ORACLE, 5 AS VALOR_PLAN
    FROM PAYMENT
    UNION ALL
    SELECT 2, 'H1', 'Pagos totales', COUNT(*), 16049
    FROM PAYMENT
    UNION ALL
    SELECT 3, 'H2', 'FK_PAYMENT_RENTAL es ON DELETE SET NULL (1 = si)', COUNT(*), 1
    FROM USER_CONSTRAINTS
    WHERE CONSTRAINT_NAME = 'FK_PAYMENT_RENTAL'
      AND DELETE_RULE     = 'SET NULL'
    UNION ALL
    SELECT 4, 'H3', 'Dias promedio que se retiene una pelicula', ROUND(AVG(DIAS), 1), 5
    FROM DEVUELTO
    UNION ALL
    SELECT 5, 'H3', '% devoluciones tarde con plazo de 3 dias',
           ROUND(100 * AVG(CASE WHEN DIAS > RENTAL_DURATION THEN 1 ELSE 0 END), 1), 66.9
    FROM DEVUELTO
    WHERE RENTAL_DURATION = 3
    UNION ALL
    SELECT 6, 'H3', '% devoluciones tarde con plazo de 7 dias',
           ROUND(100 * AVG(CASE WHEN DIAS > RENTAL_DURATION THEN 1 ELSE 0 END), 1), 23.3
    FROM DEVUELTO
    WHERE RENTAL_DURATION = 7
    UNION ALL
    SELECT 7, 'H3', '% devoluciones tarde en total',
           ROUND(100 * AVG(CASE WHEN DIAS > RENTAL_DURATION THEN 1 ELSE 0 END), 1), 45.8
    FROM DEVUELTO
    UNION ALL
    SELECT 8, 'H4', 'Multa cobrada USD (monto sobre la tarifa)',
           ROUND(SUM(P.AMOUNT - D.RENTAL_RATE)), 20192
    FROM PAYMENT P
    JOIN DEVUELTO D ON D.RENTAL_ID = P.RENTAL_ID
    UNION ALL
    SELECT 9, 'H4', 'Ingreso total USD', ROUND(SUM(AMOUNT)), 67417
    FROM PAYMENT
    UNION ALL
    SELECT 10, 'H4', '% del ingreso que es multa', ROUND(100 * M.MULTA / T.TOTAL), 30
    FROM (SELECT SUM(P.AMOUNT - D.RENTAL_RATE) AS MULTA
          FROM PAYMENT P
          JOIN DEVUELTO D ON D.RENTAL_ID = P.RENTAL_ID) M
    CROSS JOIN (SELECT SUM(AMOUNT) AS TOTAL FROM PAYMENT) T
    UNION ALL
    SELECT 11, 'H4', 'Pagos que no siguen tarifa + 1 USD por dia de calendario de atraso', COUNT(*), 0
    FROM PAYMENT P
    JOIN DEVUELTO D ON D.RENTAL_ID = P.RENTAL_ID
    WHERE P.AMOUNT <> D.RENTAL_RATE + GREATEST(D.DIAS - D.RENTAL_DURATION, 0)
    UNION ALL
    SELECT 12, 'H5', 'Clientes que arrendaron con otra copia vencida en casa',
           COUNT(DISTINCT CUSTOMER_ID), 490
    FROM CON_VENCIDA
    UNION ALL
    SELECT 13, 'H5', 'Arriendos hechos con otra copia vencida en casa', COUNT(*), 1709
    FROM CON_VENCIDA
    UNION ALL
    SELECT 14, 'H6', 'Clientes inactivos', COUNT(*), 15
    FROM CUSTOMER
    WHERE ACTIVE IN ('0', 'N')
    UNION ALL
    SELECT 15, 'H6', 'Arriendos de clientes inactivos', COUNT(*), 404
    FROM RENTAL R
    JOIN CUSTOMER C ON C.CUSTOMER_ID = R.CUSTOMER_ID
    WHERE C.ACTIVE IN ('0', 'N')
    UNION ALL
    SELECT 16, 'H7', 'Copias que aun no recuperan su costo de reposicion',
           COUNT(CASE WHEN INGRESO < REPLACEMENT_COST THEN 1 END), 3331
    FROM COPIA
    UNION ALL
    SELECT 17, 'H7', 'Copias en inventario', COUNT(*), 4581
    FROM COPIA
    UNION ALL
    SELECT 18, 'H7', 'Brecha por recuperar USD',
           ROUND(SUM(CASE WHEN INGRESO < REPLACEMENT_COST
                          THEN REPLACEMENT_COST - INGRESO END)), 35009
    FROM COPIA
    UNION ALL
    SELECT 19, 'H8', 'Peliculas sin ninguna copia en inventario', COUNT(*), 42
    FROM FILM F
    WHERE NOT EXISTS (SELECT 1 FROM INVENTORY I WHERE I.FILM_ID = F.FILM_ID)
    UNION ALL
    SELECT 20, 'H8', 'Peliculas en catalogo', COUNT(*), 1000
    FROM FILM
    UNION ALL
    SELECT 21, 'H9', 'Copias sin devolver cuya multa supera su costo',
           COUNT(CASE WHEN DIAS_ATRASO > REPLACEMENT_COST THEN 1 END), 1
    FROM SIN_DEVOLVER
    UNION ALL
    SELECT 22, 'H9', 'Dias de atraso de esa copia',
           MAX(CASE WHEN DIAS_ATRASO > REPLACEMENT_COST THEN DIAS_ATRASO END), 171
    FROM SIN_DEVOLVER
    UNION ALL
    SELECT 23, 'H9', 'Costo de reposicion de esa copia USD',
           MAX(CASE WHEN DIAS_ATRASO > REPLACEMENT_COST THEN REPLACEMENT_COST END), 20.99
    FROM SIN_DEVOLVER
    UNION ALL
    SELECT 24, 'H10', 'Tablas de Sakila con LAST_UPDATE', COUNT(*), 15
    FROM USER_TAB_COLUMNS
    WHERE COLUMN_NAME = 'LAST_UPDATE'
      AND TABLE_NAME IN (SELECT TABLE_NAME FROM TABLA_SAKILA)
    UNION ALL
    SELECT 25, 'H10', 'Columnas de Sakila que guardan usuario u operacion', COUNT(*), 0
    FROM USER_TAB_COLUMNS
    WHERE TABLE_NAME IN (SELECT TABLE_NAME FROM TABLA_SAKILA)
      AND (COLUMN_NAME LIKE '%USUARIO%'
           OR COLUMN_NAME LIKE '%OPERA%'
           OR COLUMN_NAME LIKE '%MODIFIED%'
           OR COLUMN_NAME LIKE '%CREATED%')
    UNION ALL
    SELECT 26, 'P1', 'Fecha de corte = ultimo arriendo exacto (AAAAMMDDHH24MISS)',
           TO_NUMBER(TO_CHAR(FECHA_CORTE, 'YYYYMMDDHH24MISS')), 20060214151603
    FROM CORTE
    UNION ALL
    SELECT 27, 'P1', 'Arriendos sin devolver', COUNT(*), 183
    FROM SIN_DEVOLVER
    UNION ALL
    SELECT 28, 'P1', 'Sin devolver arrendados en el ultimo instante del dataset', COUNT(*), 182
    FROM SIN_DEVOLVER S
    JOIN CORTE C ON S.RENTAL_DATE = C.FECHA_CORTE
    UNION ALL
    SELECT 29, 'P1', 'Fuga real: sin devolver y vencidos a la fecha de corte',
           COUNT(CASE WHEN DIAS_ATRASO > 0 THEN 1 END), 1
    FROM SIN_DEVOLVER
    UNION ALL
    SELECT 30, 'P1', 'Arriendos con exactamente un pago', COUNT(*), 16044
    FROM (SELECT RENTAL_ID
          FROM PAYMENT
          WHERE RENTAL_ID IS NOT NULL
          GROUP BY RENTAL_ID
          HAVING COUNT(*) = 1)
    UNION ALL
    SELECT 31, 'P1', 'Tarifa ya pagada por los arriendos sin devolver USD', SUM(P.AMOUNT), 518.17
    FROM PAYMENT P
    JOIN SIN_DEVOLVER S ON S.RENTAL_ID = P.RENTAL_ID
    UNION ALL
    SELECT 32, 'RIESGO', 'PAYMENT_SEQUENCE de Sakila choca con PAYMENT_ID cargados (1 = si)',
           CASE WHEN S.LAST_NUMBER <= (SELECT MAX(PAYMENT_ID) FROM PAYMENT) THEN 1 ELSE 0 END, 1
    FROM USER_SEQUENCES S
    WHERE S.SEQUENCE_NAME = 'PAYMENT_SEQUENCE'
    UNION ALL
    SELECT 33, 'RIESGO', 'RENTAL_SEQUENCE de Sakila choca con RENTAL_ID cargados (1 = si)',
           CASE WHEN S.LAST_NUMBER <= (SELECT MAX(RENTAL_ID) FROM RENTAL) THEN 1 ELSE 0 END, 1
    FROM USER_SEQUENCES S
    WHERE S.SEQUENCE_NAME = 'RENTAL_SEQUENCE'
)
ORDER BY ORDEN;
