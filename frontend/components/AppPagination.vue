<script setup lang="ts">
import { ChevronLeft, ChevronRight } from 'lucide-vue-next'

const props = defineProps<{
  page: number
  total: number
  pageSize: number
}>()

const emit = defineEmits<{ 'update:page': [page: number] }>()

const pages = computed(() => Math.max(1, Math.ceil(props.total / props.pageSize)))

// Compact window: 1 … 4 5 [6] 7 8 … 20
const items = computed(() => {
  const last = pages.value
  const cur = props.page
  const set = new Set([1, last, cur - 1, cur, cur + 1].filter(p => p >= 1 && p <= last))
  const sorted = [...set].sort((a, b) => a - b)
  const out: (number | '…')[] = []
  sorted.forEach((p, i) => {
    if (i > 0 && p - sorted[i - 1]! > 1) out.push('…')
    out.push(p)
  })
  return out
})

const go = (p: number) => {
  if (p >= 1 && p <= pages.value && p !== props.page) emit('update:page', p)
}
</script>

<template>
  <nav v-if="pages > 1" class="flex items-center justify-center gap-1" aria-label="Страницы">
    <Button variant="ghost" size="sm" :disabled="page <= 1" aria-label="Предыдущая" @click="go(page - 1)">
      <ChevronLeft class="h-4 w-4" />
    </Button>
    <template v-for="(item, i) in items" :key="i">
      <span v-if="item === '…'" class="px-2 text-sm text-muted-foreground">…</span>
      <Button
        v-else
        :variant="item === page ? 'default' : 'ghost'"
        size="sm"
        class="min-w-9"
        :aria-current="item === page ? 'page' : undefined"
        @click="go(item)"
      >
        {{ item }}
      </Button>
    </template>
    <Button variant="ghost" size="sm" :disabled="page >= pages" aria-label="Следующая" @click="go(page + 1)">
      <ChevronRight class="h-4 w-4" />
    </Button>
  </nav>
</template>
