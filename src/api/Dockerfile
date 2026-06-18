# Lab 2 buổi chiều: Dockerfile
FROM python:3.13-alpine
RUN pip install flask prometheus-flask-exporter gunicorn gevent
COPY app.py /app/app.py
WORKDIR /app
EXPOSE 8080
CMD ["gunicorn", "app:app", "--bind", "0.0.0.0:8080", "--worker-class", "gevent", "--workers", "2", "--worker-connections", "100"]
