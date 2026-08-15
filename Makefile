COMPOSE = docker compose --env-file infra/.env -f infra/docker-compose.yml

.PHONY = infra-up infra-down psql-dwh

infra-up:
	$(COMPOSE) up -d --wait

infra-down:
	$(COMPOSE) down

psql-dwh:
	$(COMPOSE) exec dwh sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'