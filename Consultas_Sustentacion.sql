-- ============================================================================
-- CONSULTAS PARA LA SUSTENTACION TECNICA
-- Sistema de Punto de Venta y Cocina "El Pastor Dorado"
-- Ejecutar en pgAdmin Query Tool sobre la base de datos pastor_dorado.
-- Se recomienda ejecutar bloque por bloque para explicar cada resultado.
--
-- NOTA: la seccion 4 crea una orden real (mesa 99) y la seccion 6 la cobra.
-- Si deseas dejar la base como al inicio, vuelve a ejecutar El_Pastor_Dorado.sql.
-- ============================================================================

-- ============================================================================
-- 1. CONSULTAS BASICAS: MOSTRAR LAS TABLAS
-- ============================================================================

-- 1.1 Categorias del menu
SELECT *
FROM categoria
ORDER BY id_categoria;

-- 1.2 Productos con su categoria y stock
SELECT
    p.id_producto,
    p.nombre AS producto,
    c.nombre AS categoria,
    p.precio_unitario,
    p.stock_porciones,
    p.stock_minimo,
    p.estado
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria
ORDER BY c.nombre, p.nombre;

-- 1.3 Empleados
SELECT *
FROM empleado
ORDER BY id_empleado;

-- 1.4 Ordenes con el nombre del empleado que atendio
SELECT
    o.id_orden,
    o.numero_mesa,
    e.nombres || ' ' || e.apellidos AS empleado,
    e.turno,
    o.tipo_servicio,
    o.fecha_hora,
    o.subtotal,
    o.propina,
    o.total,
    o.estado
FROM orden o
JOIN empleado e ON e.id_empleado = o.id_empleado
ORDER BY o.id_orden;

-- 1.5 Detalle de una orden con el nombre del producto
SELECT
    d.id_detalle,
    d.id_orden,
    p.nombre AS producto,
    d.cantidad,
    d.precio_unitario_historico,
    d.importe_linea,
    d.notas_preparacion
FROM detalle_orden d
JOIN producto p ON p.id_producto = d.id_producto
ORDER BY d.id_orden, d.id_detalle;

-- 1.6 Pagos registrados
SELECT
    pg.id_pago,
    pg.id_orden,
    pg.metodo_pago,
    pg.monto_pagado,
    pg.cambio,
    pg.fecha_hora_pago,
    pg.referencia_transaccion
FROM pago pg
ORDER BY pg.id_pago;

-- ============================================================================
-- 2. CONSULTAS CON AGREGACIONES (GROUP BY)
-- ============================================================================

-- 2.1 Total vendido por categoria (solo ordenes cobradas)
SELECT
    c.nombre AS categoria,
    SUM(d.cantidad) AS unidades_vendidas,
    SUM(d.importe_linea) AS total_vendido
FROM detalle_orden d
JOIN producto p ON p.id_producto = d.id_producto
JOIN categoria c ON c.id_categoria = p.id_categoria
JOIN orden o ON o.id_orden = d.id_orden
WHERE o.estado = 'Cobrada'
GROUP BY c.nombre
ORDER BY total_vendido DESC;

-- 2.2 Productos mas vendidos
SELECT
    p.nombre AS producto,
    SUM(d.cantidad) AS unidades_vendidas,
    SUM(d.importe_linea) AS ingresos
FROM detalle_orden d
JOIN producto p ON p.id_producto = d.id_producto
JOIN orden o ON o.id_orden = d.id_orden
WHERE o.estado = 'Cobrada'
GROUP BY p.nombre
ORDER BY unidades_vendidas DESC, ingresos DESC;

-- 2.3 Ventas por empleado y turno
SELECT
    e.nombres || ' ' || e.apellidos AS empleado,
    e.turno,
    COUNT(DISTINCT o.id_orden) AS numero_ordenes,
    SUM(o.subtotal) AS subtotal,
    SUM(o.propina) AS propinas,
    SUM(o.total) AS total
FROM orden o
JOIN empleado e ON e.id_empleado = o.id_empleado
WHERE o.estado = 'Cobrada'
GROUP BY e.nombres, e.apellidos, e.turno
ORDER BY total DESC;

-- 2.4 Totales por metodo de pago
SELECT
    metodo_pago,
    COUNT(*) AS numero_pagos,
    SUM(monto_pagado) AS total_pagado,
    SUM(cambio) AS total_cambio,
    SUM(monto_pagado - cambio) AS total_recaudado
FROM pago
GROUP BY metodo_pago
ORDER BY total_recaudado DESC;

-- 2.5 Promedio de consumo por orden cobrada
SELECT
    ROUND(AVG(total), 2) AS promedio_por_orden,
    MIN(total) AS orden_mas_baja,
    MAX(total) AS orden_mas_alta
FROM orden
WHERE estado = 'Cobrada';

-- ============================================================================
-- 3. VISTAS DE NEGOCIO
-- ============================================================================

