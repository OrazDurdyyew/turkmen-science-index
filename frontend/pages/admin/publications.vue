<script setup lang="ts">
import { ExternalLink, Pencil, Search, Trash2 } from 'lucide-vue-next'
import { errorMessage, formatDateTime, ilikePattern, year } from '~/lib/format'

definePageMeta({ middleware: 'admin' })
useHead({ title: 'Публикации · Администрирование' })

const PAGE_SIZE = 25

const supabase = useSupabase()
const toast = useToast()

const query = ref('')
const page = ref(1)
const rows = ref<any[]>([])
const total = ref(0)
const state = ref<'loading' | 'ready' | 'error'>('loading')
const toDelete = ref<any>(null)
const deleteOpen = computed({ get: () => !!toDelete.value, set: (v) => { if (!v) toDelete.value = null } })

const load = async () => {
  state.value = 'loading'
  let req = supabase
    .from('publications')
    .select('id, title, published_date, citation_count, created_at, pdf_path, journals(title), publication_authors(count), raw_references!raw_references_source_publication_id_fkey(count)', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE - 1)
  const q = query.value.trim()
  if (q) {
    req = /^[0-9a-f-]{36}$/i.test(q) ? req.eq('id', q) : req.or(`title.ilike.${ilikePattern(q)},doi.ilike.${ilikePattern(q)}`)
  }
  const { data, error, count } = await req
  if (error) {
    state.value = 'error'
    return
  }
  rows.value = data || []
  total.value = count || 0
  state.value = 'ready'
}

const confirmDelete = async () => {
  const pub = toDelete.value
  toDelete.value = null
  const { error } = await supabase.from('publications').delete().eq('id', pub.id)
  if (error) return toast.show(errorMessage(error, 'Не удалось удалить'), 'error')
  // Admins may delete any PDF, so removing it after the row is fine here
  if (pub.pdf_path) await supabase.storage.from('papers').remove([pub.pdf_path])
  toast.show('Статья удалена')
  load()
}

let timer: ReturnType<typeof setTimeout> | undefined
watch(query, () => {
  clearTimeout(timer)
  timer = setTimeout(() => { page.value === 1 ? load() : (page.value = 1) }, 300)
})
watch(page, load)

await load()
</script>

<template>
  <AdminShell title="Публикации" :description="`Всего: ${total}`">
    <div class="relative max-w-md">
      <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
      <Input v-model="query" placeholder="Название, DOI или id" class="pl-9" aria-label="Поиск публикаций" />
    </div>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
    <StateBlock v-else-if="!rows.length" state="empty" message="Ничего не найдено" />

    <Card v-else class="overflow-x-auto">
      <table class="w-full min-w-[720px] text-sm">
        <thead class="border-b bg-muted/50 text-left text-xs uppercase text-muted-foreground">
          <tr>
            <th class="p-3 font-medium">Название</th>
            <th class="p-3 font-medium">Год</th>
            <th class="p-3 text-right font-medium">Авторы</th>
            <th class="p-3 text-right font-medium">Ссылки</th>
            <th class="p-3 text-right font-medium">Цит.</th>
            <th class="p-3 font-medium">Добавлена</th>
            <th class="p-3" />
          </tr>
        </thead>
        <tbody class="divide-y">
          <tr v-for="p in rows" :key="p.id" class="hover:bg-muted/30">
            <td class="max-w-md p-3">
              <p class="line-clamp-2 font-medium">{{ p.title }}</p>
              <p v-if="p.journals" class="truncate text-xs text-muted-foreground">{{ p.journals.title }}</p>
            </td>
            <td class="p-3">{{ year(p.published_date) || '—' }}</td>
            <td class="p-3 text-right">{{ p.publication_authors?.[0]?.count ?? 0 }}</td>
            <td class="p-3 text-right">{{ p.raw_references?.[0]?.count ?? 0 }}</td>
            <td class="p-3 text-right">{{ p.citation_count }}</td>
            <td class="whitespace-nowrap p-3 text-xs text-muted-foreground">{{ formatDateTime(p.created_at) }}</td>
            <td class="p-3">
              <div class="flex justify-end gap-1">
                <NuxtLink :to="`/publications/${p.id}`"><Button variant="ghost" size="icon" class="h-8 w-8" aria-label="Открыть"><ExternalLink class="h-4 w-4" /></Button></NuxtLink>
                <NuxtLink :to="`/publications/${p.id}/edit`"><Button variant="ghost" size="icon" class="h-8 w-8" aria-label="Редактировать"><Pencil class="h-4 w-4" /></Button></NuxtLink>
                <Button variant="ghost" size="icon" class="h-8 w-8 text-destructive hover:text-destructive" aria-label="Удалить" @click="toDelete = p">
                  <Trash2 class="h-4 w-4" />
                </Button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </Card>

    <AppPagination v-model:page="page" :total="total" :page-size="PAGE_SIZE" />

    <AppModal v-model:open="deleteOpen" title="Удалить статью?" :description="toDelete?.title">
      <p class="mb-4 text-sm text-muted-foreground">Будут удалены авторство, список литературы, PDF и все цитирования этой статьи.</p>
      <div class="flex justify-end gap-2">
        <Button variant="outline" @click="toDelete = null">Отмена</Button>
        <Button variant="destructive" @click="confirmDelete">Удалить</Button>
      </div>
    </AppModal>
  </AdminShell>
</template>
