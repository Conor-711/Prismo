FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

COPY services/client_api/requirements.txt /tmp/client-api-requirements.txt
RUN pip install --no-cache-dir --disable-pip-version-check -r /tmp/client-api-requirements.txt \
    && useradd --create-home --uid 10001 bsmart

COPY --chown=bsmart:bsmart services /app/services
COPY --chown=bsmart:bsmart contracts /app/contracts

USER bsmart

EXPOSE 8080

CMD ["python", "-m", "uvicorn", "services.client_api.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers", "--forwarded-allow-ips", "*"]
