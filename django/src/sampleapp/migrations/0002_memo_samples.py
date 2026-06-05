import django.contrib.postgres.indexes
import django.contrib.postgres.operations
import django.db.models.functions
import pgvector.django
from django.db import migrations, models
from django.db.models import Q


class Migration(migrations.Migration):
    dependencies = [
        ("sampleapp", "0001_initial"),
    ]

    operations = [
        django.contrib.postgres.operations.TrigramExtension(),
        migrations.CreateModel(
            name="ProductAttribute",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("sku", models.CharField(max_length=100, unique=True)),
                ("attrs", models.JSONField(default=dict)),
            ],
            options={
                "indexes": [
                    django.contrib.postgres.indexes.GinIndex(fields=["attrs"], name="product_attrs_gin"),
                ],
            },
        ),
        migrations.CreateModel(
            name="ExternalAccount",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("tenant_id", models.BigIntegerField()),
                ("external_id", models.CharField(blank=True, max_length=100, null=True)),
            ],
            options={
                "constraints": [
                    models.UniqueConstraint(
                        fields=("tenant_id", "external_id"),
                        name="unique_external_id_per_tenant",
                        nulls_distinct=False,
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="Customer",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("email", models.EmailField(max_length=254)),
                ("name", models.CharField(max_length=200)),
                ("deleted_at", models.DateTimeField(blank=True, null=True)),
            ],
            options={
                "indexes": [
                    models.Index(
                        condition=Q(deleted_at__isnull=True),
                        fields=["email"],
                        name="active_customer_email_idx",
                    ),
                    models.Index(django.db.models.functions.Lower("email"), name="customer_lower_email_idx"),
                    models.Index(fields=["email"], include=("name",), name="customer_email_inc_name_idx"),
                ],
            },
        ),
        migrations.CreateModel(
            name="RagChunk",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("source", models.CharField(max_length=200)),
                ("title", models.CharField(max_length=200)),
                ("body", models.TextField()),
                ("embedding", pgvector.django.VectorField(dimensions=3)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={
                "indexes": [
                    pgvector.django.HnswIndex(
                        ef_construction=64,
                        fields=["embedding"],
                        m=16,
                        name="rag_chunk_embedding_hnsw",
                        opclasses=["vector_cosine_ops"],
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="ImportJob",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("status", models.CharField(db_index=True, max_length=20)),
                ("payload", models.JSONField()),
                ("started_at", models.DateTimeField(blank=True, null=True)),
            ],
        ),
        migrations.CreateModel(
            name="Stock",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("sku", models.CharField(max_length=100, unique=True)),
                ("quantity", models.IntegerField()),
                ("seen_at", models.DateTimeField()),
            ],
        ),
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    """
                    CREATE TABLE event_log (
                        id uuid NOT NULL,
                        occurred_at timestamptz NOT NULL,
                        tenant_id bigint NOT NULL,
                        payload jsonb NOT NULL,
                        PRIMARY KEY (id, occurred_at)
                    ) PARTITION BY RANGE (occurred_at);

                    CREATE TABLE event_log_2026_06
                    PARTITION OF event_log
                    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
                    """,
                    """
                    DROP TABLE IF EXISTS event_log_2026_06;
                    DROP TABLE IF EXISTS event_log;
                    """,
                ),
            ],
            state_operations=[
                migrations.CreateModel(
                    name="EventLog",
                    fields=[
                        (
                            "pk",
                            models.CompositePrimaryKey(
                                "id",
                                "occurred_at",
                                blank=True,
                                editable=False,
                                primary_key=True,
                                serialize=False,
                            ),
                        ),
                        ("id", models.UUIDField(editable=False)),
                        ("occurred_at", models.DateTimeField()),
                        ("tenant_id", models.BigIntegerField()),
                        ("payload", models.JSONField()),
                    ],
                    options={"db_table": "event_log"},
                ),
            ],
        ),
    ]
