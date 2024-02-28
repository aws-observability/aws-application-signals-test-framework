from django.urls import path
from remote_service_app import views

urlpatterns = [
    path('health-check', views.healthcheck),
]
