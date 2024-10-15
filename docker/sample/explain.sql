EXPLAIN SELECT * FROM card WHERE id = 1;
EXPLAIN SELECT * FROM card WHERE number = 13;
EXPLAIN SELECT * FROM card WHERE type = 'heart';
EXPLAIN SELECT * FROM card WHERE type = 'heart' AND number = 13;
EXPLAIN SELECT * FROM card WHERE number = 13 AND type = 'heart';