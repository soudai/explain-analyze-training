from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db import connection
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.utils import timezone

from sampleapp.models import (
    Article,
    Campaign,
    Customer,
    DraftArticle,
    ExternalAccount,
    ImportJob,
    KnowledgeEntry,
    ProductAttribute,
    RagChunk,
    Reservation,
    Room,
    Stock,
    WebhookEvent,
)


class Command(BaseCommand):
    help = "Load sample data for the article examples"

    def handle(self, *args, **options):
        now = timezone.now()

        WebhookEvent.objects.get_or_create(
            provider="stripe",
            event_type="invoice.paid",
            payload={"customer": {"id": "cus_123"}, "livemode": True, "amount": 1200},
        )
        WebhookEvent.objects.get_or_create(
            provider="stripe",
            event_type="invoice.created",
            payload={"customer": {"id": "cus_999"}, "livemode": False, "amount": 800},
        )
        WebhookEvent.objects.get_or_create(
            provider="github",
            event_type="push",
            payload={"repository": {"full_name": "example/project"}, "branch": "main"},
        )

        ProductAttribute.objects.update_or_create(
            sku="SKU-RED-M",
            defaults={"attrs": {"color": "red", "size": "M", "material": "cotton"}},
        )
        ProductAttribute.objects.update_or_create(
            sku="SKU-BLUE-L",
            defaults={"attrs": {"color": "blue", "size": "L", "material": "linen"}},
        )

        Article.objects.update_or_create(
            title="PostgreSQL and Django",
            defaults={"body": "sample", "tags": ["postgresql", "django"]},
        )
        Article.objects.update_or_create(
            title="Only Django",
            defaults={"body": "sample", "tags": ["django"]},
        )
        Article.objects.update_or_create(
            title="Django full text search",
            defaults={
                "body": "PostgreSQL full text search can be used from Django with SearchVector.",
                "tags": ["django", "search"],
            },
        )

        Campaign.objects.update_or_create(
            name="Now Active Campaign",
            defaults={"active_period": DateTimeTZRange(now - timedelta(days=1), now + timedelta(days=1), "[)")},
        )
        Campaign.objects.update_or_create(
            name="Expired Campaign",
            defaults={"active_period": DateTimeTZRange(now - timedelta(days=10), now - timedelta(days=5), "[)")},
        )

        KnowledgeEntry.objects.update_or_create(
            title="PostgreSQL JSONB",
            defaults={
                "content": "JSONB can store flexible documents and query nested keys.",
                "embedding": [0.90, 0.10, 0.20],
            },
        )
        KnowledgeEntry.objects.update_or_create(
            title="Django ORM",
            defaults={
                "content": "Django ORM maps Python models to database tables.",
                "embedding": [0.20, 0.90, 0.10],
            },
        )
        KnowledgeEntry.objects.update_or_create(
            title="Vector Search",
            defaults={
                "content": "pgvector stores embeddings and searches by distance.",
                "embedding": [0.80, 0.20, 0.30],
            },
        )

        RagChunk.objects.update_or_create(
            source="memo.md",
            title="JSONField and jsonb",
            defaults={
                "body": "Django JSONField stores PostgreSQL jsonb and supports nested key lookups.",
                "embedding": [0.90, 0.10, 0.20],
            },
        )
        RagChunk.objects.update_or_create(
            source="memo.md",
            title="PostgreSQL range types",
            defaults={
                "body": "Range types store periods and work well with GiST indexes and exclusion constraints.",
                "embedding": [0.20, 0.80, 0.20],
            },
        )
        RagChunk.objects.update_or_create(
            source="memo.md",
            title="pgvector for RAG",
            defaults={
                "body": "pgvector stores embeddings in PostgreSQL and can retrieve nearby chunks.",
                "embedding": [0.85, 0.15, 0.25],
            },
        )

        room, _ = Room.objects.get_or_create(number="A-101")
        day_start = timezone.localtime(now).replace(hour=0, minute=0, second=0, microsecond=0)
        Reservation.objects.get_or_create(
            room=room,
            timespan=DateTimeTZRange(day_start, day_start + timedelta(days=1), "[)"),
            cancelled=False,
        )
        Reservation.objects.get_or_create(
            room=room,
            timespan=DateTimeTZRange(day_start, day_start + timedelta(days=1), "[)"),
            cancelled=True,
        )

        DraftArticle.objects.get_or_create(
            user_id=1,
            status=DraftArticle.STATUS_DRAFT,
            defaults={"title": "first draft"},
        )
        DraftArticle.objects.get_or_create(
            user_id=1,
            status=DraftArticle.STATUS_PUBLISHED,
            defaults={"title": "published article"},
        )

        ExternalAccount.objects.update_or_create(
            tenant_id=1,
            external_id=None,
            defaults={},
        )
        ExternalAccount.objects.update_or_create(
            tenant_id=1,
            external_id="acct_123",
            defaults={},
        )
        ExternalAccount.objects.update_or_create(
            tenant_id=2,
            external_id=None,
            defaults={},
        )

        Customer.objects.update_or_create(
            email="alice@example.com",
            defaults={"name": "Alice", "deleted_at": None},
        )
        Customer.objects.update_or_create(
            email="old@example.com",
            defaults={"name": "Old Customer", "deleted_at": now - timedelta(days=1)},
        )

        ImportJob.objects.get_or_create(
            status="pending",
            payload={"name": "import-1"},
            defaults={"started_at": None},
        )
        ImportJob.objects.get_or_create(
            status="pending",
            payload={"name": "import-2"},
            defaults={"started_at": None},
        )
        ImportJob.objects.get_or_create(
            status="processing",
            payload={"name": "import-running"},
            defaults={"started_at": now},
        )

        Stock.objects.update_or_create(
            sku="A-001",
            defaults={"quantity": 10, "seen_at": now},
        )
        Stock.objects.update_or_create(
            sku="B-002",
            defaults={"quantity": 3, "seen_at": now},
        )

        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO event_log (id, occurred_at, tenant_id, payload)
                VALUES (%s, %s, %s, %s::jsonb)
                ON CONFLICT (id, occurred_at)
                DO UPDATE SET tenant_id = EXCLUDED.tenant_id, payload = EXCLUDED.payload
                """,
                [
                    "00000000-0000-0000-0000-000000000001",
                    "2026-06-05 10:00:00+09",
                    1,
                    '{"event": "memo_sample", "feature": "partitioning"}',
                ],
            )

        self.stdout.write(self.style.SUCCESS("Sample data loaded"))
