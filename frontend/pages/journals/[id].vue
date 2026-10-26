<script setup lang="ts">
const PAGE_SIZE = 20

const route = useRoute()
const supabase = useSupabase()

const journalId = route.params.id as string
const journal = ref<any>(null)
const publications = ref<any[]>([])
const total = ref(0)
const page = ref(1)
const sort = ref('date')
const state = ref<'loading' | 'ready' | 'error'>('loading')

const loadPubs = async () => {
  const { data, error } = await supabase.rpc('search_publications', {
    p_query: '',
    p_journal_id: journalId,
    p_sort: sort.value,
    p_limit: PAGE_SIZE,
    p_offset: (page.value - 1) * PAGE_SIZE,
  })
  if (error) throw error
  publications.value = data || []
  total.value = Number(data?.[0]?.total_count ?? 0)
}

const load = async () => {
  state.value = 'loading'
  try {
    const { data, error } = await supabase.from('journals').select('*').eq('id', journalId).maybeSingle()
    if (error) throw error
    journal.value = data
    if (data) await loadPubs()
    state.value = 'ready'
  } catch {
    state.value = 'error'
  }
}

watch(sort, () => { page.value === 1 ? loadPubs() : (page.value = 1) })
watch(page, () => { loadPubs(); window.scrollTo({ top: 0 }) })

useHead(() => ({ title: journal.value ? `${journal.value.title} — TSI` : 'Журнал — TSI' }))

await load()
</script>

<template>
  <StateBlock v-if="state === 'loading'" state="loading" />
  <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
  <StateBlock v-else-if="!journal" state="empty" message="Журнал не найден" />

  <div v-else class="space-y-6">
    <div>
      <NuxtLink to="/journals" class="text-sm text-muted-foreground hover:underline">← Все журналы</NuxtLink>
      <h1 class="mt-2 text-2xl font-bold">{{ journal.title }}</h1>
      <p class="text-sm text-muted-foreground">
        <span v-if="journal.title_en">{{ journal.title_en }}</span>
        <span v-if="journal.issn"> · ISSN {{ journal.issn }}</span>
        <span v-if="journal.publisher"> · {{ journal.publisher }}</span>
      </p>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="text-sm text-muted-foreground">Статей: {{ total }}</p>
      <AppSelect v-model="sort" class="w-52" aria-label="Сортировка">
        <option value="date">Сначала новые</option>
        <option value="citations">По цитированиям</option>
      </AppSelect>
    </div>

    <StateBlock v-if="!publications.length" state="empty" message="В этом журнале пока нет статей" />
    <div v-else class="space-y-3">
      <PublicationCard v-for="pub in publications" :key="pub.id" :publication="pub" />
    </div>

    <AppPagination v-model:page="page" :total="total" :page-size="PAGE_SIZE" />
  </div>
</template>
