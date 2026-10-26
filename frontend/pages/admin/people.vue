<script setup lang="ts">
import { BadgeCheck, ExternalLink, GitMerge, Search, Shield, Trash2 } from 'lucide-vue-next'
import { errorMessage, ilikePattern } from '~/lib/format'

definePageMeta({ middleware: 'admin' })
useHead({ title: 'Авторы и пользователи · Администрирование' })

const PAGE_SIZE = 25

const supabase = useSupabase()
const toast = useToast()
const { profile: me } = useAuth()

const filter = ref<'all' | 'registered' | 'unclaimed' | 'admins'>('all')
const query = ref('')
const page = ref(1)
const rows = ref<any[]>([])
const total = ref(0)
const state = ref<'loading' | 'ready' | 'error'>('loading')

const mergeSource = ref<any>(null)
const mergeQuery = ref('')
const mergeResults = ref<any[]>([])
const mergeTarget = ref<any>(null)
const mergeOpen = computed({ get: () => !!mergeSource.value, set: (v) => { if (!v) mergeSource.value = null } })
const toDelete = ref<any>(null)
const deleteOpen = computed({ get: () => !!toDelete.value, set: (v) => { if (!v) toDelete.value = null } })
const busy = ref(false)

const load = async () => {
  state.value = 'loading'
  let req = supabase
    .from('profiles')
    .select('id, full_name, full_name_en, institution, user_id, role, h_index, created_at, publication_authors(count)', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE - 1)
  if (filter.value === 'registered') req = req.not('user_id', 'is', null)
  if (filter.value === 'unclaimed') req = req.is('user_id', null)
  if (filter.value === 'admins') req = req.eq('role', 'admin')
  const q = query.value.trim()
  if (q) req = req.or(`full_name.ilike.${ilikePattern(q)},full_name_en.ilike.${ilikePattern(q)},institution.ilike.${ilikePattern(q)}`)
  const { data, error, count } = await req
  if (error) {
    state.value = 'error'
    return
  }
  rows.value = data || []
  total.value = count || 0
  state.value = 'ready'
}

const toggleAdmin = async (p: any) => {
  const role = p.role === 'admin' ? 'user' : 'admin'
  const { error } = await supabase.from('profiles').update({ role }).eq('id', p.id)
  if (error) return toast.show(errorMessage(error), 'error')
  toast.show(role === 'admin' ? `${p.full_name} — теперь администратор` : `${p.full_name} — больше не администратор`)
  load()
}

const startMerge = (p: any) => {
  mergeSource.value = p
  mergeQuery.value = p.full_name.split(' ')[0] || ''
  mergeTarget.value = null
}

let mergeTimer: ReturnType<typeof setTimeout> | undefined
watch(mergeQuery, (q) => {
  clearTimeout(mergeTimer)
  if (q.trim().length < 2) {
    mergeResults.value = []
    return
  }
  mergeTimer = setTimeout(async () => {
    const p = ilikePattern(q)
    const { data } = await supabase
      .from('profiles')
      .select('id, full_name, full_name_en, institution, user_id')
      .or(`full_name.ilike.${p},full_name_en.ilike.${p}`)
      .neq('id', mergeSource.value?.id ?? '')
      .limit(8)
    mergeResults.value = data || []
  }, 250)
})

const confirmMerge = async () => {
  if (!mergeSource.value || !mergeTarget.value) return
  busy.value = true
  const { error } = await supabase.rpc('merge_profiles', { p_source: mergeSource.value.id, p_target: mergeTarget.value.id })
  busy.value = false
  if (error) return toast.show(errorMessage(error), 'error')
  toast.show(`Профиль «${mergeSource.value.full_name}» объединён с «${mergeTarget.value.full_name}»`)
  mergeSource.value = null
  load()
}

const confirmDelete = async () => {
  const p = toDelete.value
  toDelete.value = null
  const { error } = await supabase.from('profiles').delete().eq('id', p.id)
  if (error) return toast.show(errorMessage(error), 'error')
  toast.show('Профиль удалён')
  load()
}

watch(filter, () => { page.value === 1 ? load() : (page.value = 1) })
let timer: ReturnType<typeof setTimeout> | undefined
watch(query, () => {
  clearTimeout(timer)
  timer = setTimeout(() => { page.value === 1 ? load() : (page.value = 1) }, 300)
})
watch(page, load)

await load()
</script>

