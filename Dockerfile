FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
COPY pyproject.toml README.md ./
COPY src/ ./src/
RUN pip install --no-cache-dir . && \
    groupadd --system --gid 10001 app && \
    useradd --system --uid 10001 --gid 10001 --home-dir /app app
COPY alembic.ini ./
COPY alembic/ ./alembic/

USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "from urllib.request import urlopen; urlopen('http://127.0.0.1:8000/health/live',timeout=3).close()" || exit 1
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn opsforge.main:app --host 0.0.0.0 --port 8000 --workers 1"]
