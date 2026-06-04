from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.utils import timezone

from sampleapp.models import Article, Campaign, DraftArticle, Reservation, Room, WebhookEvent


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

        Article.objects.get_or_create(
            title="PostgreSQL and Django",
            defaults={"body": "sample", "tags": ["postgresql", "django"]},
        )
        Article.objects.get_or_create(
            title="Only Django",
            defaults={"body": "sample", "tags": ["django"]},
        )

        Campaign.objects.update_or_create(
            name="Now Active Campaign",
            defaults={"active_period": DateTimeTZRange(now - timedelta(days=1), now + timedelta(days=1), "[)")},
        )

        room, _ = Room.objects.get_or_create(number="A-101")
        day_start = timezone.localtime(now).replace(hour=0, minute=0, second=0, microsecond=0)
        Reservation.objects.get_or_create(
            room=room,
            timespan=DateTimeTZRange(day_start, day_start + timedelta(days=1), "[)"),
            defaults={"cancelled": False},
        )

        DraftArticle.objects.get_or_create(
            user_id=1,
            status=DraftArticle.STATUS_DRAFT,
            defaults={"title": "first draft"},
        )

        self.stdout.write(self.style.SUCCESS("Sample data loaded"))
