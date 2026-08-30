FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY services/smart_money_ingest/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY pipeline ./pipeline
COPY services ./services
COPY contracts ./contracts
CMD ["python", "-m", "uvicorn", "services.smart_money_ingest.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]
