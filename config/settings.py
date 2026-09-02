"""Django settings for the CI/CD demo application.

Everything that changes between environments comes from an environment
variable, which in Kubernetes is filled in from the ConfigMap that the Helm
chart renders.
"""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-only-not-for-production")

DEBUG = os.getenv("DEBUG", "0") == "1"

ALLOWED_HOSTS = os.getenv("DJANGO_ALLOWED_HOSTS", "*").split(",")

# The load balancer address is not known when the image is built, so trust the
# host header for CSRF instead of hardcoding an origin.
CSRF_TRUSTED_ORIGINS = [
    o for o in os.getenv("CSRF_TRUSTED_ORIGINS", "").split(",") if o
]

INSTALLED_APPS = [
    "django.contrib.staticfiles",
    "core",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    # Serves static files straight from gunicorn. No nginx sidecar needed for
    # an application this small.
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

# No database. This application exists to prove the pipeline works, and adding
# RDS would add cost and moving parts without proving anything more about
# Jenkins or Argo CD.
DATABASES = {}

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ---------------------------------------------------------------------------
# Values shown on the home page. APP_VERSION is set by the Helm chart from the
# image tag, which makes a deployment visible in the browser: refresh the page
# after Argo CD syncs and the version changes.
# ---------------------------------------------------------------------------
APP_VERSION = os.getenv("APP_VERSION", "dev")
APP_ENVIRONMENT = os.getenv("APP_ENVIRONMENT", "local")
