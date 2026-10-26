<script setup lang="ts">
import { Search } from 'lucide-vue-next'
import { LANGUAGES } from '~/lib/format'

const PAGE_SIZE = 20

const supabase = useSupabase()
const route = useRoute()
const router = useRouter()

const q = route.query
const query = ref((q.q as string) || '')
const tab = ref<'publications' | 'authors'>(q.tab === 'authors' ? 'authors' : 'publications')
const yearFrom = ref((q.from as string) || '')
const yearTo = ref((q.to as string) || '')
const language = ref((q.lang as string) || '')
const journalId = ref((q.journal as string) || '')
const sort = ref((q.sort as string) || 'relevance')
const page = ref(Number(q.page) || 1)

const results = ref<any[]>([])
const total = ref(0)
const state = ref<'idle' | 'loading' | 'ready' | 'error'>('idle')
const suggestions = ref<any[]>([])
const showSuggestions = ref(false)

const { data: journals } = await supabase.from('journals').select('id, title').order('title')

let searchSeq = 0

const hasFilters = computed(() => !!(yearFrom.value || yearTo.value || language.value || journalId.value))
const toInt = (v: string) => (/^\d{4}$/.test(v) ? Number(v) : undefined)

const search = async () => {
  showSuggestions.value = false
  if (!query.value.trim() && !(tab.value === 'publications' && hasFilters.value)) {
    results.value = []
    total.value = 0
    state.value = 'idle'
    router.replace({ query: {} })
    return
  }
  state.value = 'loading'
  router.replace({
    query: {
      q: query.value.trim() || undefined,
      tab: tab.value === 'authors' ? 'authors' : undefined,
      from: yearFrom.value || undefined,
      to: yearTo.value || undefined,
      lang: language.value || undefined,
      journal: journalId.value || undefined,
      sort: sort.value !== 'relevance' ? sort.value : undefined,
      page: page.value > 1 ? String(page.value) : undefined,
    },
  })

  const offset = (page.value - 1) * PAGE_SIZE
  const mine = ++searchSeq
  const { data, error } = tab.value === 'publications'
    ? await supabase.rpc('search_publications', {
        p_query: query.value.trim(),
        p_journal_id: journalId.value || undefined,
        p_year_from: toInt(yearFrom.value),
        p_year_to: toInt(yearTo.value),
        p_language: language.value || undefined,
        p_sort: sort.value,
        p_limit: PAGE_SIZE,
        p_offset: offset,
      })
    : await supabase.rpc('search_authors', { p_query: query.value.trim(), p_limit: PAGE_SIZE, p_offset: offset })

  // A slower earlier request must not overwrite newer results
  if (mine !== searchSeq) return
  if (error) {
    state.value = 'error'
    return
  }
  results.value = data || []
  total.value = Number((data as any[])?.[0]?.total_count ?? 0)
  state.value = 'ready'
}

const submit = () => {
  // Changing the page triggers the page watcher, which searches
  if (page.value !== 1) page.value = 1
  else search()
}

let suggestTimer: ReturnType<typeof setTimeout> | undefined
let suggestSeq = 0
const onInput = () => {
  clearTimeout(suggestTimer)
  suggestTimer = setTimeout(async () => {
    if (query.value.trim().length < 2) {
      suggestions.value = []
      showSuggestions.value = false
      return
    }
    const mine = ++suggestSeq
    const { data } = await supabase.rpc('autocomplete', { p_query: query.value.trim(), p_limit: 5 })
    if (mine !== suggestSeq) return
    suggestions.value = data || []
    showSuggestions.value = suggestions.value.length > 0
  }, 250)
}

const hideSuggestions = () => {
  // Let a click on a suggestion land before the list disappears
  setTimeout(() => { showSuggestions.value = false }, 150)
}

const selectSuggestion = (item: any) => {
  showSuggestions.value = false
  navigateTo(item.type === 'publication' ? `/publications/${item.id}` : `/profile/${item.id}`)
}

const switchTab = (t: 'publications' | 'authors') => {
  if (tab.value === t) return
  tab.value = t
  submit()
}

