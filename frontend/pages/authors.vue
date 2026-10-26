<script setup lang="ts">
import { Search } from 'lucide-vue-next'

const PAGE_SIZE = 24

const supabase = useSupabase()
const route = useRoute()
const router = useRouter()

const query = ref((route.query.q as string) || '')
const page = ref(Number(route.query.page) || 1)
const authors = ref<any[]>([])
const total = ref(0)
const state = ref<'loading' | 'ready' | 'error'>('loading')

const load = async () => {
  state.value = 'loading'
  const { data, error } = await supabase.rpc('search_authors', {
    p_query: query.value.trim(),
    p_limit: PAGE_SIZE,
    p_offset: (page.value - 1) * PAGE_SIZE,
  })
  if (error) {
    state.value = 'error'
    return
  }
  authors.value = data || []
  total.value = Number(data?.[0]?.total_count ?? 0)
  state.value = 'ready'
}

const sync = () => {
  router.replace({
    query: {
      q: query.value.trim() || undefined,
      page: page.value > 1 ? String(page.value) : undefined,
    },
  })
  load()
}

let timer: ReturnType<typeof setTimeout> | undefined
watch(query, () => {
  clearTimeout(timer)
  timer = setTimeout(() => {
    page.value = 1
    sync()
  }, 300)
})

watch(page, () => {
  sync()
  window.scrollTo({ top: 0 })
})

await load()
</script>

<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold">Авторы</h1>
      <p class="text-sm text-muted-foreground">
        Отсортированы по индексу Хирша. Профили без отметки созданы автоматически из загруженных статей.
      </p>
    </div>

    <div class="relative max-w-md">
      <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
      <Input v-model="query" placeholder="Поиск по ФИО (кириллица или латиница)" class="pl-9" aria-label="Поиск автора" />
    </div>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
    <StateBlock v-else-if="!authors.length" state="empty" :message="query ? `Никого не найдено по запросу «${query}»` : 'Авторов пока нет'" />

    <div v-else class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <AuthorCard v-for="a in authors" :key="a.id" :author="a" />
    </div>

    <AppPagination v-model:page="page" :total="total" :page-size="PAGE_SIZE" />
  </div>
</template>
