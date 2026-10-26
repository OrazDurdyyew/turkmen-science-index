<script setup lang="ts">
import type { PickedAuthor } from '~/components/AuthorPicker.vue'
import { LANGUAGES } from '~/lib/format'

export type PublicationFormValue = {
  title: string
  title_en: string
  abstract: string
  journal_id: string
  published_date: string
  doi: string
  language: string
  authors: PickedAuthor[]
}

const form = defineModel<PublicationFormValue>({ required: true })

defineProps<{ submitLabel: string; busy?: boolean; error?: string }>()
defineEmits<{ submit: []; cancel: [] }>()

const supabase = useSupabase()
const { data: journals } = await supabase.from('journals').select('id, title').order('title')
</script>

<template>
  <form class="space-y-6" @submit.prevent="$emit('submit')">
    <Card>
      <CardHeader><CardTitle class="text-lg">Основная информация</CardTitle></CardHeader>
      <CardContent class="space-y-4">
        <div class="space-y-2">
          <Label for="title">Заголовок *</Label>
          <Input id="title" v-model="form.title" placeholder="Название научной статьи" required maxlength="1000" />
        </div>
        <div class="space-y-2">
          <Label for="title_en">Заголовок на английском</Label>
          <Input id="title_en" v-model="form.title_en" placeholder="Title in English" maxlength="1000" />
        </div>
        <div class="space-y-2">
          <Label for="abstract">Аннотация</Label>
          <AppTextarea id="abstract" v-model="form.abstract" placeholder="Краткое описание статьи…" />
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-2">
            <Label for="journal">Журнал</Label>
            <AppSelect id="journal" v-model="form.journal_id">
              <option value="">Не указан</option>
              <option v-for="j in journals || []" :key="j.id" :value="j.id">{{ j.title }}</option>
            </AppSelect>
          </div>
          <div class="space-y-2">
            <Label for="date">Дата публикации</Label>
            <Input id="date" v-model="form.published_date" type="date" />
          </div>
          <div class="space-y-2">
            <Label for="doi">DOI</Label>
            <Input id="doi" v-model="form.doi" placeholder="10.xxxx/xxxxx" pattern="10\..+/.+" title="DOI начинается с 10." />
          </div>
          <div class="space-y-2">
            <Label for="language">Язык</Label>
            <AppSelect id="language" v-model="form.language">
              <option v-for="(label, code) in LANGUAGES" :key="code" :value="code">{{ label }}</option>
            </AppSelect>
          </div>
        </div>
      </CardContent>
    </Card>

    <Card>
      <CardHeader>
        <CardTitle class="text-lg">Авторы</CardTitle>
        <CardDescription>Порядок в списке — порядок авторов в статье</CardDescription>
      </CardHeader>
      <CardContent>
        <AuthorPicker v-model="form.authors" />
      </CardContent>
    </Card>

    <p v-if="error" class="text-sm text-destructive" role="alert">{{ error }}</p>

    <div class="flex gap-3">
      <Button type="submit" :disabled="busy || !form.title.trim()">{{ busy ? 'Сохранение…' : submitLabel }}</Button>
      <Button variant="outline" type="button" @click="$emit('cancel')">Отмена</Button>
    </div>
  </form>
</template>
