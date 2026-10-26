<script setup lang="ts">
import { CheckCircle2, FileText, Plus, Upload, X } from 'lucide-vue-next'
import { errorMessage, LANGUAGES } from '~/lib/format'

definePageMeta({ middleware: 'auth' })

const supabase = useSupabase()
const { getAccessToken } = useAuth()
const PARSER_URL = useRuntimeConfig().public.parserUrl

type ParsedAuthor = { full_name: string; full_name_en?: string; affiliation?: string }
type Parsed = {
  title: string
  title_en: string
  abstract: string
  authors: ParsedAuthor[]
  references: { raw_text: string; title?: string; authors?: string; year?: number | null }[]
  doi: string
  date: string
  language: string
  journal_id?: string
  reference_count: number
}

const file = ref<File | null>(null)
const isDragging = ref(false)
const busy = ref(false)
const error = ref('')
const duplicateId = ref<string | null>(null)
const parsed = ref<Parsed | null>(null)
const saved = ref<{ publication_id: string; reference_count: number; uploader_is_author: boolean } | null>(null)
const step = ref<'upload' | 'preview' | 'saved'>('upload')
const newAuthor = ref('')
const showAllRefs = ref(false)

const { data: journals } = await supabase.from('journals').select('id, title').order('title')

const pick = (f: File | undefined | null) => {
  error.value = ''
  duplicateId.value = null
  if (!f) return
  if (f.type !== 'application/pdf' && !f.name.toLowerCase().endsWith('.pdf')) {
    error.value = 'Можно загружать только PDF-файлы'
    return
  }
  if (f.size > 50 * 1024 * 1024) {
    error.value = 'Файл больше 50 МБ'
    return
  }
  file.value = f
}

const onDrop = (e: DragEvent) => {
  isDragging.value = false
  pick(e.dataTransfer?.files?.[0])
}

const authHeaders = async () => {
  const token = await getAccessToken()
  if (!token) throw new Error('Сессия истекла, войдите заново')
  return { Authorization: `Bearer ${token}` }
}

const parsePdf = async () => {
  if (!file.value) return
  busy.value = true
  error.value = ''
  try {
    const body = new FormData()
    body.append('file', file.value)
    const resp = await $fetch<Parsed>(`${PARSER_URL}/parse`, { method: 'POST', body, headers: await authHeaders() })
    parsed.value = { ...resp, journal_id: '' }
    step.value = 'preview'
  } catch (e) {
    error.value = errorMessage(e, 'Не удалось распознать PDF.')
  } finally {
    busy.value = false
  }
}

const save = async () => {
  if (!parsed.value || !file.value) return
  busy.value = true
  error.value = ''
  duplicateId.value = null
  try {
    const body = new FormData()
    body.append('file', file.value)
    body.append('metadata', JSON.stringify(parsed.value))
    const url: string = `${PARSER_URL}/parse-and-save`
    saved.value = await $fetch<NonNullable<typeof saved.value>>(url, { method: 'POST', body, headers: await authHeaders() })
    step.value = 'saved'
  } catch (e: any) {
    if (e?.status === 409 || e?.response?.status === 409) {
      duplicateId.value = e.data?.detail?.publication_id ?? null
    }
    error.value = errorMessage(e, 'Не удалось сохранить статью')
  } finally {
    busy.value = false
  }
}

const addAuthor = () => {
  const name = newAuthor.value.trim().replace(/\s+/g, ' ')
  if (parsed.value && name.length >= 3) {
    parsed.value.authors.push({ full_name: name })
    newAuthor.value = ''
  }
}

const reset = () => {
  file.value = null
  parsed.value = null
  saved.value = null
  step.value = 'upload'
  error.value = ''
  duplicateId.value = null
}
</script>

