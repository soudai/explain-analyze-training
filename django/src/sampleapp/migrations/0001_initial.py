import django.contrib.postgres.fields
import django.contrib.postgres.indexes
import django.contrib.postgres.operations
import django.db.models.deletion
from django.contrib.postgres.constraints import ExclusionConstraint
from django.contrib.postgres.fields import RangeOperators
from django.db import migrations, models
from django.db.models import Q


class Migration(migrations.Migration):
    initial = True

    dependencies = []

    operations = [
        django.contrib.postgres.operations.BtreeGistExtension(),
        migrations.CreateModel(
            name="Article",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("title", models.CharField(max_length=200)),
                ("body", models.TextField()),
                (
                    "tags",
                    django.contrib.postgres.fields.ArrayField(
                        base_field=models.CharField(max_length=50),
                        default=list,
                        size=None,
                    ),
                ),
            ],
            options={
                "indexes": [django.contrib.postgres.indexes.GinIndex(fields=["tags"], name="article_tags_gin")],
            },
        ),
        migrations.CreateModel(
            name="Campaign",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("name", models.CharField(max_length=200)),
                ("active_period", django.contrib.postgres.fields.DateTimeRangeField()),
            ],
            options={
                "indexes": [
                    django.contrib.postgres.indexes.GistIndex(
                        fields=["active_period"],
                        name="campaign_active_period_gist",
                    )
                ],
            },
        ),
        migrations.CreateModel(
            name="DraftArticle",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("user_id", models.BigIntegerField()),
                (
                    "status",
                    models.CharField(
                        choices=[("draft", "draft"), ("published", "published"), ("archived", "archived")],
                        max_length=20,
                    ),
                ),
                ("title", models.CharField(max_length=200)),
            ],
            options={
                "constraints": [
                    models.UniqueConstraint(
                        condition=Q(status="draft"),
                        fields=("user_id",),
                        name="unique_draft_article_per_user",
                    ),
                    models.CheckConstraint(
                        condition=Q(status__in=["draft", "published", "archived"]),
                        name="draft_article_valid_status",
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="Room",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("number", models.CharField(max_length=20, unique=True)),
            ],
        ),
        migrations.CreateModel(
            name="WebhookEvent",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("provider", models.CharField(max_length=50)),
                ("event_type", models.CharField(max_length=100)),
                ("payload", models.JSONField()),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={
                "indexes": [
                    django.contrib.postgres.indexes.GinIndex(
                        fields=["payload"],
                        name="webhook_payload_path_gin",
                        opclasses=["jsonb_path_ops"],
                    )
                ],
            },
        ),
        migrations.CreateModel(
            name="Reservation",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("timespan", django.contrib.postgres.fields.DateTimeRangeField()),
                ("cancelled", models.BooleanField(default=False)),
                (
                    "room",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to="sampleapp.room"),
                ),
            ],
            options={
                "constraints": [
                    ExclusionConstraint(
                        condition=Q(cancelled=False),
                        expressions=[("timespan", RangeOperators.OVERLAPS), ("room", RangeOperators.EQUAL)],
                        name="exclude_overlapping_reservations",
                    )
                ],
            },
        ),
    ]
