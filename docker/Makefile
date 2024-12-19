

# コマンド定義
EXEC=docker exec -it


.PHONY: run
run: up update logs

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

.PHONY: pg-bash my-bash
pg-bash:
	${EXEC} pg-demo17 bash

my-bash:
	${EXEC} my-demo84 bash
