DROP DATABASE IF EXISTS snapshot;
CREATE DATABASE snapshot CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE snapshot;

-- Schema iteration: email is added.
CREATE TABLE table1 (
  id BIGINT NOT NULL,
  name VARCHAR(100) NOT NULL,
  city VARCHAR(100) NULL,
  email VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_table1_email (email)
) ENGINE=InnoDB;

INSERT INTO table1 (id, name, city, email) VALUES
  (101, 'Amy', 'Taichung', 'amy@example.test'),
  (102, 'Bob', 'Tainan', NULL),
  (103, 'Carol', 'Kaohsiung', 'carol@example.test');
