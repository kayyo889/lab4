.PHONY: help setup deploy start stop restart status migrate rollback test lint quality verify db-check


help:
	@echo "setup    - первоначальная настройка проекта"
	@echo "deploy      - деплой последней версии проекта"
	@echo "start      - запуск"
	@echo "stop      - остановка"
	@echo "restart      - перезапуск"
	@echo "status      - просмотр статуса"
	@echo "migrate		- провести миграцию"


setup:
	@echo "первичная настройка начата"
	git clone https://github.com/veter-peremen/music_store/ .
	npm install
	@test -f .env || (cp .env.example .env && echo "конфиг создан!")

deploy:
	@test -f ./deploy.sh || (echo "скрипт deploy.sh не найден!" && exit 1)
	@echo "деплой запущен"
	./deploy.sh

start:
	sudo systemctl start music-store
	@echo "сервер запущен"

stop:
	sudo systemctl stop music-store
	@echo "сервер остановлен"

restart:
	sudo systemctl restart music-store
	@echo "сервер перезагружен"

status:
	sudo systemctl status music-store

migrate:
	npx knex migrate:latest

rollback:
	npx knex migrate:rollback

test:
	npm test -- $(TEST_ARGS)

lint:
	npm run lint -- $(LINT_ARGS)

quality: lint
	npm run format:check

verify: quality test
	@echo "все проверки пройдены"



#.PHONY: help setup run test quality lint format migrate rollback seed verify up down container-check

#help:
#	@echo "setup    - установка зависимостей и подготовка .env"
#	@echo "run      - локальный запуск приложения"
#	@echo "test     - автоматические тесты"
#	@echo "quality  - форматирование и статический анализ"
#	@echo "migrate  - применение миграций"
#	@echo "rollback - откат последней миграции"
#	@echo "seed     - тестовые данные"
#	@echo "verify   - полный набор локальных проверок (quality + test)"
#	@echo "up       - запуск контейнера с БД"
#	@echo "down     - остановка контейнера с БД"

#setup:
#	npm ci || npm install
#	@test -f .env || (cp .env.example .env && echo "Создан .env из .env.example - проверьте значения")

#run:
#	npm start

#test:
#	npm test

#lint:
#	npm run lint

#format:
#	npm run format:check

#quality:
#	npm run format:check
#	npm run lint

#migrate:
#	npm run migrate

#rollback:
#	npm run migrate:rollback

#seed:
#	npm run seed

#verify: quality test
#	@echo "Все локальные проверки пройдены"

#up:
#	docker compose up -d

#down:
#	docker compose down

#container-check:
#	docker compose ps

.PHONY: container-check container-up container-down container-backup container-restore
container-check:
	python3 scripts/container-check.py

# Gate deployment on an isolated integration check of the current working tree.
container-up: container-check
	python3 scripts/container-check.py --policy-only
	docker compose build
	docker compose up -d --wait

container-down:
	docker compose down

container-backup:
	sh scripts/db-backup.sh

container-restore:
	sh scripts/db-restore.sh "$(BACKUP)" "$(RESTORE_PROJECT)"

# Проверка миграций и восстановления в отдельных одноразовых БД.
db-check:
	sh scripts/ci/db-check.sh
