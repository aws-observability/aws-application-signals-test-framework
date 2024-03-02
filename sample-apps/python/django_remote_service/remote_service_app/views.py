## Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
## SPDX-License-Identifier: Apache-2.0
from django.http import HttpResponse

def healthcheck(request):
    return HttpResponse("Remote service healthcheck")
