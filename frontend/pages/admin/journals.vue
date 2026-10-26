<script setup lang="ts">
import { Pencil, Plus, Trash2 } from 'lucide-vue-next'
import { errorMessage } from '~/lib/format'

definePageMeta({ middleware: 'admin' })
useHead({ title: 'Журналы · Администрирование' })

type Journal = { id?: string; title: string; title_en: string; issn: string; publisher: string }

const supabase = useSupabase()
const toast = useToast()

const rows = ref<any[]>([])
const state = ref<'loading' | 'ready' | 'error'>('loading')
const editing = ref<Journal | null>(null)
const editOpen = computed({ get: () => !!editing.value, set: (v) => { if (!v) editing.value = null } })
const formError = ref('')
const toDelete = ref<any>(null)
const deleteOpen = computed({ get: () => !!toDelete.value, set: (v) => { if (!v) toDelete.value = null } })
const busy = ref(false)

const load = async () => {
  state.value = 'loading'
  const { data, error } = await supabase.rpc('journals_with_counts')
  if (error) {
    state.value = 'error'
    return
  }
  rows.value = data || []
  state.value = 'ready'
}

const openNew = () => {
  formError.value = ''
  editing.value = { title: '', title_en: '', issn: '', publisher: '' }
}

const openEdit = (j: any) => {
  formError.value = ''
  editing.value = { id: j.id, title: j.title, title_en: j.title_en || '', issn: j.issn || '', publisher: j.publisher || '' }
}

const save = async () => {
  const j = editing.value
  if (!j) return
  formError.value = ''
  const issn = j.issn.trim().toUpperCase()
  if (issn && !/^\d{4}-\d{3}[\dX]$/.test(issn)) {
    formError.value = 'ISSN в формате 1234-567X'
    return
  }
  const payload = {
    title: j.title.trim(),
    title_en: j.title_en.trim() || null,
    issn: issn || null,
    publisher: j.publisher.trim() || null,
  }
  busy.value = true
  const { error } = j.id
    ? await supabase.from('journals').update(payload).eq('id', j.id)
    : await supabase.from('journals').insert(payload)
  busy.value = false
  if (error) {
    formError.value = error.code === '23505' ? 'Журнал с таким ISSN уже есть' : errorMessage(error)
    return
  }
  toast.show(j.id ? 'Журнал обновлён' : 'Журнал добавлен')
  editing.value = null
  load()
}

const confirmDelete = async () => {
  const j = toDelete.value
  toDelete.value = null
  const { error } = await supabase.from('journals').delete().eq('id', j.id)
  if (error) return toast.show(errorMessage(error), 'error')
  toast.show('Журнал удалён')
  load()
}

await load()
</script>

<template>
  <AdminShell title="Журналы" :description="`Всего: ${rows.length}`">
    <template #actions>
      <Button class="gap-1.5" @click="openNew"><Plus class="h-4 w-4" /> Добавить журнал</Button>
    </template>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
    <StateBlock v-else-if="!rows.length" state="empty" message="Журналов пока нет" />

    <Card v-else class="overflow-x-auto">
      <table class="w-full min-w-[640px] text-sm">
        <thead class="border-b bg-muted/50 text-left text-xs uppercase text-muted-foreground">
          <tr>
            <th class="p-3 font-medium">Название</th>
            <th class="p-3 font-medium">ISSN</th>
            <th class="p-3 font-medium">Издатель</th>
            <th class="p-3 text-right font-medium">Статей</th>
            <th class="p-3" />
          </tr>
        </thead>
        <tbody class="divide-y">
          <tr v-for="j in rows" :key="j.id" class="hover:bg-muted/30">
            <td class="p-3">
              <NuxtLink :to="`/journals/${j.id}`" class="font-medium hover:underline">{{ j.title }}</NuxtLink>
              <p v-if="j.title_en" class="text-xs text-muted-foreground">{{ j.title_en }}</p>
            </td>
            <td class="whitespace-nowrap p-3">{{ j.issn || '—' }}</td>
            <td class="max-w-[14rem] truncate p-3 text-muted-foreground">{{ j.publisher || '—' }}</td>
            <td class="p-3 text-right">{{ j.publication_count }}</td>
            <td class="p-3">
              <div class="flex justify-end gap-1">
                <Button variant="ghost" size="icon" class="h-8 w-8" aria-label="Редактировать" @click="openEdit(j)"><Pencil class="h-4 w-4" /></Button>
                <Button variant="ghost" size="icon" class="h-8 w-8 text-destructive hover:text-destructive" aria-label="Удалить" @click="toDelete = j">
                  <Trash2 class="h-4 w-4" />
                </Button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </Card>

    <AppModal v-model:open="editOpen" :title="editing?.id ? 'Редактировать журнал' : 'Новый журнал'">
      <form v-if="editing" class="space-y-4" @submit.prevent="save">
        <div class="space-y-2">
          <Label for="j-title">Название *</Label>
          <Input id="j-title" v-model="editing.title" required />
        </div>
        <div class="space-y-2">
          <Label for="j-title-en">Название на английском</Label>
          <Input id="j-title-en" v-model="editing.title_en" />
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-2">
            <Label for="j-issn">ISSN</Label>
            <Input id="j-issn" v-model="editing.issn" placeholder="1234-567X" maxlength="9" />
          </div>
          <div class="space-y-2">
            <Label for="j-pub">Издатель</Label>
            <Input id="j-pub" v-model="editing.publisher" />
          </div>
        </div>
        <p v-if="formError" class="text-sm text-destructive" role="alert">{{ formError }}</p>
        <div class="flex justify-end gap-2">
          <Button variant="outline" @click="editing = null">Отмена</Button>
          <Button type="submit" :disabled="busy || !editing.title.trim()">Сохранить</Button>
        </div>
      </form>
    </AppModal>

    <AppModal v-model:open="deleteOpen" title="Удалить журнал?" :description="toDelete?.title">
      <p class="mb-4 text-sm text-muted-foreground">
        Статьи журнала ({{ toDelete?.publication_count ?? 0 }}) останутся в базе, но без указания журнала.
      </p>
      <div class="flex justify-end gap-2">
        <Button variant="outline" @click="toDelete = null">Отмена</Button>
        <Button variant="destructive" @click="confirmDelete">Удалить</Button>
      </div>
    </AppModal>
  </AdminShell>
</template>
