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