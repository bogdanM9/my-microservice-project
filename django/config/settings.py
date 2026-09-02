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

# Database.
#
# The connection details come from a Kubernetes Secret that Terraform writes
# from the outputs of modules/rds, so no host name and no password is ever
# committed. When POSTGRES_HOST is not set, which is the case for a plain
# docker run or a unit test, the application falls back to a local SQLite file
# and still starts.
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "")

if POSTGRES_HOST:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "HOST": POSTGRES_HOST,
            "PORT": os.getenv("POSTGRES_PORT", "5432"),
            "NAME": os.getenv("POSTGRES_DB", "appdb"),
            "USER": os.getenv("POSTGRES_USER", "dbadmin"),
            "PASSWORD": os.getenv("POSTGRES_PASSWORD", ""),
            # A pod that cannot reach the database should fail fast rather than
            # hold a request open until the client gives up.
            "CONN_MAX_AGE": 60,
            "OPTIONS": {"connect_timeout": 5},
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

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
