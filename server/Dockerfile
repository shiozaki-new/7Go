FROM python:3.12-slim

WORKDIR /app
COPY server.py .

# SQLite DB is stored in /data for persistent volume mount
ENV SIGNAL_HOST=0.0.0.0
ENV SIGNAL_PORT=8787

EXPOSE 8787

CMD ["python3", "server.py"]
