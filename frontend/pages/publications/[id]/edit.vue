<script setup lang="ts">
import type { PublicationFormValue } from '~/components/PublicationForm.vue'
import { errorMessage } from '~/lib/format'

definePageMeta({ middleware: 'auth' })

const route = useRoute()
const supabase = useSupabase()
const { saveAuthors } = usePublicationAuthors()

const pubId = route.params.id as string
const form = ref<PublicationFormValue | null>(null)
const state = ref<'loading' | 'ready' | 'forbidden' | 'missing'>('loading')
const error = ref('')
const busy = ref(false)

const [{ data: allowed }, { data: pub }, { data: authorRows }] = await Promise.all([
  supabase.rpc('can_manage_publication', { p_publication_id: pubId }),
  supabase.from('publications').select('*').eq('id', pubId).maybeSingle(),
  supabase
    .from('publication_authors')
    .select('position, profiles(id, full_name, user_id)')
    .eq('publication_id', pubId)
    .order('position'),
])

if (!pub) {
  state.value = 'missing'
} else if (!allowed) {
  state.value = 'forbidden'
} else {
  form.value = {
    title: pub.title,
    title_en: pub.title_en || '',
    abstract: pub.abstract || '',
    journal_id: pub.journal_id || '',
    published_date: pub.published_date || '',
    doi: pub.doi || '',
    language: pub.language || 'ru',
    authors: (authorRows || [])
      .map((r: any) => r.profiles && { id: r.profiles.id, full_name: r.profiles.full_name, is_registered: !!r.profiles.user_id })
      .filter(Boolean),
  }
  state.value = 'ready'
}

const submit = async () => {
  if (!form.value) return
  error.value = ''
  busy.value = true
  try {
    const { error: updError } = await supabase
      .from('publications')
      .update({
        title: form.value.title.trim(),
        title_en: form.value.title_en.trim() || null,
        abstract: form.value.abstract.trim() || null,
        journal_id: form.value.journal_id || null,
        published_date: form.value.published_date || null,
        doi: form.value.doi.trim() || null,
        language: form.value.language,
      })
      .eq('id', pubId)
    if (updError) {
      throw updError.code === '23505' ? new Error('Статья с таким DOI уже есть в базе') : updError
    }
    await saveAuthors(pubId, form.value.authors)
    await navigateTo(`/publications/${pubId}`)
  } catch (e) {
    error.value = errorMessage(e, 'Не удалось сохранить изменения')
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="max-w-2xl">
    <h1 class="mb-6 text-2xl font-bold">Редактирование статьи</h1>
    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'missing'" state="empty" message="Статья не найдена" />
    <StateBlock v-else-if="state === 'forbidden'" state="error" message="Редактировать статью могут её авторы, добавивший её пользователь и администраторы" />
    <PublicationForm
      v-else-if="form"
      v-model="form"
      submit-label="Сохранить"
      :busy="busy"
      :error="error"
      @submit="submit"
      @cancel="navigateTo(`/publications/${pubId}`)"
    />
  </div>
</template>
