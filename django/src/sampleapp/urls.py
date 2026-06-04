from django.urls import path

from sampleapp.views import health, sample_result

urlpatterns = [
    path("", health),
    path("sample/", sample_result),
]
