FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY services/x_ingest/requirements.txt /tmp/x-ingest-requirements.txt
RUN pip install --no-cache-dir -r /tmp/x-ingest-requirements.txt
COPY pipeline ./pipeline
COPY services ./services
COPY contracts ./contracts
CMD ["python", "-m", "uvicorn", "services.x_ingest.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080"]
