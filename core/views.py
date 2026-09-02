import socket

from django.conf import settings
from django.http import HttpResponse
from django.shortcuts import render


def home(request):
    """Home page.

    Shows the image version and the pod name. Both are useful when watching a
    deployment: the version changes when Argo CD syncs a new tag, and the pod
    name changes when the ReplicaSet is rolled.
    """
    context = {
        "version": settings.APP_VERSION,
        "environment": settings.APP_ENVIRONMENT,
        "pod": socket.gethostname(),
    }
    return render(request, "core/home.html", context)


def healthz(request):
    """Liveness and readiness probe target.

    Deliberately does nothing but return 200. A probe that touches a database
    turns a slow query into a restart loop.
    """
    return HttpResponse("ok", content_type="text/plain")
