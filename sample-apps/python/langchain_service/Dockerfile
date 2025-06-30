FROM python:3.12-slim

WORKDIR /app

COPY . .

RUN pip install --no-cache-dir -r ec2-requirements.txt

EXPOSE 8000

CMD ["opentelemetry-instrument", "python", "server.py"]