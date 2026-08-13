infra-up:
	docker compose --env-file infra/.env -f infra/docker-compose.yml up -d

infra-down:
	docker compose --env-file infra/.env -f infra/docker-compose.yml down