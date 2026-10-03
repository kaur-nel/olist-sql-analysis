-- Foreign keys. If the data violates one, the loader logs a warning and continues.
ALTER TABLE orders         ADD CONSTRAINT fk_orders_customer  FOREIGN KEY (customer_id) REFERENCES customers(customer_id);
ALTER TABLE order_items    ADD CONSTRAINT fk_items_order      FOREIGN KEY (order_id)    REFERENCES orders(order_id);
ALTER TABLE order_items    ADD CONSTRAINT fk_items_product    FOREIGN KEY (product_id)  REFERENCES products(product_id);
ALTER TABLE order_items    ADD CONSTRAINT fk_items_seller     FOREIGN KEY (seller_id)   REFERENCES sellers(seller_id);
ALTER TABLE order_payments ADD CONSTRAINT fk_payments_order   FOREIGN KEY (order_id)    REFERENCES orders(order_id);
ALTER TABLE order_reviews  ADD CONSTRAINT fk_reviews_order    FOREIGN KEY (order_id)    REFERENCES orders(order_id);

-- Indexes on columns we will join, filter, or group by.
CREATE INDEX IF NOT EXISTS idx_orders_customer    ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status      ON orders(order_status);
CREATE INDEX IF NOT EXISTS idx_orders_purchase_ts ON orders(order_purchase_timestamp);
CREATE INDEX IF NOT EXISTS idx_items_product      ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_items_seller       ON order_items(seller_id);
CREATE INDEX IF NOT EXISTS idx_reviews_order      ON order_reviews(order_id);
CREATE INDEX IF NOT EXISTS idx_customers_unique   ON customers(customer_unique_id);
CREATE INDEX IF NOT EXISTS idx_products_category  ON products(product_category_name);
CREATE INDEX IF NOT EXISTS idx_geo_zip            ON geolocation(geolocation_zip_code_prefix);

ANALYZE;