-- 3.1 Menu disponible para cocina
SELECT *
FROM v_menudisponiblecocina
ORDER BY id_producto;

-- 3.2 Comandas pendientes con tiempo transcurrido
SELECT *
FROM v_comandaspendientes
ORDER BY minutos_transcurridos DESC;

-- 3.3 Reporte de ventas del dia por turno y metodo de pago
SELECT *
FROM v_reporteventasturno
ORDER BY turno, metodo_pago;

-- ============================================================================
-- 4. DEMOSTRACION DE TRIGGERS: CASO DE EXITO
-- Se crea una orden nueva, se agrega un detalle y se observa como el trigger
-- descuenta stock y recalcula subtotal y total automaticamente.
-- ============================================================================

-- 4.1 Crear una tabla temporal para guardar el ID de la orden de demostracion
CREATE TEMP TABLE IF NOT EXISTS demo_ctx (
    id_orden INTEGER
);
TRUNCATE demo_ctx;

-- 4.2 Crear la orden de demostracion
WITH nueva AS (
    INSERT INTO orden (id_empleado, numero_mesa, tipo_servicio, propina)
    VALUES (2, 99, 'Comedor', 5.00)
    RETURNING id_orden
)
INSERT INTO demo_ctx (id_orden)
SELECT id_orden FROM nueva;

-- 4.3 Ver el ID generado
SELECT id_orden AS orden_de_demostracion
FROM demo_ctx;

-- 4.4 Ver el stock del producto 1 antes de la venta
SELECT
    id_producto,
    nombre,
    stock_porciones,
    estado
FROM producto
WHERE id_producto = 1;

-- 4.5 Insertar 2 tacos al pastor en la orden de demostracion
INSERT INTO detalle_orden
    (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea, notas_preparacion)
VALUES
    ((SELECT id_orden FROM demo_ctx), 1, 2, 15.00, 30.00, 'Sin cebolla');

-- 4.6 Ver el stock despues de la venta
SELECT
    id_producto,
    nombre,
    stock_porciones,
    estado
FROM producto
WHERE id_producto = 1;

-- 4.7 Ver como el trigger actualizo subtotal y total
SELECT
    id_orden,
    subtotal,
    propina,
    total,
    estado
FROM orden
WHERE id_orden = (SELECT id_orden FROM demo_ctx);

-- ============================================================================
-- 5. DEMOSTRACION DE TRIGGERS: CASOS DE FALLO CONTROLADO
-- Los bloques DO capturan el error y muestran el mensaje sin romper la sesion.
-- ============================================================================

-- 5.1 Fallo: cantidad mayor al stock disponible
DO $$
DECLARE
    v_id_orden INTEGER;
BEGIN
    SELECT id_orden INTO v_id_orden FROM demo_ctx;

    INSERT INTO detalle_orden
        (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea)
    VALUES
        (v_id_orden, 1, 9999, 15.00, 149985.00);

    RAISE NOTICE 'PRUEBA STOCK (FALLO): la insercion no fue bloqueada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA STOCK (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- 5.2 Fallo: producto en estado Agotado
DO $$
DECLARE
    v_id_orden INTEGER;
BEGIN
    SELECT id_orden INTO v_id_orden FROM demo_ctx;

    INSERT INTO detalle_orden
        (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea)
    VALUES
        (v_id_orden, 13, 1, 20.00, 20.00);

    RAISE NOTICE 'PRUEBA AGOTADO (FALLO): la insercion no fue bloqueada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA AGOTADO (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- 5.3 Fallo: cobrar la orden sin pagos registrados
DO $$
DECLARE
    v_id_orden INTEGER;
BEGIN
    SELECT id_orden INTO v_id_orden FROM demo_ctx;

    UPDATE orden
       SET estado = 'Cobrada'
     WHERE id_orden = v_id_orden;

    RAISE NOTICE 'PRUEBA COBRO SIN PAGO (FALLO): la orden fue cobrada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA COBRO SIN PAGO (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- ============================================================================
-- 6. DEMOSTRACION DE TRIGGERS: CASO DE EXITO AL COBRAR
-- ============================================================================

-- 6.1 Registrar el pago completo de la orden de demostracion
INSERT INTO pago
    (id_orden, metodo_pago, monto_pagado, cambio, referencia_transaccion)
VALUES
    ((SELECT id_orden FROM demo_ctx), 'Efectivo', 35.00, 0.00, 'DEMO-PAGO-001');

-- 6.2 Cambiar la orden a Cobrada
UPDATE orden
SET estado = 'Cobrada'
WHERE id_orden = (SELECT id_orden FROM demo_ctx);

-- 6.3 Verificar el estado final de la orden
SELECT
    id_orden,
    subtotal,
    propina,
    total,
    estado
FROM orden
WHERE id_orden = (SELECT id_orden FROM demo_ctx);

