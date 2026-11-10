-- ============================================================================
-- BATERIA DE PRUEBAS DE TRIGGERS
-- Sistema de Punto de Venta y Cocina "El Pastor Dorado"
-- Motor: PostgreSQL 13+
--
-- REQUISITO: haber ejecutado previamente El_Pastor_Dorado.sql
-- Esta bateria crea una orden temporal, ejecuta las pruebas y termina con
-- ROLLBACK para no dejar datos de prueba en la base de datos.
-- Los mensajes RAISE NOTICE se ven en la pestana "Messages" de pgAdmin.
-- ============================================================================

BEGIN;

-- Contexto de la prueba: guarda el ID de la orden temporal
CREATE TEMP TABLE test_ctx (
    id_orden INTEGER
);

-- Crear una orden de prueba con mesa 99 para no interferir con los datos reales
WITH nueva AS (
    INSERT INTO orden (id_empleado, numero_mesa, tipo_servicio, propina)
    VALUES (2, 99, 'Comedor', 0.00)
    RETURNING id_orden
)
INSERT INTO test_ctx (id_orden)
SELECT id_orden FROM nueva;

-- ============================================================================
-- PRUEBA 1 (EXITO)
-- Insertar un detalle valido y verificar:
--   - Que el stock del producto disminuya.
--   - Que el subtotal y el total de la orden se recalculen automaticamente.
-- ============================================================================
DO $$
DECLARE
    v_id_orden      INTEGER;
    v_stock_antes   INTEGER;
    v_stock_despues INTEGER;
    v_subtotal      NUMERIC(12,2);
    v_total         NUMERIC(12,2);
BEGIN
    SELECT id_orden INTO v_id_orden FROM test_ctx;

    SELECT stock_porciones
      INTO v_stock_antes
      FROM producto
     WHERE id_producto = 1;

    INSERT INTO detalle_orden
        (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea, notas_preparacion)
    VALUES
        (v_id_orden, 1, 2, 15.00, 30.00, 'Sin cebolla');

    SELECT stock_porciones
      INTO v_stock_despues
      FROM producto
     WHERE id_producto = 1;

    SELECT subtotal, total
      INTO v_subtotal, v_total
      FROM orden
     WHERE id_orden = v_id_orden;

    RAISE NOTICE 'PRUEBA 1 (EXITO): stock antes=%, despues=%; subtotal=%, total=%.',
        v_stock_antes, v_stock_despues, v_subtotal, v_total;
END;
$$;

-- ============================================================================
-- PRUEBA 2A (FALLO INTENCIONAL)
-- Intentar vender una cantidad mayor al stock disponible.
-- El trigger debe lanzar una excepcion y bloquear la insercion.
-- ============================================================================
DO $$
DECLARE
    v_id_orden INTEGER;
BEGIN
    SELECT id_orden INTO v_id_orden FROM test_ctx;

    INSERT INTO detalle_orden
        (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea)
    VALUES
        (v_id_orden, 1, 9999, 15.00, 149985.00);

    RAISE NOTICE 'PRUEBA 2A (FALLO): la insercion no fue bloqueada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA 2A (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- ============================================================================
-- PRUEBA 2B (FALLO INTENCIONAL)
-- Intentar vender un producto que esta en estado 'Agotado'.
-- El trigger debe lanzar una excepcion y bloquear la insercion.
-- ============================================================================
DO $$
DECLARE
    v_id_orden INTEGER;
BEGIN
    SELECT id_orden INTO v_id_orden FROM test_ctx;

    INSERT INTO detalle_orden
        (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea)
    VALUES
        (v_id_orden, 13, 1, 20.00, 20.00);

    RAISE NOTICE 'PRUEBA 2B (FALLO): la insercion no fue bloqueada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA 2B (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- ============================================================================
-- PRUEBA 3 (FALLO INTENCIONAL)
-- Intentar cambiar la orden a 'Cobrada' sin registrar pagos.
-- El trigger debe cancelar la actualizacion y mostrar un error explicativo.
-- ============================================================================
DO $$
DECLARE
    v_id_orden INTEGER;
BEGIN
    SELECT id_orden INTO v_id_orden FROM test_ctx;

    UPDATE orden
       SET estado = 'Cobrada'
     WHERE id_orden = v_id_orden;

    RAISE NOTICE 'PRUEBA 3 (FALLO): la orden fue cobrada sin pagos.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA 3 (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- ============================================================================
-- PRUEBA 4 (EXITO)
-- Registrar el pago completo y cambiar la orden a 'Cobrada'.
-- La operacion debe completarse correctamente.
-- ============================================================================
DO $$
DECLARE
    v_id_orden INTEGER;
    v_total    NUMERIC(12,2);
    v_pagado   NUMERIC(12,2);
    v_estado   VARCHAR(15);
BEGIN
    SELECT id_orden INTO v_id_orden FROM test_ctx;

    SELECT total INTO v_total FROM orden WHERE id_orden = v_id_orden;

    INSERT INTO pago
        (id_orden, metodo_pago, monto_pagado, cambio, fecha_hora_pago, referencia_transaccion)
    VALUES
        (v_id_orden, 'Efectivo', v_total, 0.00, NOW(), 'TEST-BATERIA-004');

    SELECT COALESCE(SUM(monto_pagado), 0)
      INTO v_pagado
      FROM pago
     WHERE id_orden = v_id_orden;

    UPDATE orden
       SET estado = 'Cobrada'
     WHERE id_orden = v_id_orden;

    SELECT estado INTO v_estado FROM orden WHERE id_orden = v_id_orden;

    RAISE NOTICE 'PRUEBA 4 (EXITO): total=%, pagado=%, estado=%.',
        v_total, v_pagado, v_estado;
END;
$$;

-- ============================================================================
-- REVERSION DE LA BATERIA
-- Se revierten todos los cambios de la prueba para dejar la base intacta.
-- ============================================================================
ROLLBACK;

-- ============================================================================
-- FIN DE LA BATERIA DE PRUEBAS
-- ============================================================================
