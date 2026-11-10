-- ============================================================================
-- PROYECTO FINAL DE BASE DE DATOS RELACIONAL
-- SISTEMA DE PUNTO DE VENTA Y COCINA "EL PASTOR DORADO"
-- Motor: PostgreSQL 13+
-- Autor: DBA / Ingeniero de Bases de Datos Senior
-- Descripcion: Script unico, ejecutable de principio a fin, con DDL, vistas,
--              funciones, triggers, datos de prueba y bateria de pruebas.
-- ============================================================================

-- ============================================================================
-- 0. CONFIGURACION INICIAL Y LIMPIEZA DE OBJETOS
-- ============================================================================

BEGIN;

SET client_min_messages TO NOTICE;

-- Eliminacion ordenada para permitir reejecucion del script sin errores.
DROP VIEW IF EXISTS v_reporteventasturno CASCADE;
DROP VIEW IF EXISTS v_comandaspendientes CASCADE;
DROP VIEW IF EXISTS v_menudisponiblecocina CASCADE;

DROP TABLE IF EXISTS pago CASCADE;
DROP TABLE IF EXISTS detalle_orden CASCADE;
DROP TABLE IF EXISTS orden CASCADE;
DROP TABLE IF EXISTS empleado CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;

DROP FUNCTION IF EXISTS fn_actualizar_stock_verificar_disponibilidad() CASCADE;
DROP FUNCTION IF EXISTS fn_calcular_totales_orden() CASCADE;
DROP FUNCTION IF EXISTS fn_validar_cierre_pagos() CASCADE;

-- ============================================================================
-- 1. DDL - CREACION DEL ESQUEMA RELACIONAL (6 TABLAS EN 3FN)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1 CATEGORIA
-- Almacena las categorias del menu. El nombre es unico y el estado controla
-- si la categoria esta vigente para el negocio.
-- ----------------------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria SERIAL PRIMARY KEY,
    nombre       VARCHAR(60)  NOT NULL,
    descripcion  VARCHAR(200),
    estado       VARCHAR(10)  NOT NULL DEFAULT 'Activa',
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre),
    CONSTRAINT chk_categoria_estado CHECK (estado IN ('Activa', 'Inactiva'))
);

-- ----------------------------------------------------------------------------
-- 1.2 PRODUCTO
-- Cada producto pertenece a una categoria. Se controla precio, existencias,
-- stock minimo y disponibilidad para la venta.
-- ----------------------------------------------------------------------------
CREATE TABLE producto (
    id_producto     SERIAL PRIMARY KEY,
    id_categoria    INTEGER       NOT NULL,
    nombre          VARCHAR(80)   NOT NULL,
    precio_unitario NUMERIC(10,2) NOT NULL,
    stock_porciones INTEGER       NOT NULL DEFAULT 0,
    stock_minimo    INTEGER       NOT NULL DEFAULT 0,
    estado          VARCHAR(12)   NOT NULL DEFAULT 'Disponible',
    CONSTRAINT uq_producto_nombre UNIQUE (nombre),
    CONSTRAINT chk_producto_precio CHECK (precio_unitario > 0),
    CONSTRAINT chk_producto_stock CHECK (stock_porciones >= 0),
    CONSTRAINT chk_producto_stock_minimo CHECK (stock_minimo >= 0),
    CONSTRAINT chk_producto_estado CHECK (estado IN ('Disponible', 'Agotado')),
    CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria)
        REFERENCES categoria (id_categoria)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 1.3 EMPLEADO
-- Personal del restaurante. El documento de identidad es unico y se validan
-- los roles y turnos permitidos.
-- ----------------------------------------------------------------------------
CREATE TABLE empleado (
    id_empleado          SERIAL PRIMARY KEY,
    documento_identidad  VARCHAR(20) NOT NULL,
    nombres              VARCHAR(60) NOT NULL,
    apellidos            VARCHAR(60) NOT NULL,
    rol                  VARCHAR(10) NOT NULL,
    turno                VARCHAR(12) NOT NULL,
    CONSTRAINT uq_empleado_documento UNIQUE (documento_identidad),
    CONSTRAINT chk_empleado_rol CHECK (rol IN ('Cajero', 'Mesero', 'Taquero')),
    CONSTRAINT chk_empleado_turno CHECK (turno IN ('Matutino', 'Vespertino', 'Nocturno'))
);