-- 6.4 Ver el reporte actualizado
SELECT *
FROM v_reporteventasturno
ORDER BY turno, metodo_pago;

-- ============================================================================
-- 7. DEMOSTRACION DE RESTRICCIONES (CHECK, UNIQUE, FK, NOT NULL)
-- Cada bloque intenta una operacion invalida y muestra el error controlado.
-- ============================================================================

-- 7.1 UNIQUE: no se puede repetir el nombre de una categoria
DO $$
BEGIN
    INSERT INTO categoria (nombre, descripcion, estado)
    VALUES ('Tacos', 'Categoria duplicada', 'Activa');

    RAISE NOTICE 'UNIQUE (FALLO): se permitio un nombre duplicado.';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'UNIQUE (BLOQUEADO CORRECTAMENTE): %', SQLERRM;
END;
$$;

-- 7.2 CHECK: el rol debe ser Cajero, Mesero o Taquero
DO $$
BEGIN
    INSERT INTO empleado (documento_identidad, nombres, apellidos, rol, turno)
    VALUES ('9999', 'Empleado', 'Invalido', 'Gerente', 'Matutino');

    RAISE NOTICE 'CHECK (FALLO): se permitio un rol invalido.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'CHECK (BLOQUEADO CORRECTAMENTE): %', SQLERRM;
END;
$$;

-- 7.3 FOREIGN KEY: la categoria debe existir
DO $$
BEGIN
    INSERT INTO producto
        (id_categoria, nombre, precio_unitario, stock_porciones, stock_minimo, estado)
    VALUES
        (999, 'Producto sin categoria', 10.00, 10, 1, 'Disponible');

    RAISE NOTICE 'FOREIGN KEY (FALLO): se permitio una categoria inexistente.';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'FOREIGN KEY (BLOQUEADO CORRECTAMENTE): %', SQLERRM;
END;
$$;

-- 7.4 NOT NULL: el nombre del producto es obligatorio
DO $$
BEGIN
    INSERT INTO producto
        (id_categoria, nombre, precio_unitario, stock_porciones, stock_minimo, estado)
    VALUES
        (1, NULL, 10.00, 10, 1, 'Disponible');

    RAISE NOTICE 'NOT NULL (FALLO): se permitio un nombre nulo.';
EXCEPTION
    WHEN not_null_violation THEN
        RAISE NOTICE 'NOT NULL (BLOQUEADO CORRECTAMENTE): %', SQLERRM;
END;
$$;

-- ============================================================================
-- 8. DEMOSTRACION DE ATOMICIDAD
-- Se intenta crear una orden y luego un detalle invalido. Si el detalle falla,
-- la orden tambien se revierte. La operacion es todo o nada.
-- ============================================================================
DO $$
DECLARE
    v_id_orden INTEGER;
    v_existe INTEGER;
BEGIN
    BEGIN
        INSERT INTO orden (id_empleado, numero_mesa, tipo_servicio)
        VALUES (2, 98, 'Para Llevar')
        RETURNING id_orden INTO v_id_orden;

        INSERT INTO detalle_orden
            (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea)
        VALUES
            (v_id_orden, 1, 9999, 15.00, 149985.00);
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'ATOMICIDAD: la operacion fallo y se revirtio: %', SQLERRM;
    END;

    SELECT COUNT(*) INTO v_existe
    FROM orden
    WHERE numero_mesa = 98;

    IF v_existe = 0 THEN
        RAISE NOTICE 'ATOMICIDAD VERIFICADA: la orden no quedo registrada.';
    ELSE
        RAISE NOTICE 'ATOMICIDAD NO VERIFICADA: la orden quedo registrada.';
    END IF;
END;
$$;

-- ============================================================================
-- 9. CONSULTAS DE CIERRE PARA LA SUSTENTACION
-- ============================================================================

-- 9.1 Resumen general de la base de datos
SELECT
    (SELECT COUNT(*) FROM categoria) AS categorias,
    (SELECT COUNT(*) FROM producto) AS productos,
    (SELECT COUNT(*) FROM empleado) AS empleados,
    (SELECT COUNT(*) FROM orden) AS ordenes,
    (SELECT COUNT(*) FROM detalle_orden) AS detalles,
    (SELECT COUNT(*) FROM pago) AS pagos;

-- 9.2 Estado de las ordenes
SELECT
    estado,
    COUNT(*) AS cantidad,
    SUM(total) AS total
FROM orden
GROUP BY estado
ORDER BY estado;

-- 9.3 Productos con stock bajo (por debajo o igual al minimo)
SELECT
    id_producto,
    nombre,
    stock_porciones,
    stock_minimo,
    estado
FROM producto
WHERE stock_porciones <= stock_minimo
ORDER BY stock_porciones ASC;

-- ============================================================================
-- FIN DE LAS CONSULTAS DE SUSTENTACION
-- ============================================================================
