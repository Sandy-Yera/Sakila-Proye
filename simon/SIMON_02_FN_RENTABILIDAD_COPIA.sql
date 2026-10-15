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