watch([journalId, language, sort], submit)
watch(page, () => {
  search()
  window.scrollTo({ top: 0 })
})

if (query.value || hasFilters.value) await search()
</script>

<template>
  <div class="space-y-6">
    <h1 class="text-2xl font-bold">Поиск</h1>

    <form class="flex gap-2" @submit.prevent="submit">
      <div class="relative flex-1">
        <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          v-model="query"
          placeholder="Название, ключевые слова или ФИО автора…"
          class="pl-9"
          aria-label="Поисковый запрос"
          autocomplete="off"
          @input="onInput"
          @focus="showSuggestions = suggestions.length > 0"
          @blur="hideSuggestions"
        />
        <div v-if="showSuggestions" class="absolute left-0 right-0 top-full z-50 mt-1 rounded-md border bg-popover p-1 shadow-md">
          <button
            v-for="item in suggestions"
            :key="`${item.type}-${item.id}`"
            type="button"
            class="flex w-full items-center gap-3 rounded px-3 py-2 text-left text-sm hover:bg-accent"
            @mousedown.prevent="selectSuggestion(item)"
          >
            <Badge variant="outline" class="shrink-0 text-xs">{{ item.type === 'publication' ? 'Статья' : 'Автор' }}</Badge>
            <span class="truncate font-medium">{{ item.label }}</span>
            <span v-if="item.sublabel" class="shrink-0 text-muted-foreground">{{ item.sublabel }}</span>
          </button>
        </div>
      </div>
      <Button type="submit" :disabled="state === 'loading'">Найти</Button>
    </form>

    <div class="flex gap-1 border-b" role="tablist">
      <button
        v-for="t in ([['publications', 'Публикации'], ['authors', 'Авторы']] as const)"
        :key="t[0]"
        role="tab"
        :aria-selected="tab === t[0]"
        class="-mb-px border-b-2 px-4 py-2 text-sm font-medium transition-colors"
        :class="tab === t[0] ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'"
        @click="switchTab(t[0])"
      >
        {{ t[1] }}
      </button>
    </div>

    <div v-if="tab === 'publications'" class="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap">
      <AppSelect v-model="journalId" class="col-span-2 sm:w-64" aria-label="Журнал">
        <option value="">Все журналы</option>
        <option v-for="j in journals || []" :key="j.id" :value="j.id">{{ j.title }}</option>
      </AppSelect>
      <Input v-model="yearFrom" inputmode="numeric" maxlength="4" placeholder="Год от" class="sm:w-28" aria-label="Год от" @change="submit" />
      <Input v-model="yearTo" inputmode="numeric" maxlength="4" placeholder="Год до" class="sm:w-28" aria-label="Год до" @change="submit" />
      <AppSelect v-model="language" class="sm:w-40" aria-label="Язык">
        <option value="">Все языки</option>
        <option v-for="(label, code) in LANGUAGES" :key="code" :value="code">{{ label }}</option>
      </AppSelect>
      <AppSelect v-model="sort" class="sm:w-48" aria-label="Сортировка">
        <option value="relevance">По релевантности</option>
        <option value="citations">По цитированиям</option>
        <option value="date">Сначала новые</option>
      </AppSelect>
    </div>

    <p v-if="state === 'idle'" class="py-12 text-center text-sm text-muted-foreground">
      Введите запрос. Поиск работает по названию, аннотации и ФИО авторов, с учётом опечаток.
    </p>
    <StateBlock v-else-if="state === 'loading'" state="loading" message="Ищем…" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="search" />
    <StateBlock v-else-if="!results.length" state="empty" :message="query ? `Ничего не найдено по запросу «${query}»` : 'Ничего не найдено'" />

    <template v-else>
      <p class="text-sm text-muted-foreground">Найдено: {{ total }}</p>
      <div v-if="tab === 'publications'" class="space-y-3">
        <PublicationCard v-for="pub in results" :key="pub.id" :publication="pub" />
      </div>
      <div v-else class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <AuthorCard v-for="a in results" :key="a.id" :author="a" />
      </div>
    </template>

    <AppPagination v-if="state === 'ready'" v-model:page="page" :total="total" :page-size="PAGE_SIZE" />
  </div>
</template>
