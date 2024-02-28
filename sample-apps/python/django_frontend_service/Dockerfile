# Use an official Python runtime as a parent image
FROM python:3.10

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Set the working directory
WORKDIR /django_frontend_app

# Install dependencies
COPY django_frontend_service/requirements.txt /django_frontend_app/
RUN pip install -r requirements.txt

# Copy the project code into the container
COPY django_frontend_service/. /django_frontend_app/