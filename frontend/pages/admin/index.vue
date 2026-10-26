<script setup lang="ts">
import { Calculator, RefreshCw } from 'lucide-vue-next'
import { errorMessage, formatDateTime } from '~/lib/format'

definePageMeta({ middleware: 'admin' })
useHead({ title: 'Администрирование' })

const supabase = useSupabase()
const toast = useToast()

const stats = ref<Record<string, any> | null>(null)
const state = ref<'loading' | 'ready' | 'error'>('loading')
const running = ref<'' | 'matching' | 'hindex'>('')

const load = async () => {
  state.value = 'loading'
  const { data, error } = await supabase.rpc('admin_stats')
  if (error) {
    state.value = 'error'
    return
  }
  stats.value = data as Record<string, any>
  state.value = 'ready'
}

const runMatching = async () => {
  running.value = 'matching'
  const { data, error } = await supabase.rpc('run_matching')
  running.value = ''
  if (error) return toast.show(errorMessage(error), 'error')
  const r = data as { matched: number; pending: number }
  toast.show(`Обработано ссылок: ${r.pending}, найдено совпадений: ${r.matched}`)
  load()
}

const runHIndex = async () => {
  running.value = 'hindex'
  const { data, error } = await supabase.rpc('run_h_index_update')
  running.value = ''
  if (error) return toast.show(errorMessage(error), 'error')
  toast.show(`Пересчитано профилей: ${(data as any).profiles_updated}`)
  load()
}

const cards = computed(() => {
  const s = stats.value
  if (!s) return []
  return [
    { label: 'Публикаций', value: s.publications, to: '/admin/publications' },
    { label: 'Профилей авторов', value: s.profiles, hint: `из них с аккаунтом: ${s.registered_users}`, to: '/admin/people' },
    { label: 'Журналов', value: s.journals, to: '/admin/journals' },
    { label: 'Цитирований', value: s.citations },
    { label: 'Ссылок без совпадения', value: s.refs_unmatched, to: '/admin/references' },
    { label: 'Заявок на профили', value: s.claims_pending, to: '/admin/claims', highlight: s.claims_pending > 0 },
  ]
})

const refTotal = computed(() => {
  const s = stats.value
  return s ? s.refs_pending + s.refs_matched + s.refs_unmatched + s.refs_rejected : 0
})

await load()
</script>

<template>
  <AdminShell title="Обзор" description="Состояние базы и фоновых задач">
    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />

    <template v-else-if="stats">
      <div class="grid grid-cols-2 gap-3 md:grid-cols-3">
        <component
          :is="c.to ? resolveComponent('NuxtLink') : 'div'"
          v-for="c in cards"
          :key="c.label"
          :to="c.to"
          class="block"
        >
          <Card class="h-full p-4 transition-colors" :class="[c.to && 'hover:bg-accent/50', c.highlight && 'border-primary']">
            <p class="text-2xl font-bold">{{ c.value }}</p>
            <p class="text-sm text-muted-foreground">{{ c.label }}</p>
            <p v-if="c.hint" class="text-xs text-muted-foreground">{{ c.hint }}</p>
          </Card>
        </component>
      </div>

      <Card>
        <CardHeader>
          <CardTitle class="text-lg">Сопоставление ссылок</CardTitle>
          <CardDescription>Автоматически каждые 10 минут. Последний запуск: {{ formatDateTime(stats.last_matching) }}</CardDescription>
        </CardHeader>
        <CardContent class="space-y-4">
          <div v-if="refTotal" class="flex h-3 overflow-hidden rounded-full bg-muted" aria-hidden="true">
            <div class="bg-primary" :style="{ width: `${(stats.refs_matched / refTotal) * 100}%` }" />
            <div class="bg-amber-400" :style="{ width: `${(stats.refs_pending / refTotal) * 100}%` }" />
            <div class="bg-muted-foreground/30" :style="{ width: `${(stats.refs_unmatched / refTotal) * 100}%` }" />
          </div>
          <div class="flex flex-wrap gap-x-5 gap-y-1 text-sm">
            <span><span class="mr-1.5 inline-block h-2.5 w-2.5 rounded-full bg-primary" />Найдено: {{ stats.refs_matched }}</span>
            <span><span class="mr-1.5 inline-block h-2.5 w-2.5 rounded-full bg-amber-400" />В очереди: {{ stats.refs_pending }}</span>
            <span><span class="mr-1.5 inline-block h-2.5 w-2.5 rounded-full bg-muted-foreground/30" />Нет в базе: {{ stats.refs_unmatched }}</span>
            <span class="text-muted-foreground">Отклонено: {{ stats.refs_rejected }}</span>
          </div>
          <Button variant="outline" class="gap-1.5" :disabled="!!running" @click="runMatching">
            <RefreshCw class="h-4 w-4" :class="running === 'matching' && 'animate-spin'" /> Запустить сейчас
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle class="text-lg">Индекс Хирша</CardTitle>
          <CardDescription>Автоматически раз в час. Последний пересчёт: {{ formatDateTime(stats.last_h_index) }}</CardDescription>
        </CardHeader>
        <CardContent>
          <Button variant="outline" class="gap-1.5" :disabled="!!running" @click="runHIndex">
            <Calculator class="h-4 w-4" /> Пересчитать сейчас
          </Button>
        </CardContent>
      </Card>
    </template>
  </AdminShell>
</template>
