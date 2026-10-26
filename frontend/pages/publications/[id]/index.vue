<script setup lang="ts">
import { Download, ExternalLink, Pencil, Trash2 } from 'lucide-vue-next'
import { errorMessage, formatDate, LANGUAGES, plural, year } from '~/lib/format'

const route = useRoute()
const supabase = useSupabase()
const { user, isAdmin } = useAuth()

const pubId = computed(() => route.params.id as string)

const publication = ref<any>(null)
const authors = ref<any[]>([])
const citedBy = ref<any[]>([])
const refs = ref<any[]>([])
const canManage = ref(false)
const state = ref<'loading' | 'ready' | 'error'>('loading')
const refFilter = ref<'all' | 'matched'>('all')
const deleteOpen = ref(false)
const actionError = ref('')

const load = async () => {
  state.value = 'loading'
  const { data: pub, error } = await supabase
    .from('publications')
    .select('*, journals(id, title, issn)')
    .eq('id', pubId.value)
    .maybeSingle()
  if (error) {
    state.value = 'error'
    return
  }
  publication.value = pub
  if (!pub) {
    state.value = 'ready'
    return
  }

  const [authorRes, citRes, refRes, manageRes] = await Promise.all([
    supabase
      .from('publication_authors')
      .select('position, profiles(id, full_name, institution, user_id)')
      .eq('publication_id', pubId.value)
      .order('position'),
    supabase
      .from('citations')
      .select('id, source:source_publication_id(id, title, published_date)')
      .eq('target_publication_id', pubId.value)
      .limit(200),
    supabase
      .from('raw_references')
      .select('id, raw_text, status, match_score, matched:matched_publication_id(id, title)')
      .eq('source_publication_id', pubId.value)
      .order('created_at'),
    user.value ? supabase.rpc('can_manage_publication', { p_publication_id: pubId.value }) : Promise.resolve({ data: false }),
  ])

  authors.value = authorRes.data?.map((pa: any) => pa.profiles).filter(Boolean) || []
  citedBy.value = (citRes.data || []).filter((c: any) => c.source)
  refs.value = refRes.data || []
  canManage.value = !!manageRes.data
  state.value = 'ready'
}

const visibleRefs = computed(() =>
  refFilter.value === 'matched' ? refs.value.filter(r => r.status === 'matched') : refs.value,
)
const matchedCount = computed(() => refs.value.filter(r => r.status === 'matched').length)

const downloadPdf = async () => {
  actionError.value = ''
  const { data, error } = await supabase.storage
    .from('papers')
    .createSignedUrl(publication.value.pdf_path, 60)
  if (error || !data) {
    actionError.value = 'Не удалось получить файл'
    return
  }
  window.open(data.signedUrl, '_blank', 'noopener')
}

const remove = async () => {
  actionError.value = ''
  // The PDF first: storage policy lets the creator delete it only while the publication exists
  const path = publication.value.pdf_path
  if (path) await supabase.storage.from('papers').remove([path])
  const { error } = await supabase.from('publications').delete().eq('id', pubId.value)
  if (error) {
    actionError.value = errorMessage(error, 'Не удалось удалить статью')
    deleteOpen.value = false
    return
  }
  await navigateTo('/publications')
}

const refBadge = (r: any) => {
  if (r.status === 'matched') return { text: `${Math.round((r.match_score ?? 1) * 100)}%`, variant: 'default' as const }
  if (r.status === 'pending') return { text: 'в очереди', variant: 'secondary' as const }
  return { text: 'нет в базе', variant: 'outline' as const }
}

useHead(() => ({ title: publication.value ? `${publication.value.title} — TSI` : 'Статья — TSI' }))

watch(pubId, load)
await load()
</script>

