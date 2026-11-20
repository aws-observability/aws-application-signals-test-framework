## Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
## SPDX-License-Identifier: Apache-2.0
from django.urls import path
from remote_service_app import views

urlpatterns = [
    path('healthcheck', views.healthcheck),
    path('status/<int:code>', views.status),
]
