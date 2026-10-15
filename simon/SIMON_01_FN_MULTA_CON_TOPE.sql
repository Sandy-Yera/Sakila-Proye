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