-- ----------------------------------------------------------------------------
-- 1.4 ORDEN
-- Cabecera de la orden. Guarda al empleado responsable, mesa, tipo de servicio,
-- fechas, importes y estado del ciclo de vida de la orden.
-- ----------------------------------------------------------------------------
CREATE TABLE orden (
    id_orden       SERIAL PRIMARY KEY,
    id_empleado    INTEGER       NOT NULL,
    numero_mesa    INTEGER       NOT NULL,
    tipo_servicio  VARCHAR(12)   NOT NULL,
    fecha_hora     TIMESTAMP     NOT NULL DEFAULT NOW(),
    subtotal       NUMERIC(12,2) NOT NULL DEFAULT 0,
    propina        NUMERIC(12,2) NOT NULL DEFAULT 0,
    total          NUMERIC(12,2) NOT NULL DEFAULT 0,
    estado         VARCHAR(15)   NOT NULL DEFAULT 'Abierta',
    CONSTRAINT chk_orden_mesa CHECK (numero_mesa > 0),
    CONSTRAINT chk_orden_tipo_servicio CHECK (tipo_servicio IN ('Comedor', 'Para Llevar')),
    CONSTRAINT chk_orden_subtotal CHECK (subtotal >= 0),
    CONSTRAINT chk_orden_propina CHECK (propina >= 0),
    CONSTRAINT chk_orden_total CHECK (total >= 0),
    CONSTRAINT chk_orden_estado CHECK (estado IN ('Abierta', 'En Preparacion', 'Cobrada', 'Cancelada')),
    CONSTRAINT fk_orden_empleado FOREIGN KEY (id_empleado)
        REFERENCES empleado (id_empleado)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 1.5 DETALLE_ORDEN
-- Lineas de producto solicitadas en cada orden. Conserva el precio historico
-- del momento de la venta y las notas de preparacion para cocina.
-- ----------------------------------------------------------------------------
CREATE TABLE detalle_orden (
    id_detalle                SERIAL PRIMARY KEY,
    id_orden                  INTEGER       NOT NULL,
    id_producto               INTEGER       NOT NULL,
    cantidad                  INTEGER       NOT NULL,
    precio_unitario_historico NUMERIC(10,2) NOT NULL,
    importe_linea             NUMERIC(12,2) NOT NULL,
    notas_preparacion         VARCHAR(200),
    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_precio CHECK (precio_unitario_historico > 0),
    CONSTRAINT chk_detalle_importe CHECK (importe_linea > 0),
    CONSTRAINT fk_detalle_orden FOREIGN KEY (id_orden)
        REFERENCES orden (id_orden)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 1.6 PAGO
-- Pagos aplicados a una orden. Una orden puede tener uno o varios pagos con
-- distintos metodos. Se registra el cambio entregado y la referencia externa.
-- ----------------------------------------------------------------------------
CREATE TABLE pago (
    id_pago                 SERIAL PRIMARY KEY,
    id_orden                INTEGER       NOT NULL,
    metodo_pago             VARCHAR(15)   NOT NULL,
    monto_pagado            NUMERIC(12,2) NOT NULL,
    cambio                  NUMERIC(12,2) NOT NULL DEFAULT 0,
    fecha_hora_pago         TIMESTAMP     NOT NULL DEFAULT NOW(),
    referencia_transaccion  VARCHAR(60),
    CONSTRAINT chk_pago_metodo CHECK (metodo_pago IN ('Efectivo', 'Tarjeta', 'Transferencia')),
    CONSTRAINT chk_pago_monto CHECK (monto_pagado > 0),
    CONSTRAINT chk_pago_cambio CHECK (cambio >= 0),
    CONSTRAINT fk_pago_orden FOREIGN KEY (id_orden)
        REFERENCES orden (id_orden)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

-- ============================================================================
-- 2. INDICES DE APOYO
-- Se crean indices sobre claves foraneas y columnas de filtro frecuente para
-- mejorar el rendimiento de las vistas y de las operaciones del punto de venta.
-- ============================================================================
CREATE INDEX idx_pastor_producto_categoria ON producto (id_categoria);
CREATE INDEX idx_pastor_orden_empleado ON orden (id_empleado);
CREATE INDEX idx_pastor_orden_estado ON orden (estado);
CREATE INDEX idx_pastor_detalle_orden ON detalle_orden (id_orden);
CREATE INDEX idx_pastor_detalle_producto ON detalle_orden (id_producto);
CREATE INDEX idx_pastor_pago_orden ON pago (id_orden);
CREATE INDEX idx_pastor_pago_fecha ON pago (fecha_hora_pago);

-- ============================================================================
-- 3. VISTAS DE NEGOCIO
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 V_MenuDisponibleCocina
-- Productos vendibles en este momento: estado 'Disponible' y stock por encima
-- del minimo configurado.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_menudisponiblecocina AS
SELECT
    p.id_producto,
    p.nombre,
    c.nombre AS categoria,
    p.stock_porciones
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE p.estado = 'Disponible'
  AND p.stock_porciones > p.stock_minimo;

-- ----------------------------------------------------------------------------
-- 3.2 V_ComandasPendientes
-- Ordenes activas con el tiempo transcurrido en minutos desde su apertura,
-- el nombre completo del mesero y el resumen de productos con sus notas.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_comandaspendientes AS
SELECT
    o.id_orden,
    o.numero_mesa,
    o.estado,
    ROUND(EXTRACT(EPOCH FROM (NOW() - o.fecha_hora)) / 60, 2) AS minutos_transcurridos,
    e.nombres || ' ' || e.apellidos AS mesero,
    COALESCE(
        STRING_AGG(
            p.nombre || ' x' || d.cantidad ||
            CASE
                WHEN d.notas_preparacion IS NOT NULL
                THEN ' [' || d.notas_preparacion || ']'
                ELSE ''
            END,
            ', ' ORDER BY d.id_detalle
        ),
        'Sin productos'
    ) AS productos
FROM orden o
JOIN empleado e ON e.id_empleado = o.id_empleado
LEFT JOIN detalle_orden d ON d.id_orden = o.id_orden
LEFT JOIN producto p ON p.id_producto = d.id_producto
WHERE o.estado IN ('Abierta', 'En Preparacion')
GROUP BY o.id_orden, o.numero_mesa, o.estado, o.fecha_hora, e.nombres, e.apellidos;

-- ----------------------------------------------------------------------------
-- 3.3 V_ReporteVentasTurno
-- Consolidado del dia actual por turno del empleado y metodo de pago.
-- La propina se distribuye proporcionalmente entre los metodos de pago de la
-- orden para evitar duplicarla cuando una orden tiene varios pagos.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_reporteventasturno AS
WITH pagos_del_dia AS (
    SELECT
        id_orden,
        metodo_pago,
        monto_pagado,
        cambio
    FROM pago
    WHERE fecha_hora_pago::date = CURRENT_DATE
),
pagos_agrupados AS (
    SELECT
        id_orden,
        metodo_pago,
        SUM(monto_pagado) AS monto_pagado,
        SUM(cambio) AS cambio
    FROM pagos_del_dia
    GROUP BY id_orden, metodo_pago
),
totales_pago_orden AS (
    SELECT
        id_orden,
        SUM(monto_pagado) AS total_pagado
    FROM pagos_del_dia
    GROUP BY id_orden
),
base AS (
    SELECT
        o.id_orden,
        o.id_empleado,
        o.propina,
        pa.metodo_pago,
        pa.monto_pagado,
        pa.cambio,
        tpo.total_pagado
    FROM orden o
    JOIN pagos_agrupados pa ON pa.id_orden = o.id_orden
    JOIN totales_pago_orden tpo ON tpo.id_orden = o.id_orden
    WHERE o.estado = 'Cobrada'
)
SELECT
    e.turno,
    b.metodo_pago,
    SUM(b.monto_pagado - b.cambio) AS total_recaudado,
    ROUND(SUM(
        CASE
            WHEN b.total_pagado > 0
            THEN b.propina * (b.monto_pagado / b.total_pagado)
            ELSE 0
        END
    ), 2) AS total_propinas,
    COUNT(DISTINCT b.id_orden) AS numero_ordenes
FROM base b
JOIN empleado e ON e.id_empleado = b.id_empleado
GROUP BY e.turno, b.metodo_pago
ORDER BY e.turno, b.metodo_pago;

-- ============================================================================
-- 4. LOGICA ACTIVA: FUNCIONES Y TRIGGERS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 TR_ActualizarStockYVerificarDisponibilidad (BEFORE INSERT en DETALLE_ORDEN)
-- Verifica que el producto exista, este 'Disponible' y tenga stock suficiente.
-- Si todo es correcto, descuenta las porciones y marca 'Agotado' si llega a 0.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_actualizar_stock_verificar_disponibilidad()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock  INTEGER;
    v_estado VARCHAR(12);
    v_nombre VARCHAR(80);
BEGIN
    SELECT stock_porciones, estado, nombre
      INTO v_stock, v_estado, v_nombre
      FROM producto
     WHERE id_producto = NEW.id_producto
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto con id % no existe.', NEW.id_producto;
    END IF;

    IF v_estado <> 'Disponible' THEN
        RAISE EXCEPTION 'El producto "%" esta en estado "%" y no puede venderse.',
            v_nombre, v_estado;
    END IF;

    IF v_stock < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para "%": disponible %, solicitado %.',
            v_nombre, v_stock, NEW.cantidad;
    END IF;

    UPDATE producto
       SET stock_porciones = stock_porciones - NEW.cantidad,
           estado = CASE
                        WHEN stock_porciones - NEW.cantidad = 0 THEN 'Agotado'
                        ELSE estado
                    END
     WHERE id_producto = NEW.id_producto;

    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4.2 TR_CalcularTotalesOrden (AFTER INSERT OR UPDATE OR DELETE en DETALLE_ORDEN)
-- Recalcula el subtotal de la orden a partir de la suma de importe_linea y
-- actualiza el total general como subtotal + propina.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_calcular_totales_orden()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_orden INTEGER;
    v_subtotal NUMERIC(12,2);
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id_orden := OLD.id_orden;
    ELSE
        v_id_orden := NEW.id_orden;
    END IF;

    SELECT COALESCE(SUM(importe_linea), 0)
      INTO v_subtotal
      FROM detalle_orden
     WHERE id_orden = v_id_orden;

    UPDATE orden
       SET subtotal = v_subtotal,
           total = v_subtotal + propina
     WHERE id_orden = v_id_orden;

    -- Si en una actualizacion cambia la orden destino, se recalcula tambien
    -- la orden de origen para mantener la consistencia de ambos totales.
    IF TG_OP = 'UPDATE' THEN
        IF OLD.id_orden <> NEW.id_orden THEN
            SELECT COALESCE(SUM(importe_linea), 0)
              INTO v_subtotal
              FROM detalle_orden
             WHERE id_orden = OLD.id_orden;

            UPDATE orden
               SET subtotal = v_subtotal,
                   total = v_subtotal + propina
             WHERE id_orden = OLD.id_orden;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4.3 TR_ValidarCierreYPagos (BEFORE UPDATE en ORDEN)
-- Impide pasar una orden a 'Cobrada' si no tiene pagos registrados o si la
-- suma de los pagos no cubre el total de la orden.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_cierre_pagos()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_num_pagos    BIGINT;
    v_total_pagado NUMERIC(12,2);
BEGIN
    IF NEW.estado = 'Cobrada' AND OLD.estado IS DISTINCT FROM 'Cobrada' THEN
        SELECT COUNT(*), COALESCE(SUM(monto_pagado), 0)
          INTO v_num_pagos, v_total_pagado
          FROM pago
         WHERE id_orden = NEW.id_orden;

        IF v_num_pagos = 0 THEN
            RAISE EXCEPTION 'No se puede cobrar la orden %: no existen pagos registrados.',
                NEW.id_orden;
        END IF;

        IF v_total_pagado < NEW.total THEN
            RAISE EXCEPTION 'No se puede cobrar la orden %: total pagado % es menor al total de la orden %.',
                NEW.id_orden, v_total_pagado, NEW.total;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4.4 Creacion de los disparadores
-- ----------------------------------------------------------------------------
CREATE TRIGGER "TR_ActualizarStockYVerificarDisponibilidad"
BEFORE INSERT ON detalle_orden
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_stock_verificar_disponibilidad();

CREATE TRIGGER "TR_CalcularTotalesOrden"
AFTER INSERT OR UPDATE OR DELETE ON detalle_orden
FOR EACH ROW
EXECUTE FUNCTION fn_calcular_totales_orden();

CREATE TRIGGER "TR_ValidarCierreYPagos"
BEFORE UPDATE ON orden
FOR EACH ROW
EXECUTE FUNCTION fn_validar_cierre_pagos();

-- ============================================================================
-- 5. DATOS DE PRUEBA (DML) - MINIMO 10 REGISTROS POR TABLA
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 5.1 CATEGORIA (10 registros)
-- ----------------------------------------------------------------------------
INSERT INTO categoria (nombre, descripcion, estado) VALUES
('Tacos', 'Tacos al pastor, suadero, campechano y especialidades', 'Activa'),
('Tortas', 'Tortas preparadas con diferentes guisos', 'Activa'),
('Quesadillas', 'Quesadillas con queso y guisos', 'Activa'),
('Bebidas', 'Aguas frescas, refrescos y bebidas embotelladas', 'Activa'),
('Postres', 'Postres caseros y flanes', 'Activa'),
('Especialidades', 'Platillos especiales de la casa', 'Activa'),
('Desayunos', 'Huevos, chilaquiles y desayunos mexicanos', 'Activa'),
('Salsas y Extras', 'Salsas, guacamole, cebolla y limones', 'Activa'),
('Combos', 'Combinaciones de tacos, bebidas y guarniciones', 'Activa'),
('Ensaladas', 'Ensaladas frescas y saludables', 'Inactiva');

-- ----------------------------------------------------------------------------
-- 5.2 PRODUCTO (14 registros, incluye un producto agotado para pruebas)
-- ----------------------------------------------------------------------------
INSERT INTO producto (id_categoria, nombre, precio_unitario, stock_porciones, stock_minimo, estado) VALUES
(1, 'Taco al Pastor', 15.00, 200, 20, 'Disponible'),
(1, 'Taco de Suadero', 16.00, 150, 20, 'Disponible'),
(1, 'Taco Campechano', 18.00, 120, 15, 'Disponible'),
(2, 'Torta al Pastor', 45.00, 80, 10, 'Disponible'),
(2, 'Torta de Milanesa', 48.00, 60, 10, 'Disponible'),
(3, 'Quesadilla de Queso', 30.00, 100, 15, 'Disponible'),
(3, 'Quesadilla al Pastor', 38.00, 90, 15, 'Disponible'),
(4, 'Agua de Horchata', 25.00, 120, 20, 'Disponible'),
(4, 'Agua de Jamaica', 25.00, 110, 20, 'Disponible'),
(5, 'Flan Napolitano', 28.00, 40, 5, 'Disponible'),
(6, 'Volcan de Pastor', 40.00, 70, 10, 'Disponible'),
(4, 'Agua Embotellada', 15.00, 200, 30, 'Disponible'),
(1, 'Taco de Cabeza', 20.00, 0, 10, 'Agotado'),
(6, 'Sincronizada Especial', 35.00, 8, 5, 'Disponible');

-- ----------------------------------------------------------------------------
-- 5.3 EMPLEADO (10 registros)
-- ----------------------------------------------------------------------------
INSERT INTO empleado (documento_identidad, nombres, apellidos, rol, turno) VALUES
('1001', 'Juan', 'Perez', 'Cajero', 'Matutino'),
('1002', 'Maria', 'Lopez', 'Mesero', 'Matutino'),
('1003', 'Pedro', 'Ramirez', 'Taquero', 'Matutino'),
('1004', 'Ana', 'Torres', 'Cajero', 'Vespertino'),
('1005', 'Luis', 'Gomez', 'Mesero', 'Vespertino'),
('1006', 'Carlos', 'Diaz', 'Taquero', 'Vespertino'),
('1007', 'Sofia', 'Herrera', 'Cajero', 'Nocturno'),
('1008', 'Jorge', 'Castro', 'Mesero', 'Nocturno'),
('1009', 'Elena', 'Rios', 'Taquero', 'Nocturno'),
('1010', 'Miguel', 'Vargas', 'Mesero', 'Matutino');

-- ----------------------------------------------------------------------------
-- 5.4 ORDEN (10 registros)
-- Las ordenes que se cobraran se insertan inicialmente como 'Abierta' para
-- que el trigger de validacion de pagos se ejecute al cambiar a 'Cobrada'.
-- La orden 10 se deja sin detalles para la bateria de pruebas.
-- ----------------------------------------------------------------------------
INSERT INTO orden (id_empleado, numero_mesa, tipo_servicio, fecha_hora, subtotal, propina, total, estado) VALUES
(2, 1, 'Comedor', CURRENT_DATE + TIME '09:00', 0, 10.00, 0, 'Abierta'),
(2, 2, 'Comedor', CURRENT_DATE + TIME '10:30', 0, 5.00, 0, 'Abierta'),
(5, 3, 'Comedor', CURRENT_DATE + TIME '15:00', 0, 15.00, 0, 'Abierta'),
(5, 4, 'Para Llevar', CURRENT_DATE + TIME '16:30', 0, 12.00, 0, 'Abierta'),
(8, 5, 'Comedor', NOW() - INTERVAL '25 minutes', 0, 0, 0, 'En Preparacion'),
(10, 6, 'Para Llevar', NOW() - INTERVAL '10 minutes', 0, 0, 0, 'Abierta'),
(5, 7, 'Comedor', CURRENT_DATE + TIME '17:15', 0, 4.00, 0, 'Abierta'),
(5, 8, 'Para Llevar', NOW() - INTERVAL '3 hours', 0, 0, 0, 'Cancelada'),
(8, 9, 'Comedor', NOW() - INTERVAL '40 minutes', 0, 0, 0, 'En Preparacion'),
(2, 10, 'Comedor', NOW() - INTERVAL '5 minutes', 0, 0, 0, 'Abierta');

-- ----------------------------------------------------------------------------
-- 5.5 DETALLE_ORDEN (11 registros)
-- Al insertar estas lineas se ejecutan los triggers de stock y de totales.
-- ----------------------------------------------------------------------------
INSERT INTO detalle_orden (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea, notas_preparacion) VALUES
(1, 1, 2, 15.00, 30.00, 'Sin cebolla'),
(1, 8, 1, 25.00, 25.00, 'Con hielo'),
(2, 4, 1, 45.00, 45.00, 'Con todo'),
(3, 6, 2, 30.00, 60.00, 'Una sin salsa'),
(3, 9, 1, 25.00, 25.00, 'Sin azucar'),
(4, 11, 1, 40.00, 40.00, 'Termino medio'),
(4, 10, 1, 28.00, 28.00, 'Para llevar'),
(5, 2, 3, 16.00, 48.00, 'Con cilantro y cebolla'),
(6, 7, 1, 38.00, 38.00, 'Sin picante'),
(7, 3, 2, 18.00, 36.00, 'Bien dorados'),
(9, 12, 2, 15.00, 30.00, 'Bien frias');

-- ----------------------------------------------------------------------------
-- 5.6 PAGO (10 registros)
-- Pagos de las ordenes 1, 2, 3, 4 y 7. La suma de pagos de cada orden cubre
-- exactamente su total (subtotal + propina).
-- ----------------------------------------------------------------------------
INSERT INTO pago (id_orden, metodo_pago, monto_pagado, cambio, fecha_hora_pago, referencia_transaccion) VALUES
(1, 'Efectivo', 40.00, 0.00, NOW(), 'PAGO-001-A'),
(1, 'Tarjeta', 25.00, 0.00, NOW(), 'PAGO-001-B'),
(2, 'Efectivo', 30.00, 0.00, NOW(), 'PAGO-002-A'),
(2, 'Tarjeta', 20.00, 0.00, NOW(), 'PAGO-002-B'),
(3, 'Efectivo', 60.00, 0.00, NOW(), 'PAGO-003-A'),
(3, 'Tarjeta', 40.00, 0.00, NOW(), 'PAGO-003-B'),
(4, 'Tarjeta', 80.00, 0.00, NOW(), 'PAGO-004-A'),
(7, 'Efectivo', 20.00, 0.00, NOW(), 'PAGO-007-A'),
(7, 'Tarjeta', 10.00, 0.00, NOW(), 'PAGO-007-B'),
(7, 'Transferencia', 10.00, 0.00, NOW(), 'PAGO-007-C');

-- ----------------------------------------------------------------------------
-- 5.7 CIERRE DE ORDENES PAGADAS
-- El trigger TR_ValidarCierreYPagos verifica que cada orden tenga pagos
-- suficientes antes de permitir el cambio a 'Cobrada'.
-- ----------------------------------------------------------------------------
UPDATE orden
   SET estado = 'Cobrada'
 WHERE id_orden IN (1, 2, 3, 4, 7);

-- ============================================================================
-- 6. BATERIA DE PRUEBAS DE TRIGGERS
-- Las pruebas de fallo se ejecutan dentro de bloques DO con manejo de
-- excepciones para que el script continue y muestre el mensaje controlado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PRUEBA 1 (EXITO): Insertar detalles en la orden 10, verificar el descuento
-- de stock y la actualizacion automatica de subtotal y total.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_stock_antes   INTEGER;
    v_stock_despues INTEGER;
    v_subtotal      NUMERIC(12,2);
    v_total         NUMERIC(12,2);
BEGIN
    SELECT stock_porciones
      INTO v_stock_antes
      FROM producto
     WHERE id_producto = 1;

    INSERT INTO detalle_orden
        (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea, notas_preparacion)
    VALUES
        (10, 1, 2, 15.00, 30.00, 'Sin cebolla'),
        (10, 8, 1, 25.00, 25.00, 'Con hielo');

    SELECT stock_porciones
      INTO v_stock_despues
      FROM producto
     WHERE id_producto = 1;

    SELECT subtotal, total
      INTO v_subtotal, v_total
      FROM orden
     WHERE id_orden = 10;

    RAISE NOTICE 'PRUEBA 1 (EXITO): stock producto 1 antes=%, despues=%; orden 10 subtotal=%, total=%.',
        v_stock_antes, v_stock_despues, v_subtotal, v_total;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 2A (FALLO INTENCIONAL): Intentar vender una cantidad mayor al stock
-- disponible del producto 1. El trigger debe bloquear la insercion.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO detalle_orden
        (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea)
    VALUES
        (10, 1, 9999, 15.00, 149985.00);

    RAISE NOTICE 'PRUEBA 2A (FALLO): la insercion no fue bloqueada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA 2A (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 2B (FALLO INTENCIONAL): Intentar vender el producto 13, que esta en
-- estado 'Agotado'. El trigger debe bloquear la insercion.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO detalle_orden
        (id_orden, id_producto, cantidad, precio_unitario_historico, importe_linea)
    VALUES
        (10, 13, 1, 20.00, 20.00);

    RAISE NOTICE 'PRUEBA 2B (FALLO): la insercion no fue bloqueada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA 2B (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 3 (FALLO INTENCIONAL): Intentar cobrar la orden 10 sin pagos.
-- El trigger TR_ValidarCierreYPagos debe cancelar la actualizacion.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    UPDATE orden
       SET estado = 'Cobrada'
     WHERE id_orden = 10;

    RAISE NOTICE 'PRUEBA 3 (FALLO): la orden fue cobrada sin pagos.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'PRUEBA 3 (FALLO CONTROLADO): %', SQLERRM;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 4 (EXITO): Registrar un pago suficiente para la orden 10 y cambiar
-- su estado a 'Cobrada'. La operacion debe completarse correctamente.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_total  NUMERIC(12,2);
    v_pagado NUMERIC(12,2);
    v_estado VARCHAR(15);
BEGIN
    SELECT total
      INTO v_total
      FROM orden
     WHERE id_orden = 10;

    INSERT INTO pago
        (id_orden, metodo_pago, monto_pagado, cambio, fecha_hora_pago, referencia_transaccion)
    VALUES
        (10, 'Efectivo', 60.00, 5.00, NOW(), 'TEST-004');

    SELECT COALESCE(SUM(monto_pagado), 0)
      INTO v_pagado
      FROM pago
     WHERE id_orden = 10;

    UPDATE orden
       SET estado = 'Cobrada'
     WHERE id_orden = 10;

    SELECT estado
      INTO v_estado
      FROM orden
     WHERE id_orden = 10;

    RAISE NOTICE 'PRUEBA 4 (EXITO): orden 10 total=%, pagado=%, estado=%.',
        v_total, v_pagado, v_estado;
END;
$$;

-- ============================================================================
-- 7. CONSULTAS DE VERIFICACION FINAL
-- ============================================================================

-- Menu disponible para cocina
SELECT *
FROM v_menudisponiblecocina
ORDER BY id_producto;

-- Comandas pendientes con tiempo transcurrido y resumen de productos
SELECT *
FROM v_comandaspendientes
ORDER BY id_orden;

-- Reporte de ventas del dia por turno y metodo de pago
SELECT *
FROM v_reporteventasturno
ORDER BY turno, metodo_pago;

-- Resumen de ordenes y totales recalculados por los triggers
SELECT
    id_orden,
    numero_mesa,
    estado,
    subtotal,
    propina,
    total
FROM orden
ORDER BY id_orden;

COMMIT;

-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