<template>
  <StateBlock v-if="state === 'loading'" state="loading" />
  <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
  <StateBlock v-else-if="!publication" state="empty" message="Статья не найдена">
    <NuxtLink to="/publications"><Button variant="outline" size="sm">К списку публикаций</Button></NuxtLink>
  </StateBlock>

  <article v-else class="max-w-3xl space-y-6">
    <header class="space-y-3">
      <h1 class="text-2xl font-bold leading-tight">{{ publication.title }}</h1>
      <p v-if="publication.title_en" class="text-muted-foreground">{{ publication.title_en }}</p>

      <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
        <span v-for="(author, i) in authors" :key="author.id">
          <NuxtLink :to="`/profile/${author.id}`" class="text-primary hover:underline">{{ author.full_name }}</NuxtLink><span
            v-if="i < authors.length - 1"
            class="text-muted-foreground"
          >,</span>
        </span>
        <span v-if="!authors.length" class="text-muted-foreground">Авторы не указаны</span>
      </div>

      <div class="flex flex-wrap gap-2">
        <NuxtLink v-if="publication.journals" :to="`/journals/${publication.journals.id}`">
          <Badge variant="outline" class="hover:bg-accent">{{ publication.journals.title }}</Badge>
        </NuxtLink>
        <Badge v-if="publication.published_date" variant="outline" :title="formatDate(publication.published_date)">
          {{ year(publication.published_date) }}
        </Badge>
        <Badge v-if="publication.language" variant="outline">{{ LANGUAGES[publication.language] || publication.language }}</Badge>
        <Badge variant="secondary">
          {{ publication.citation_count }} {{ plural(publication.citation_count, 'цитирование', 'цитирования', 'цитирований') }}
        </Badge>
      </div>

      <div class="flex flex-wrap gap-2 pt-1">
        <Button v-if="publication.pdf_path && user" size="sm" variant="outline" class="gap-1.5" @click="downloadPdf">
          <Download class="h-4 w-4" /> PDF
        </Button>
        <p v-else-if="publication.pdf_path" class="text-xs text-muted-foreground">
          <NuxtLink :to="{ path: '/login', query: { redirect: route.fullPath } }" class="text-primary hover:underline">Войдите</NuxtLink>, чтобы скачать PDF
        </p>
        <a v-if="publication.doi" :href="`https://doi.org/${publication.doi}`" target="_blank" rel="noopener">
          <Button size="sm" variant="outline" class="gap-1.5"><ExternalLink class="h-4 w-4" /> DOI: {{ publication.doi }}</Button>
        </a>
        <NuxtLink v-if="canManage" :to="`/publications/${publication.id}/edit`">
          <Button size="sm" variant="outline" class="gap-1.5"><Pencil class="h-4 w-4" /> Редактировать</Button>
        </NuxtLink>
        <Button
          v-if="isAdmin || (user && publication.created_by === user.id)"
          size="sm"
          variant="ghost"
          class="gap-1.5 text-destructive hover:text-destructive"
          @click="deleteOpen = true"
        >
          <Trash2 class="h-4 w-4" /> Удалить
        </Button>
      </div>
      <p v-if="actionError" class="text-sm text-destructive" role="alert">{{ actionError }}</p>
    </header>

    <Separator />

    <section v-if="publication.abstract" class="space-y-2">
      <h2 class="text-lg font-semibold">Аннотация</h2>
      <p class="whitespace-pre-line text-sm leading-relaxed">{{ publication.abstract }}</p>
    </section>

    <section class="space-y-3">
      <h2 class="text-lg font-semibold">Цитируется в ({{ citedBy.length }})</h2>
      <p v-if="!citedBy.length" class="text-sm text-muted-foreground">
        Пока ни одна статья в системе не ссылается на эту работу.
      </p>
      <NuxtLink
        v-for="cit in citedBy"
        :key="cit.id"
        :to="`/publications/${cit.source.id}`"
        class="block rounded-md border p-3 text-sm transition-colors hover:bg-accent/50"
      >
        <span class="font-medium">{{ cit.source.title }}</span>
        <span v-if="cit.source.published_date" class="text-muted-foreground"> · {{ year(cit.source.published_date) }}</span>
      </NuxtLink>
    </section>

    <section v-if="refs.length" class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h2 class="text-lg font-semibold">Список литературы ({{ refs.length }})</h2>
        <div class="flex gap-1 text-sm">
          <Button size="sm" :variant="refFilter === 'all' ? 'secondary' : 'ghost'" @click="refFilter = 'all'">Все</Button>
          <Button size="sm" :variant="refFilter === 'matched' ? 'secondary' : 'ghost'" @click="refFilter = 'matched'">
            Найдены в TSI ({{ matchedCount }})
          </Button>
        </div>
      </div>
      <ol class="space-y-2">
        <li v-for="r in visibleRefs" :key="r.id" class="flex items-start gap-3 rounded-md border p-3 text-sm">
          <Badge :variant="refBadge(r).variant" class="mt-0.5 shrink-0">{{ refBadge(r).text }}</Badge>
          <div class="min-w-0 space-y-1">
            <p class="break-words text-muted-foreground">{{ r.raw_text }}</p>
            <NuxtLink v-if="r.matched" :to="`/publications/${r.matched.id}`" class="block text-primary hover:underline">
              → {{ r.matched.title }}
            </NuxtLink>
          </div>
        </li>
      </ol>
    </section>

    <AppModal v-model:open="deleteOpen" title="Удалить статью?" description="Статья, её авторство, список литературы и цитирования будут удалены без возможности восстановления.">
      <div class="flex justify-end gap-2">
        <Button variant="outline" @click="deleteOpen = false">Отмена</Button>
        <Button variant="destructive" @click="remove">Удалить</Button>
      </div>
    </AppModal>
  </article>
</template>
