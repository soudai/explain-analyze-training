from datetime import timedelta

from django.db import IntegrityError, transaction
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.http import JsonResponse
from django.utils import timezone
from pgvector.django import CosineDistance

from sampleapp.models import Article, Campaign, DraftArticle, RagChunk, Reservation, Room, WebhookEvent


def health(request):
    return JsonResponse({"status": "ok"})


def sample_result(request):
    now = timezone.now()

    paid_events_count = WebhookEvent.objects.filter(
        provider="stripe",
        event_type="invoice.paid",
    ).count()

    customer_events_count = WebhookEvent.objects.filter(
        payload__customer__id="cus_123",
    ).count()

    livemode_events_count = WebhookEvent.objects.filter(
        payload__contains={"livemode": True},
    ).count()

    events_with_customer_count = WebhookEvent.objects.filter(
        payload__has_key="customer",
    ).count()

    contains_postgres_titles = list(
        Article.objects.filter(tags__contains=["postgresql"]).order_by("id").values_list("title", flat=True)
    )

    overlap_titles = list(
        Article.objects.filter(tags__overlap=["django", "postgresql"]).order_by("id").values_list("title", flat=True)
    )

    active_campaign_names = list(
        Campaign.objects.filter(active_period__contains=now).order_by("id").values_list("name", flat=True)
    )

    query_embedding = [0.90, 0.10, 0.20]
    nearest_chunks = [
        {
            "title": chunk.title,
            "distance": round(chunk.distance, 6),
        }
        for chunk in RagChunk.objects.annotate(distance=CosineDistance("embedding", query_embedding))
        .order_by("distance")
        .only("title")[:2]
    ]

    room = Room.objects.get(number="A-101")
    overlap_blocked = False
    try:
        with transaction.atomic():
            Reservation.objects.create(
                room=room,
                timespan=DateTimeTZRange(now, now + timedelta(hours=1), "[)"),
            )
    except IntegrityError:
        overlap_blocked = True

    draft_blocked = False
    try:
        with transaction.atomic():
            DraftArticle.objects.create(
                user_id=1,
                status=DraftArticle.STATUS_DRAFT,
                title="duplicate draft",
            )
    except IntegrityError:
        draft_blocked = True

    return JsonResponse(
        {
            "jsonfield": {
                "paid_events_count": paid_events_count,
                "customer_events_count": customer_events_count,
                "livemode_events_count": livemode_events_count,
                "events_with_customer_count": events_with_customer_count,
            },
            "arrayfield": {
                "contains_postgresql": contains_postgres_titles,
                "overlap_django_or_postgresql": overlap_titles,
            },
            "rangefield": {
                "active_campaigns": active_campaign_names,
            },
            "pgvector": {
                "query_embedding": query_embedding,
                "nearest_chunks": nearest_chunks,
            },
            "constraints": {
                "reservation_overlap_blocked": overlap_blocked,
                "duplicate_draft_blocked": draft_blocked,
            },
        }
    )
