# コマンド定義
EXEC=docker exec -it
PG_CONTAINER=pg-demo18
PG_DB=pgdemo
PG_USER=pg-demo18
PARKING_DIR=src/design_parking
PARKING_TMP=/tmp/design_parking

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

.PHONY: pg-bash my-bash psql mysql initialize parking initialize-parking
# Generic initialize target with optional module goals
initialize:
	@echo "[initialize] Starting initialization goals: $(MAKECMDGOALS)"
	@if echo "$(MAKECMDGOALS)" | grep -q "\bparking\b"; then \
		bash $(PARKING_DIR)/init.sh; \
	else \
		echo "[initialize] No optional module specified. Use: make initialize parking"; \
	fi

# Placeholder optional goal (so 'make initialize parking' works)
parking:
	@true
pg-bash:
	${EXEC} pg-demo18 bash

my-bash:
	${EXEC} my-demo84 bash

psql:
	${EXEC} pg-demo18 psql -U pg-demo18 -d pgdemo

mysql:
	${EXEC} my-demo84 mysql -uroot -p

# 駐車場設計DDLの取り込み（soudai/ai/ai2 を各スキーマへ）
initialize-parking:
	@echo "[initialize-parking] Import DDLs into $(PG_DB) on $(PG_CONTAINER)"
	$(EXEC) $(PG_CONTAINER) bash -lc "mkdir -p $(PARKING_TMP)"
	docker cp $(PARKING_DIR)/init.sql $(PG_CONTAINER):$(PARKING_TMP)/init.sql
	docker cp $(PARKING_DIR)/soudai_ddl.sql $(PG_CONTAINER):$(PARKING_TMP)/soudai_ddl.sql
	docker cp $(PARKING_DIR)/ai_ddl.sql $(PG_CONTAINER):$(PARKING_TMP)/ai_ddl.sql
	docker cp $(PARKING_DIR)/ai2_ddl.sql $(PG_CONTAINER):$(PARKING_TMP)/ai2_ddl.sql
	$(EXEC) $(PG_CONTAINER) bash -lc "cd $(PARKING_TMP) && psql -U $(PG_USER) -d $(PG_DB) -f $(PARKING_TMP)/init.sql"
