from django.contrib.postgres.constraints import ExclusionConstraint
from django.contrib.postgres.fields import ArrayField, DateTimeRangeField, RangeOperators
from django.contrib.postgres.indexes import GinIndex, GistIndex
from django.db import models
from django.db.models import Q
from django.db.models.functions import Lower
from pgvector.django import HnswIndex, VectorField


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


class ProductAttribute(models.Model):
    sku = models.CharField(max_length=100, unique=True)
    attrs = models.JSONField(default=dict)

    class Meta:
        indexes = [
            GinIndex(fields=["attrs"], name="product_attrs_gin"),
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


class KnowledgeEntry(models.Model):
    title = models.CharField(max_length=200)
    content = models.TextField()
    embedding = VectorField(dimensions=3)

    class Meta:
        indexes = [
            HnswIndex(
                name="knowledge_embedding_hnsw",
                fields=["embedding"],
                m=16,
                ef_construction=64,
                opclasses=["vector_l2_ops"],
            ),
        ]


class RagChunk(models.Model):
    source = models.CharField(max_length=200)
    title = models.CharField(max_length=200)
    body = models.TextField()
    embedding = VectorField(dimensions=3)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            HnswIndex(
                name="rag_chunk_embedding_hnsw",
                fields=["embedding"],
                m=16,
                ef_construction=64,
                opclasses=["vector_cosine_ops"],
            ),
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
                condition=Q(status="draft"),
                name="unique_draft_article_per_user",
            ),
            models.CheckConstraint(
                condition=Q(status__in=["draft", "published", "archived"]),
                name="draft_article_valid_status",
            ),
        ]


class ExternalAccount(models.Model):
    tenant_id = models.BigIntegerField()
    external_id = models.CharField(max_length=100, null=True, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["tenant_id", "external_id"],
                nulls_distinct=False,
                name="unique_external_id_per_tenant",
            ),
        ]


class Customer(models.Model):
    email = models.EmailField()
    name = models.CharField(max_length=200)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(
                fields=["email"],
                condition=Q(deleted_at__isnull=True),
                name="active_customer_email_idx",
            ),
            models.Index(
                Lower("email"),
                name="customer_lower_email_idx",
            ),
            models.Index(
                fields=["email"],
                include=["name"],
                name="customer_email_inc_name_idx",
            ),
        ]


class ImportJob(models.Model):
    status = models.CharField(max_length=20, db_index=True)
    payload = models.JSONField()
    started_at = models.DateTimeField(null=True, blank=True)


class EventLog(models.Model):
    pk = models.CompositePrimaryKey("id", "occurred_at")
    id = models.UUIDField(editable=False)
    occurred_at = models.DateTimeField()
    tenant_id = models.BigIntegerField()
    payload = models.JSONField()

    class Meta:
        db_table = "event_log"


class Stock(models.Model):
    sku = models.CharField(max_length=100, unique=True)
    quantity = models.IntegerField()
    seen_at = models.DateTimeField()
