<script setup lang="ts">
import { Quote } from 'lucide-vue-next'
import { plural, year } from '~/lib/format'

defineProps<{
  publication: {
    id: string
    title: string
    published_date?: string | null
    citation_count?: number | null
    language?: string | null
    journal_title?: string | null
    authors?: string | null
  }
}>()
</script>

<template>
  <NuxtLink :to="`/publications/${publication.id}`" class="block min-w-0">
    <Card class="transition-colors hover:bg-accent/50">
      <CardHeader class="gap-1.5 p-4 sm:p-6">
        <CardTitle class="text-base leading-snug">{{ publication.title }}</CardTitle>
        <CardDescription class="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span v-if="publication.authors" class="text-foreground/80">{{ publication.authors }}</span>
          <span v-if="publication.journal_title">· {{ publication.journal_title }}</span>
          <span v-if="publication.published_date">· {{ year(publication.published_date) }}</span>
          <Badge v-if="publication.citation_count" variant="secondary" class="gap-1">
            <Quote class="h-3 w-3" />
            {{ publication.citation_count }}
            {{ plural(publication.citation_count, 'цитирование', 'цитирования', 'цитирований') }}
          </Badge>
        </CardDescription>
      </CardHeader>
    </Card>
  </NuxtLink>
</template>
