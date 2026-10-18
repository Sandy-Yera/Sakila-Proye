Nota de diseño: llamadas entre packages y funciones sueltas

Contexto. FN_FECHA_CORTE la usan PKG_RESPONSABILIDAD_CLIENTE y PKG_COBRANZA_INVENTARIO. No justifica un package propio, porque es una sola función.
Al consultarlo con el docente surgió la duda de si un package, al compilarse como una unidad, puede llamar a una función externa o a otro package, o si habría que repetir la función dentro de cada uno.

Qué verificamos. Creamos en Oracle 21c una función suelta, un package A que la llama y un package B que llama a A. Después borramos los tres objetos.

[código de la prueba]
[captura: salida del SELECT y los tres objetos en estado VALID en USER_OBJECTS]

Qué concluimos.

Un package puede llamar a funciones sueltas y a miembros públicos de otros packages. Al compilarse, guarda una referencia a esos objetos, visible en USER_DEPENDENCIES.
Si un objeto referenciado cambia, el package queda INVALID y Oracle intenta recompilarlo en la siguiente llamada. Si el objeto se borra, la llamada falla.
Los miembros privados de un package no son visibles desde fuera.
Por defecto (AUTHID DEFINER), el package se ejecuta con los permisos de su dueño. Quien tiene EXECUTE sobre el package puede usarlo aunque no tenga permiso sobre las funciones ni las tablas que el package consulta.

Decisión. Mantenemos FN_FECHA_CORTE como función suelta compartida. Repetirla dentro de cada package dejaría dos copias de la misma regla, que podrían terminar dando fechas distintas; 
es justamente el error de la P1 que corrige la regla 4 del plan. Por eso el script crea primero las funciones sueltas y después los bodies de los packages.
