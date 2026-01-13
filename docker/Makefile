# コマンド定義
EXEC=docker exec -it

.PHONY: run
run: pull up logs

.PHONY: pull

pull:
	git pull origin main

.PHONY: up
up: 
	docker compose up -d

.PHONY: logs
logs:
	@docker compose logs -f

.PHONY: down
down:
	docker compose down

.PHONY: clean clean-postgres clean-mysql


clean: down clean-postgres clean-mysql

clean-postgres:
	-docker volume rm pg-demo-data
clean-mysql:
	-docker volume rm my-demo-data

.PHONY: pg-bash my-bash psql mysql
pg-bash:
	${EXEC} pg-demo18 bash

my-bash:
	${EXEC} my-demo84 bash

psql:
	${EXEC} pg-demo18 psql -U pg-demo18 -d pgdemo

mysql:
	${EXEC} my-demo84 mysql -uroot -p
