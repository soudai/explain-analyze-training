from django.contrib.postgres.constraints import ExclusionConstraint
from django.contrib.postgres.fields import ArrayField, DateTimeRangeField, RangeOperators
from django.contrib.postgres.indexes import GinIndex, GistIndex
from django.db import models
from django.db.models import Q


class WebhookEvent(models.Model):
    provider = models.CharField(max_length=50)
    event_type = models.CharField(max_length=100)
    payload = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            GinIndex(
                fields=["payload"],
                name="webhook_payload_path_gin",
                opclasses=["jsonb_path_ops"],
            ),
        ]


class Article(models.Model):
    title = models.CharField(max_length=200)
    body = models.TextField()
    tags = ArrayField(models.CharField(max_length=50), default=list)

    class Meta:
        indexes = [
            GinIndex(fields=["tags"], name="article_tags_gin"),
        ]


class Campaign(models.Model):
    name = models.CharField(max_length=200)
    active_period = DateTimeRangeField()

    class Meta:
        indexes = [
            GistIndex(fields=["active_period"], name="campaign_active_period_gist"),
        ]


class Room(models.Model):
    number = models.CharField(max_length=20, unique=True)


class Reservation(models.Model):
    room = models.ForeignKey(Room, on_delete=models.CASCADE)
    timespan = DateTimeRangeField()
    cancelled = models.BooleanField(default=False)

    class Meta:
        constraints = [
            ExclusionConstraint(
                name="exclude_overlapping_reservations",
                expressions=[
                    ("timespan", RangeOperators.OVERLAPS),
                    ("room", RangeOperators.EQUAL),
                ],
                condition=Q(cancelled=False),
            ),
        ]


class DraftArticle(models.Model):
    STATUS_DRAFT = "draft"
    STATUS_PUBLISHED = "published"
    STATUS_ARCHIVED = "archived"

    STATUS_CHOICES = [
        (STATUS_DRAFT, "draft"),
        (STATUS_PUBLISHED, "published"),
        (STATUS_ARCHIVED, "archived"),
    ]

    user_id = models.BigIntegerField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES)
    title = models.CharField(max_length=200)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user_id"],
                condition=Q(status=STATUS_DRAFT),
                name="unique_draft_article_per_user",
            ),
            models.CheckConstraint(
                condition=Q(status__in=[STATUS_DRAFT, STATUS_PUBLISHED, STATUS_ARCHIVED]),
                name="draft_article_valid_status",
            ),
        ]
