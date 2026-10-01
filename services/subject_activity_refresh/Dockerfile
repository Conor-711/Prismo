FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app

RUN pip install --no-cache-dir 'psycopg[binary]>=3.2,<4' 'requests>=2.32,<3' 'python-dotenv>=1,<2'
COPY pipeline /app/pipeline

CMD ["python", "-m", "pipeline.jobs.congress_capture.refresh_cycle"]
