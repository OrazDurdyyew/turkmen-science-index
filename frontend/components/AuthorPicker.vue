<script setup lang="ts">
import { ArrowDown, ArrowUp, BadgeCheck, Plus, X } from 'lucide-vue-next'
import { ilikePattern } from '~/lib/format'

// id === null: a new author typed by name, created on save via find_or_create_author()
export type PickedAuthor = { id: string | null; full_name: string; is_registered?: boolean }

const authors = defineModel<PickedAuthor[]>({ required: true })

const supabase = useSupabase()
const search = ref('')
const results = ref<any[]>([])
let timer: ReturnType<typeof setTimeout> | undefined
let seq = 0

watch(search, (q) => {
  clearTimeout(timer)
  if (q.trim().length < 2) {
    results.value = []
    return
  }
  timer = setTimeout(async () => {
    const mine = ++seq
    const p = ilikePattern(q)
    const { data } = await supabase
      .from('profiles')
      .select('id, full_name, institution, user_id')
      .or(`full_name.ilike.${p},full_name_en.ilike.${p}`)
      .limit(6)
    if (mine === seq) results.value = data || []
  }, 250)
})

const isPicked = (id: string) => authors.value.some(a => a.id === id)

const add = (a: PickedAuthor) => {
  if (a.id && isPicked(a.id)) return
  if (!a.id && authors.value.some(x => !x.id && x.full_name.toLowerCase() === a.full_name.toLowerCase())) return
  authors.value = [...authors.value, a]
  search.value = ''
  results.value = []
}

const remove = (i: number) => {
  authors.value = authors.value.filter((_, idx) => idx !== i)
}

const move = (i: number, dir: -1 | 1) => {
  const j = i + dir
  if (j < 0 || j >= authors.value.length) return
  const next = [...authors.value]
  ;[next[i], next[j]] = [next[j]!, next[i]!]
  authors.value = next
}

const exactMatch = computed(() =>
  results.value.some(r => r.full_name.toLowerCase() === search.value.trim().toLowerCase()),
)
</script>

<template>
  <div class="space-y-3">
    <ol v-if="authors.length" class="space-y-1.5">
      <li
        v-for="(a, i) in authors"
        :key="(a.id || 'new') + a.full_name"
        class="flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm"
      >
        <span class="w-5 text-muted-foreground">{{ i + 1 }}.</span>
        <span class="flex-1 truncate">{{ a.full_name }}</span>
        <BadgeCheck v-if="a.is_registered" class="h-4 w-4 text-primary" aria-label="Зарегистрирован" />
        <Badge v-if="!a.id" variant="outline">новый</Badge>
        <Button variant="ghost" size="icon" class="h-7 w-7" :disabled="i === 0" aria-label="Выше" @click="move(i, -1)">
          <ArrowUp class="h-3.5 w-3.5" />
        </Button>
        <Button variant="ghost" size="icon" class="h-7 w-7" :disabled="i === authors.length - 1" aria-label="Ниже" @click="move(i, 1)">
          <ArrowDown class="h-3.5 w-3.5" />
        </Button>
        <Button variant="ghost" size="icon" class="h-7 w-7" aria-label="Убрать" @click="remove(i)">
          <X class="h-3.5 w-3.5" />
        </Button>
      </li>
    </ol>

    <div class="relative">
      <Input v-model="search" placeholder="Начните вводить ФИО автора…" aria-label="Поиск автора" @keydown.enter.prevent />
      <div
        v-if="search.trim().length >= 2"
        class="absolute left-0 right-0 top-full z-20 mt-1 rounded-md border bg-popover p-1 shadow-md"
      >
        <button
          v-for="r in results"
          :key="r.id"
          type="button"
          class="flex w-full items-center gap-2 rounded px-3 py-2 text-left text-sm hover:bg-accent disabled:opacity-50"
          :disabled="isPicked(r.id)"
          @click="add({ id: r.id, full_name: r.full_name, is_registered: !!r.user_id })"
        >
          <span class="font-medium">{{ r.full_name }}</span>
          <BadgeCheck v-if="r.user_id" class="h-4 w-4 text-primary" />
          <span v-if="r.institution" class="truncate text-muted-foreground">· {{ r.institution }}</span>
        </button>
        <button
          v-if="!exactMatch"
          type="button"
          class="flex w-full items-center gap-2 rounded px-3 py-2 text-left text-sm hover:bg-accent"
          @click="add({ id: null, full_name: search.trim().replace(/\s+/g, ' ') })"
        >
          <Plus class="h-4 w-4" /> Добавить нового автора «{{ search.trim() }}»
        </button>
      </div>
    </div>
  </div>
</template>
