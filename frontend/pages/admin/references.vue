<script setup lang="ts">
import { Ban, Link2, RotateCcw, Search, Unlink } from 'lucide-vue-next'
import { errorMessage, ilikePattern, year } from '~/lib/format'

definePageMeta({ middleware: 'admin' })
useHead({ title: 'Ссылки · Администрирование' })

const PAGE_SIZE = 20

type Status = 'unmatched' | 'pending' | 'matched' | 'rejected'
const TABS: { value: Status; label: string }[] = [
  { value: 'unmatched', label: 'Не найдены' },
  { value: 'matched', label: 'Сопоставлены' },
  { value: 'pending', label: 'В очереди' },
  { value: 'rejected', label: 'Отклонены' },
]

const supabase = useSupabase()
const toast = useToast()

const status = ref<Status>('unmatched')
const query = ref('')
const page = ref(1)
const rows = ref<any[]>([])
const total = ref(0)
const state = ref<'loading' | 'ready' | 'error'>('loading')

// Row being resolved by hand
const openId = ref<string | null>(null)
const candidates = ref<any[]>([])
const manualQuery = ref('')
const manualResults = ref<any[]>([])
const busyId = ref<string | null>(null)

const load = async () => {
  state.value = 'loading'
  let req = supabase
    .from('raw_references')
    .select('id, raw_text, parsed_title, parsed_year, status, match_score, source:source_publication_id(id, title), matched:matched_publication_id(id, title)', { count: 'exact' })
    .eq('status', status.value)
    .order('created_at', { ascending: false })
    .range((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE - 1)
  if (query.value.trim()) req = req.ilike('raw_text', ilikePattern(query.value))
  const { data, error, count } = await req
  if (error) {
    state.value = 'error'
    return
  }
  rows.value = data || []
  total.value = count || 0
  state.value = 'ready'
}

const toggle = async (row: any) => {
  if (openId.value === row.id) {
    openId.value = null
    return
  }
  openId.value = row.id
  candidates.value = []
  manualQuery.value = ''
  manualResults.value = []
  const { data } = await supabase.rpc('reference_candidates', { p_ref_id: row.id, p_limit: 5 })
  if (openId.value === row.id) candidates.value = data || []
}

let manualTimer: ReturnType<typeof setTimeout> | undefined
watch(manualQuery, (q) => {
  clearTimeout(manualTimer)
  if (q.trim().length < 3) {
    manualResults.value = []
    return
  }
  manualTimer = setTimeout(async () => {
    const { data } = await supabase.from('publications').select('id, title, published_date').ilike('title', ilikePattern(q)).limit(8)
    manualResults.value = data || []
  }, 250)
})

const link = async (row: any, pubId: string) => {
  busyId.value = row.id
  const { error } = await supabase.rpc('admin_link_reference', { p_ref_id: row.id, p_publication_id: pubId })
  busyId.value = null
  if (error) return toast.show(errorMessage(error), 'error')
  toast.show('Ссылка привязана, цитирование засчитано')
  openId.value = null
  load()
}

const setStatus = async (row: any, next: 'unmatched' | 'rejected' | 'pending', message: string) => {
  busyId.value = row.id
  const { error } = await supabase.rpc('admin_set_reference_status', { p_ref_id: row.id, p_status: next })
  busyId.value = null
  if (error) return toast.show(errorMessage(error), 'error')
  toast.show(message)
  load()
}

watch(status, () => { openId.value = null; page.value === 1 ? load() : (page.value = 1) })
let timer: ReturnType<typeof setTimeout> | undefined
watch(query, () => {
  clearTimeout(timer)
  timer = setTimeout(() => { page.value === 1 ? load() : (page.value = 1) }, 300)
})
watch(page, load)

await load()
</script>

<template>
  <AdminShell title="Ссылки" description="Ручная проверка сопоставления списков литературы со статьями в базе">
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex gap-1 overflow-x-auto" role="tablist">
        <Button
          v-for="t in TABS"
          :key="t.value"
          size="sm"
          role="tab"
          :aria-selected="status === t.value"
          :variant="status === t.value ? 'secondary' : 'ghost'"
          @click="status = t.value"
        >
          {{ t.label }}
        </Button>
      </div>
      <div class="relative sm:w-72">
        <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input v-model="query" placeholder="Поиск по тексту ссылки" class="pl-9" aria-label="Поиск по ссылкам" />
      </div>
    </div>

    <p class="text-sm text-muted-foreground">Найдено: {{ total }}</p>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
    <StateBlock v-else-if="!rows.length" state="empty" message="Здесь пусто" />

    <ul v-else class="space-y-2">
      <li v-for="r in rows" :key="r.id" class="rounded-md border">
        <div class="flex flex-col gap-3 p-3 sm:flex-row sm:items-start sm:justify-between">
          <div class="min-w-0 space-y-1 text-sm">
            <p class="break-words">{{ r.raw_text }}</p>
            <p class="text-xs text-muted-foreground">
              из статьи
              <NuxtLink v-if="r.source" :to="`/publications/${r.source.id}`" class="text-primary hover:underline">{{ r.source.title }}</NuxtLink>
              <span v-if="r.parsed_year"> · год {{ r.parsed_year }}</span>
            </p>
            <p v-if="r.matched" class="text-xs">
              → <NuxtLink :to="`/publications/${r.matched.id}`" class="text-primary hover:underline">{{ r.matched.title }}</NuxtLink>
              <Badge variant="outline" class="ml-1">{{ Math.round((r.match_score ?? 1) * 100) }}%</Badge>
            </p>
          </div>
          <div class="flex shrink-0 flex-wrap gap-1">
            <Button v-if="r.status !== 'matched'" size="sm" variant="outline" class="gap-1.5" @click="toggle(r)">
              <Link2 class="h-4 w-4" /> Привязать
            </Button>
            <Button v-if="r.status === 'matched'" size="sm" variant="outline" class="gap-1.5" :disabled="busyId === r.id" @click="setStatus(r, 'unmatched', 'Привязка снята')">
              <Unlink class="h-4 w-4" /> Отвязать
            </Button>
            <Button v-if="r.status === 'unmatched' || r.status === 'matched'" size="sm" variant="ghost" class="gap-1.5" :disabled="busyId === r.id" @click="setStatus(r, 'rejected', 'Ссылка отклонена')">
              <Ban class="h-4 w-4" /> Отклонить
            </Button>
            <Button v-if="r.status === 'rejected'" size="sm" variant="ghost" class="gap-1.5" :disabled="busyId === r.id" @click="setStatus(r, 'pending', 'Ссылка возвращена в очередь')">
              <RotateCcw class="h-4 w-4" /> В очередь
            </Button>
          </div>
        </div>

        <div v-if="openId === r.id" class="space-y-3 border-t bg-muted/30 p-3">
          <div v-if="candidates.length" class="space-y-1">
            <p class="text-xs font-medium uppercase text-muted-foreground">Похожие статьи в базе</p>
            <button
              v-for="c in candidates"
              :key="c.id"
              class="flex w-full items-center justify-between gap-3 rounded border bg-background px-3 py-2 text-left text-sm hover:bg-accent"
              :disabled="busyId === r.id"
              @click="link(r, c.id)"
            >
              <span class="min-w-0 truncate">{{ c.title }} <span class="text-muted-foreground">{{ year(c.published_date) }}</span></span>
              <Badge variant="secondary" class="shrink-0">{{ Math.round(c.score * 100) }}%</Badge>
            </button>
          </div>
          <p v-else class="text-xs text-muted-foreground">Похожих статей не найдено автоматически.</p>
          <div class="space-y-1">
            <Input v-model="manualQuery" placeholder="Найти статью по названию…" aria-label="Поиск статьи для привязки" />
            <button
              v-for="m in manualResults"
              :key="m.id"
              class="flex w-full items-center gap-2 rounded border bg-background px-3 py-2 text-left text-sm hover:bg-accent"
              :disabled="busyId === r.id || m.id === r.source?.id"
              @click="link(r, m.id)"
            >
              <span class="truncate">{{ m.title }}</span>
              <span class="shrink-0 text-muted-foreground">{{ year(m.published_date) }}</span>
            </button>
          </div>
        </div>
      </li>
    </ul>

    <AppPagination v-model:page="page" :total="total" :page-size="PAGE_SIZE" />
  </AdminShell>
</template>
