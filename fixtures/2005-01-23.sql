DROP DATABASE IF EXISTS snapshot;
CREATE DATABASE snapshot CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE snapshot;

-- Schema iteration: city is dropped. id=103 is also absent from this full snapshot.
CREATE TABLE table1 (
  id BIGINT NOT NULL,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_table1_email (email)
) ENGINE=InnoDB;

INSERT INTO table1 (id, name, email) VALUES
  (101, 'Amy', 'amy@example.test'),
  (102, 'Bobby', NULL);
