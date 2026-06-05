from django.contrib import admin

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

admin.site.register(WebhookEvent)
admin.site.register(Article)
admin.site.register(Campaign)
admin.site.register(ProductAttribute)
admin.site.register(KnowledgeEntry)
admin.site.register(RagChunk)
admin.site.register(Room)
admin.site.register(Reservation)
admin.site.register(DraftArticle)
admin.site.register(ExternalAccount)
admin.site.register(Customer)
admin.site.register(ImportJob)
admin.site.register(Stock)
