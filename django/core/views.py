import socket

from django.conf import settings
from django.db import connection
from django.http import HttpResponse, JsonResponse
from django.shortcuts import render


def _database_status():
    """Ask the database the cheapest question there is.

    Returns a short label rather than an exception, because the home page has to
    render either way. The connect timeout is set in settings, so a database
    that is unreachable costs five seconds and not the whole request timeout.
    """
    engine = settings.DATABASES["default"]["ENGINE"].rsplit(".", 1)[-1]
    host = settings.DATABASES["default"].get("HOST") or "local file"

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
    except Exception as exc:  # noqa: BLE001 - the label is the whole point
        return {"engine": engine, "host": host, "ok": False, "detail": type(exc).__name__}

    return {"engine": engine, "host": host, "ok": True, "detail": "connected"}


def home(request):
    """Home page.

    Shows the image version, the pod name and whether the database answers.
    All three are useful when watching a deployment: the version changes when
    Argo CD syncs a new tag, the pod name changes when the ReplicaSet is rolled,
    and the database line proves the pod really reaches RDS.
    """
    context = {
        "version": settings.APP_VERSION,
        "environment": settings.APP_ENVIRONMENT,
        "pod": socket.gethostname(),
        "database": _database_status(),
    }
    return render(request, "core/home.html", context)


def healthz(request):
    """Liveness and readiness probe target.

    Deliberately does nothing but return 200. A probe that touches a database
    turns a slow query into a restart loop, which is the opposite of what a
    probe is for.
    """
    return HttpResponse("ok", content_type="text/plain")


def dbz(request):
    """Database check, on its own endpoint and not on the probe path.

    Returns 200 when the query succeeds and 503 when it does not, so it can be
    curled from a terminal or scraped by something else without parsing HTML.
    """
    status = _database_status()
    return JsonResponse(status, status=200 if status["ok"] else 503)
