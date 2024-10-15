-- postgresql
-- trumpを10万件作る
INSERT INTO trump SELECT FROM generate_series(1, 100000);

-- trumpと紐づいたcardのデータを作る
WITH card_set AS (SELECT 'heart' AS type, generate_series(1, 13) AS number
                  FROM generate_series(1, 13)
                  UNION
                  SELECT 'spade' AS type, generate_series(1, 13) AS number
                  FROM generate_series(1, 13)
                  UNION
                  SELECT 'club' AS type, generate_series(1, 13) AS number
                  FROM generate_series(1, 13)
                  UNION
                  SELECT 'diamond' AS type, generate_series(1, 13) AS number
                  FROM generate_series(1, 13))
INSERT
INTO card (trump_id, type, number)
SELECT trump.id, type, number
FROM trump
         LEFT JOIN card_set on 1 = 1
ORDER BY trump.id, card_set.type, card_set.number;

SELECT count(*) FROM card;

-- mysql
-- trumpはPostgreSQLからCSVで取り込む
-- trumpをベースにcardを作る

INSERT INTO card  (trump_id, type, number)
WITH RECURSIVE sequence AS (
SELECT trump.id AS num
       FROM trump ORDER BY id limit 13
),card_set AS (
    SELECT 'heart' AS type, num AS number FROM sequence
    UNION SELECT 'spade' AS type, num AS number FROM sequence
    UNION SELECT 'club' AS type, num AS number FROM sequence
    UNION SELECT 'diamond' AS type, num AS number FROM sequence
)

SELECT trump.id, card_set.type, card_set.number
FROM trump
         LEFT JOIN card_set on 1 = 1
ORDER BY trump.id, card_set.type, card_set.number;


SELECT * FROM card limit 10;