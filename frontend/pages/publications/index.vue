<script setup lang="ts">
import { FileUp } from 'lucide-vue-next'
import { LANGUAGES } from '~/lib/format'

const PAGE_SIZE = 20

const supabase = useSupabase()
const route = useRoute()
const router = useRouter()
const { user } = useAuth()

const page = ref(Number(route.query.page) || 1)
const sort = ref((route.query.sort as string) || 'date')
const journalId = ref((route.query.journal as string) || '')
const language = ref((route.query.lang as string) || '')

const publications = ref<any[]>([])
const total = ref(0)
const journals = ref<{ id: string; title: string }[]>([])
const state = ref<'loading' | 'ready' | 'error'>('loading')

const load = async () => {
  state.value = 'loading'
  const { data, error } = await supabase.rpc('search_publications', {
    p_query: '',
    p_journal_id: journalId.value || undefined,
    p_language: language.value || undefined,
    p_sort: sort.value,
    p_limit: PAGE_SIZE,
    p_offset: (page.value - 1) * PAGE_SIZE,
  })
  if (error) {
    state.value = 'error'
    return
  }
  publications.value = data || []
  total.value = Number(data?.[0]?.total_count ?? 0)
  state.value = 'ready'
}

watch([sort, journalId, language], () => {
  page.value = 1
})

watch([page, sort, journalId, language], () => {
  router.replace({
    query: {
      page: page.value > 1 ? String(page.value) : undefined,
      sort: sort.value !== 'date' ? sort.value : undefined,
      journal: journalId.value || undefined,
      lang: language.value || undefined,
    },
  })
  load()
  window.scrollTo({ top: 0 })
})

const { data: journalData } = await supabase.from('journals').select('id, title').order('title')
journals.value = journalData || []

await load()
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-bold">Публикации</h1>
        <p v-if="state === 'ready'" class="text-sm text-muted-foreground">Всего: {{ total }}</p>
      </div>
      <NuxtLink v-if="user" to="/publications/upload">
        <Button class="gap-1.5"><FileUp class="h-4 w-4" /> Загрузить PDF</Button>
      </NuxtLink>
    </div>

    <div class="grid gap-2 sm:flex sm:flex-wrap">
      <AppSelect v-model="sort" class="sm:w-52" aria-label="Сортировка">
        <option value="date">Сначала новые</option>
        <option value="citations">По цитированиям</option>
      </AppSelect>
      <AppSelect v-model="journalId" class="sm:w-72" aria-label="Журнал">
        <option value="">Все журналы</option>
        <option v-for="j in journals" :key="j.id" :value="j.id">{{ j.title }}</option>
      </AppSelect>
      <AppSelect v-model="language" class="sm:w-44" aria-label="Язык">
        <option value="">Все языки</option>
        <option v-for="(label, code) in LANGUAGES" :key="code" :value="code">{{ label }}</option>
      </AppSelect>
    </div>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
    <StateBlock v-else-if="!publications.length" state="empty" message="Публикаций не найдено" />

    <div v-else class="space-y-3">
      <PublicationCard v-for="pub in publications" :key="pub.id" :publication="pub" />
    </div>

    <AppPagination v-model:page="page" :total="total" :page-size="PAGE_SIZE" />
  </div>
</template>