<template>
  <AdminShell title="Авторы и пользователи" :description="`Профилей: ${total}`">
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex gap-1 overflow-x-auto">
        <Button
          v-for="f in ([['all', 'Все'], ['registered', 'С аккаунтом'], ['unclaimed', 'Без аккаунта'], ['admins', 'Администраторы']] as const)"
          :key="f[0]"
          size="sm"
          :variant="filter === f[0] ? 'secondary' : 'ghost'"
          @click="filter = f[0]"
        >
          {{ f[1] }}
        </Button>
      </div>
      <div class="relative sm:w-72">
        <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input v-model="query" placeholder="ФИО или учреждение" class="pl-9" aria-label="Поиск профилей" />
      </div>
    </div>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
    <StateBlock v-else-if="!rows.length" state="empty" message="Ничего не найдено" />

    <Card v-else class="overflow-x-auto">
      <table class="w-full min-w-[720px] text-sm">
        <thead class="border-b bg-muted/50 text-left text-xs uppercase text-muted-foreground">
          <tr>
            <th class="p-3 font-medium">ФИО</th>
            <th class="p-3 font-medium">Учреждение</th>
            <th class="p-3 text-right font-medium">Статей</th>
            <th class="p-3 text-right font-medium">h</th>
            <th class="p-3 font-medium">Статус</th>
            <th class="p-3" />
          </tr>
        </thead>
        <tbody class="divide-y">
          <tr v-for="p in rows" :key="p.id" class="hover:bg-muted/30">
            <td class="p-3">
              <p class="font-medium">{{ p.full_name || '—' }}</p>
              <p v-if="p.full_name_en" class="text-xs text-muted-foreground">{{ p.full_name_en }}</p>
            </td>
            <td class="max-w-[16rem] truncate p-3 text-muted-foreground">{{ p.institution || '—' }}</td>
            <td class="p-3 text-right">{{ p.publication_authors?.[0]?.count ?? 0 }}</td>
            <td class="p-3 text-right">{{ p.h_index }}</td>
            <td class="p-3">
              <div class="flex flex-wrap gap-1">
                <Badge v-if="p.role === 'admin'" class="gap-1"><Shield class="h-3 w-3" /> админ</Badge>
                <Badge v-if="p.user_id" variant="secondary" class="gap-1"><BadgeCheck class="h-3 w-3" /> аккаунт</Badge>
                <Badge v-else variant="outline">без аккаунта</Badge>
              </div>
            </td>
            <td class="p-3">
              <div class="flex justify-end gap-1">
                <NuxtLink :to="`/profile/${p.id}`"><Button variant="ghost" size="icon" class="h-8 w-8" aria-label="Открыть профиль"><ExternalLink class="h-4 w-4" /></Button></NuxtLink>
                <Button
                  v-if="p.user_id && p.id !== me?.id"
                  variant="ghost"
                  size="sm"
                  class="h-8"
                  @click="toggleAdmin(p)"
                >
                  {{ p.role === 'admin' ? 'Снять админа' : 'Сделать админом' }}
                </Button>
                <Button v-if="!p.user_id" variant="ghost" size="icon" class="h-8 w-8" aria-label="Объединить с другим профилем" title="Объединить с другим профилем" @click="startMerge(p)">
                  <GitMerge class="h-4 w-4" />
                </Button>
                <Button v-if="!p.user_id" variant="ghost" size="icon" class="h-8 w-8 text-destructive hover:text-destructive" aria-label="Удалить" @click="toDelete = p">
                  <Trash2 class="h-4 w-4" />
                </Button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </Card>

    <AppPagination v-model:page="page" :total="total" :page-size="PAGE_SIZE" />

    <AppModal
      v-model:open="mergeOpen"
      title="Объединить профили"
      :description="`Все статьи профиля «${mergeSource?.full_name}» перейдут в выбранный профиль, а этот профиль будет удалён.`"
    >
      <div class="space-y-3">
        <Input v-model="mergeQuery" placeholder="Найти основной профиль…" aria-label="Поиск основного профиля" />
        <div class="max-h-64 space-y-1 overflow-y-auto">
          <button
            v-for="r in mergeResults"
            :key="r.id"
            class="flex w-full items-center gap-2 rounded border px-3 py-2 text-left text-sm hover:bg-accent"
            :class="mergeTarget?.id === r.id && 'border-primary bg-accent'"
            @click="mergeTarget = r"
          >
            <span class="font-medium">{{ r.full_name }}</span>
            <BadgeCheck v-if="r.user_id" class="h-4 w-4 text-primary" />
            <span class="truncate text-muted-foreground">{{ r.full_name_en || r.institution }}</span>
          </button>
        </div>
        <div class="flex justify-end gap-2">
          <Button variant="outline" @click="mergeSource = null">Отмена</Button>
          <Button :disabled="!mergeTarget || busy" @click="confirmMerge">Объединить</Button>
        </div>
      </div>
    </AppModal>

    <AppModal v-model:open="deleteOpen" title="Удалить профиль?" :description="toDelete?.full_name">
      <p class="mb-4 text-sm text-muted-foreground">
        Профиль будет удалён вместе с авторством во всех статьях ({{ toDelete?.publication_authors?.[0]?.count ?? 0 }}).
        Если это дубль — лучше объединить его с основным профилем.
      </p>
      <div class="flex justify-end gap-2">
        <Button variant="outline" @click="toDelete = null">Отмена</Button>
        <Button variant="destructive" @click="confirmDelete">Удалить</Button>
      </div>
    </AppModal>
  </AdminShell>
</template>
