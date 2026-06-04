from django.contrib import admin

from sampleapp.models import Article, Campaign, DraftArticle, Reservation, Room, WebhookEvent

admin.site.register(WebhookEvent)
admin.site.register(Article)
admin.site.register(Campaign)
admin.site.register(Room)
admin.site.register(Reservation)
admin.site.register(DraftArticle)
