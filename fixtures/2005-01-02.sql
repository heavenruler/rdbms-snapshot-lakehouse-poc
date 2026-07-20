DROP DATABASE IF EXISTS snapshot;
CREATE DATABASE snapshot CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE snapshot;

CREATE TABLE table1 (
  id BIGINT NOT NULL,
  name VARCHAR(100) NOT NULL,
  city VARCHAR(100) NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

INSERT INTO table1 (id, name, city) VALUES
  (101, 'Amy', 'Taipei'),
  (102, 'Bob', 'Tainan');