<template>
  <div class="max-w-3xl space-y-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-bold">Загрузка PDF</h1>
        <p class="text-sm text-muted-foreground">
          Шаг {{ step === 'upload' ? 1 : step === 'preview' ? 2 : 3 }} из 3 ·
          {{ step === 'upload' ? 'выбор файла' : step === 'preview' ? 'проверка данных' : 'готово' }}
        </p>
      </div>
      <Button v-if="step !== 'upload'" variant="outline" @click="reset">Загрузить другой</Button>
    </div>

    <!-- Step 1 -->
    <Card v-if="step === 'upload'">
      <CardContent class="pt-6">
        <label
          class="flex cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed p-10 text-center transition-colors sm:p-12"
          :class="isDragging ? 'border-primary bg-primary/5' : 'border-muted-foreground/25 hover:border-muted-foreground/50'"
          @dragover.prevent="isDragging = true"
          @dragleave="isDragging = false"
          @drop.prevent="onDrop"
        >
          <Upload class="mb-3 h-10 w-10 text-muted-foreground" />
          <span class="text-sm font-medium">Перетащите PDF сюда или <span class="text-primary">выберите файл</span></span>
          <span class="mt-1 text-xs text-muted-foreground">PDF, до 50 МБ. Распознавание занимает до минуты.</span>
          <input type="file" accept=".pdf,application/pdf" class="sr-only" @change="pick(($event.target as HTMLInputElement).files?.[0])" />
        </label>

        <div v-if="file" class="mt-4 flex flex-col gap-3 rounded-md bg-muted p-3 sm:flex-row sm:items-center sm:justify-between">
          <div class="flex min-w-0 items-center gap-2 text-sm">
            <FileText class="h-4 w-4 shrink-0" />
            <span class="truncate font-medium">{{ file.name }}</span>
            <span class="shrink-0 text-muted-foreground">({{ (file.size / 1024 / 1024).toFixed(1) }} МБ)</span>
          </div>
          <Button :disabled="busy" @click="parsePdf">{{ busy ? 'Распознавание…' : 'Распознать' }}</Button>
        </div>

        <p v-if="error" class="mt-3 text-sm text-destructive" role="alert">{{ error }}</p>
      </CardContent>
    </Card>

    <!-- Step 2 -->
    <template v-if="step === 'preview' && parsed">
      <Card>
        <CardHeader>
          <CardTitle class="text-lg">Проверьте и при необходимости исправьте</CardTitle>
          <CardDescription>Распознавание не идеально: особенно проверьте ФИО авторов</CardDescription>
        </CardHeader>
        <CardContent class="space-y-4">
          <div class="space-y-2">
            <Label for="p-title">Заголовок *</Label>
            <Input id="p-title" v-model="parsed.title" required />
          </div>
          <div class="space-y-2">
            <Label for="p-title-en">Заголовок на английском</Label>
            <Input id="p-title-en" v-model="parsed.title_en" />
          </div>

          <div class="space-y-2">
            <Label>Авторы</Label>
            <div class="flex flex-wrap gap-2">
              <Badge v-for="(a, i) in parsed.authors" :key="i" variant="secondary" class="gap-1 py-1 pr-1">
                {{ a.full_name }}
                <span v-if="a.full_name_en" class="font-normal text-muted-foreground">/ {{ a.full_name_en }}</span>
                <button class="rounded p-0.5 hover:bg-background" :aria-label="`Убрать ${a.full_name}`" @click="parsed.authors.splice(i, 1)">
                  <X class="h-3 w-3" />
                </button>
              </Badge>
              <span v-if="!parsed.authors.length" class="text-sm text-muted-foreground">Авторы не распознаны — добавьте вручную</span>
            </div>
            <form class="flex gap-2" @submit.prevent="addAuthor">
              <Input v-model="newAuthor" placeholder="Фамилия Имя Отчество" aria-label="Добавить автора" />
              <Button type="submit" variant="outline" size="icon" aria-label="Добавить автора"><Plus class="h-4 w-4" /></Button>
            </form>
          </div>

          <div class="space-y-2">
            <Label for="p-abstract">Аннотация</Label>
            <AppTextarea id="p-abstract" v-model="parsed.abstract" />
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <div class="space-y-2">
              <Label for="p-journal">Журнал</Label>
              <AppSelect id="p-journal" v-model="parsed.journal_id">
                <option value="">Не указан</option>
                <option v-for="j in journals || []" :key="j.id" :value="j.id">{{ j.title }}</option>
              </AppSelect>
            </div>
            <div class="space-y-2">
              <Label for="p-date">Дата публикации</Label>
              <Input id="p-date" v-model="parsed.date" type="date" />
            </div>
            <div class="space-y-2">
              <Label for="p-doi">DOI</Label>
              <Input id="p-doi" v-model="parsed.doi" placeholder="10.xxxx/xxxxx" />
            </div>
            <div class="space-y-2">
              <Label for="p-lang">Язык</Label>
              <AppSelect id="p-lang" v-model="parsed.language">
                <option v-for="(label, code) in LANGUAGES" :key="code" :value="code">{{ label }}</option>
              </AppSelect>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card v-if="parsed.references.length">
        <CardHeader>
          <CardTitle class="text-lg">Список литературы ({{ parsed.references.length }})</CardTitle>
          <CardDescription>После сохранения ссылки автоматически сопоставятся со статьями в базе</CardDescription>
        </CardHeader>
        <CardContent>
          <ol class="list-inside list-decimal space-y-2 text-sm text-muted-foreground">
            <li v-for="(r, i) in showAllRefs ? parsed.references : parsed.references.slice(0, 10)" :key="i" class="break-words">
              {{ r.raw_text }}
            </li>
          </ol>
          <Button v-if="parsed.references.length > 10" variant="link" class="px-0" @click="showAllRefs = !showAllRefs">
            {{ showAllRefs ? 'Свернуть' : `Показать все (${parsed.references.length})` }}
          </Button>
        </CardContent>
      </Card>

      <p v-if="error" class="text-sm text-destructive" role="alert">
        {{ error }}
        <NuxtLink v-if="duplicateId" :to="`/publications/${duplicateId}`" class="ml-1 text-primary underline">Открыть существующую</NuxtLink>
      </p>

      <div class="flex gap-3">
        <Button :disabled="busy || !parsed.title.trim()" @click="save">{{ busy ? 'Сохранение…' : 'Сохранить в базу' }}</Button>
        <Button variant="outline" @click="reset">Отмена</Button>
      </div>
    </template>

    <!-- Step 3 -->
    <Card v-if="step === 'saved' && saved">
      <CardContent class="space-y-4 pt-6 text-center">
        <CheckCircle2 class="mx-auto h-12 w-12 text-green-600" />
        <p class="font-medium">Статья сохранена</p>
        <p class="text-sm text-muted-foreground">
          {{ saved.reference_count }} ссылок поставлено в очередь на сопоставление (запускается каждые 10 минут).
        </p>
        <p v-if="!saved.uploader_is_author" class="text-sm text-amber-700">
          Вы не найдены среди авторов статьи. Если это ваша работа — добавьте себя в разделе «Редактировать».
        </p>
        <div class="flex flex-wrap justify-center gap-3">
          <NuxtLink :to="`/publications/${saved.publication_id}`"><Button>Открыть статью</Button></NuxtLink>
          <Button variant="outline" @click="reset">Загрузить ещё</Button>
        </div>
      </CardContent>
    </Card>
  </div>
</template>
