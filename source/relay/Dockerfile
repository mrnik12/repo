FROM python:3.14-slim

WORKDIR /app
COPY requirements.txt ./
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY app.py artwork.py ./
USER 65532:65532
EXPOSE 8080
CMD ["sh", "-c", "exec python -m uvicorn app:app --host 0.0.0.0 --port ${PORT:-8080} --limit-concurrency 16"]
