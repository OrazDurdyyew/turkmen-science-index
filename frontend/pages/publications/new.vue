<script setup lang="ts">
import type { PublicationFormValue } from '~/components/PublicationForm.vue'
import { errorMessage, ilikeExact } from '~/lib/format'

definePageMeta({ middleware: 'auth' })

const supabase = useSupabase()
const { profile } = useAuth()
const { saveAuthors } = usePublicationAuthors()

const form = ref<PublicationFormValue>({
  title: '',
  title_en: '',
  abstract: '',
  journal_id: '',
  published_date: '',
  doi: '',
  language: 'ru',
  // The person adding the article is usually its first author; they can remove themselves
  authors: profile.value ? [{ id: profile.value.id, full_name: profile.value.full_name, is_registered: true }] : [],
})
const error = ref('')
const duplicateId = ref<string | null>(null)
const busy = ref(false)

const submit = async () => {
  error.value = ''
  duplicateId.value = null
  busy.value = true
  try {
    const { data: existing } = await supabase
      .from('publications')
      .select('id')
      .ilike('title', ilikeExact(form.value.title))
      .limit(1)
    if (existing?.length) {
      duplicateId.value = existing[0]!.id
      throw new Error('Статья с таким названием уже есть в базе')
    }

    const { data: pub, error: pubError } = await supabase
      .from('publications')
      .insert({
        title: form.value.title.trim(),
        title_en: form.value.title_en.trim() || null,
        abstract: form.value.abstract.trim() || null,
        journal_id: form.value.journal_id || null,
        published_date: form.value.published_date || null,
        doi: form.value.doi.trim() || null,
        language: form.value.language,
      })
      .select('id')
      .single()
    if (pubError) {
      throw pubError.code === '23505' ? new Error('Статья с таким DOI уже есть в базе') : pubError
    }

    await saveAuthors(pub.id, form.value.authors)
    await navigateTo(`/publications/${pub.id}`)
  } catch (e) {
    error.value = errorMessage(e, 'Ошибка при добавлении статьи')
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="max-w-2xl">
    <h1 class="mb-1 text-2xl font-bold">Добавить статью вручную</h1>
    <p class="mb-6 text-sm text-muted-foreground">
      Есть PDF? <NuxtLink to="/publications/upload" class="text-primary hover:underline">Загрузите его</NuxtLink> —
      метаданные и список литературы распознаются автоматически.
    </p>
    <PublicationForm
      v-model="form"
      submit-label="Добавить статью"
      :busy="busy"
      :error="error"
      @submit="submit"
      @cancel="navigateTo('/publications')"
    />
    <NuxtLink v-if="duplicateId" :to="`/publications/${duplicateId}`" class="mt-2 inline-block text-sm text-primary underline">
      Открыть существующую статью
    </NuxtLink>
  </div>
</template>
