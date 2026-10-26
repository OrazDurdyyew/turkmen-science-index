<script setup lang="ts">
import { BadgeCheck } from 'lucide-vue-next'
import { initials } from '~/lib/format'

defineProps<{
  author: {
    id: string
    full_name: string
    full_name_en?: string | null
    institution?: string | null
    h_index?: number | null
    i10_index?: number | null
    publication_count?: number | null
    is_registered?: boolean | null
  }
}>()
</script>

<template>
  <NuxtLink :to="`/profile/${author.id}`" class="block h-full min-w-0">
    <Card class="h-full transition-colors hover:bg-accent/50">
      <CardHeader class="p-4">
        <div class="flex items-center gap-3">
          <Avatar class="shrink-0">
            <AvatarFallback class="text-xs">{{ initials(author.full_name) }}</AvatarFallback>
          </Avatar>
          <div class="min-w-0">
            <CardTitle class="flex items-center gap-1.5 text-base">
              <span class="truncate">{{ author.full_name }}</span>
              <BadgeCheck v-if="author.is_registered" class="h-4 w-4 shrink-0 text-primary" aria-label="Зарегистрирован" />
            </CardTitle>
            <CardDescription class="truncate">
              {{ author.institution || author.full_name_en || ' ' }}
            </CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent class="px-4 pb-4 pt-0">
        <div class="flex gap-4 text-sm">
          <span>h-index: <strong>{{ author.h_index || 0 }}</strong></span>
          <span>i10: <strong>{{ author.i10_index || 0 }}</strong></span>
          <span v-if="author.publication_count != null">Статей: <strong>{{ author.publication_count }}</strong></span>
        </div>
      </CardContent>
    </Card>
  </NuxtLink>
</template>
