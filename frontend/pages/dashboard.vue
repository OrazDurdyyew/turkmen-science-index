<script setup lang="ts">
import { FilePlus2, FileUp } from 'lucide-vue-next'
import { formatDateTime } from '~/lib/format'

definePageMeta({ middleware: 'auth' })

const supabase = useSupabase()
const { profile } = useAuth()

const publications = ref<any[]>([])
const claims = ref<any[]>([])
const state = ref<'loading' | 'ready' | 'error'>('loading')

const totalCitations = computed(() => publications.value.reduce((s, p) => s + (p.citation_count || 0), 0))

const load = async () => {
  if (!profile.value) return
  state.value = 'loading'
  const [pubRes, claimRes] = await Promise.all([
    supabase
      .from('publication_authors')
      .select('publications(id, title, published_date, citation_count, language, journals(title))')
      .eq('profile_id', profile.value.id),
    supabase
      .from('profile_claims')
      .select('id, profile_id, profile_name, status, created_at')
      .order('created_at', { ascending: false }),
  ])
  if (pubRes.error || claimRes.error) {
    state.value = 'error'
    return
  }
  publications.value = (pubRes.data || [])
    .map((pa: any) => pa.publications && { ...pa.publications, journal_title: pa.publications.journals?.title })
    .filter(Boolean)
    .sort((a: any, b: any) => (b.citation_count - a.citation_count) || String(b.published_date).localeCompare(String(a.published_date)))
  claims.value = claimRes.data || []
  state.value = 'ready'
}

const claimStatus: Record<string, string> = {
  pending: 'на рассмотрении',
  approved: 'одобрена',
  rejected: 'отклонена',
  merged: 'профиль объединён',
}

watch(profile, load, { immediate: true })
</script>

<template>
  <div class="space-y-8">
    <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 class="text-2xl font-bold">Личный кабинет</h1>
        <p class="text-muted-foreground">{{ profile?.full_name }}</p>
      </div>
      <div class="flex gap-2">
        <NuxtLink to="/publications/upload"><Button class="gap-1.5"><FileUp class="h-4 w-4" /> Загрузить PDF</Button></NuxtLink>
        <NuxtLink to="/publications/new"><Button variant="outline" class="gap-1.5"><FilePlus2 class="h-4 w-4" /> Вручную</Button></NuxtLink>
      </div>
    </div>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />

    <template v-else>
      <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Card class="p-4"><p class="text-3xl font-bold">{{ publications.length }}</p><p class="text-sm text-muted-foreground">публикаций</p></Card>
        <Card class="p-4"><p class="text-3xl font-bold">{{ totalCitations }}</p><p class="text-sm text-muted-foreground">цитирований</p></Card>
        <Card class="p-4"><p class="text-3xl font-bold">{{ profile?.h_index ?? 0 }}</p><p class="text-sm text-muted-foreground">h-index</p></Card>
        <Card class="p-4"><p class="text-3xl font-bold">{{ profile?.i10_index ?? 0 }}</p><p class="text-sm text-muted-foreground">i10-index</p></Card>
      </div>
      <p class="text-xs text-muted-foreground">
        Индексы пересчитываются автоматически раз в час.
        <template v-if="profile?.h_index_updated_at">Последний пересчёт: {{ formatDateTime(profile.h_index_updated_at) }}</template>
      </p>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Мои публикации</h2>
        <StateBlock v-if="!publications.length" state="empty" message="У вас пока нет публикаций">
          <p class="max-w-md text-xs">
            Загрузите PDF — авторы и список литературы распознаются автоматически.
            Если ваши статьи уже есть в системе под профилем без аккаунта, откройте этот профиль и нажмите «Это я».
          </p>
        </StateBlock>
        <PublicationCard v-for="pub in publications" :key="pub.id" :publication="pub" />
      </section>

      <section v-if="claims.length" class="space-y-3">
        <h2 class="text-xl font-semibold">Заявки на профили</h2>
        <Card>
          <ul class="divide-y">
            <li v-for="c in claims" :key="c.id" class="flex flex-wrap items-center justify-between gap-2 p-4 text-sm">
              <NuxtLink v-if="c.profile_id" :to="`/profile/${c.profile_id}`" class="font-medium hover:underline">{{ c.profile_name }}</NuxtLink>
              <span v-else class="font-medium">{{ c.profile_name }}</span>
              <Badge :variant="c.status === 'approved' ? 'default' : c.status === 'rejected' ? 'destructive' : 'secondary'">
                {{ claimStatus[c.status] || c.status }}
              </Badge>
            </li>
          </ul>
        </Card>
      </section>
    </template>
  </div>
</template>
