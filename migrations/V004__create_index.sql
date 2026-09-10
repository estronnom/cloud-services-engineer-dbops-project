CREATE INDEX idx_orders_status_date ON orders (status, date_created);
CREATE INDEX idx_order_product_order_id_qty ON order_product(order_id) INCLUDE (quantity);
