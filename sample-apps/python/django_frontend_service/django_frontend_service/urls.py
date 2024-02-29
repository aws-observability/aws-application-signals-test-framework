from django.urls import path
from frontend_service_app import views

urlpatterns = [
    path('', views.healthcheck),
    path('aws-sdk-call', views.aws_sdk_call),
    path('outgoing-http-call', views.http_call),
    path('remote-service', views.downstream_service),
    path('client-call', views.async_service),
]
