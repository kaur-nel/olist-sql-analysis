.RECIPEPREFIX = >
PY ?= python

.PHONY: setup run test lint docker-run down help

help:
> @echo Targets: setup run test lint docker-run down

# Install pinned packages and start the database (activate .venv first)
setup:
> $(PY) -m pip install -r requirements.txt
> docker compose up -d --wait db

# Load data, audit, views, queries, charts (needs data/raw/*.csv)
run:
> $(PY) -m src.pipeline

test:
> $(PY) -m pytest -q

lint:
> $(PY) -m ruff check .

# Same pipeline, inside Docker
docker-run:
> docker compose --profile pipeline build app
> docker compose --profile pipeline run --rm app

down:
> docker compose --profile pipeline down