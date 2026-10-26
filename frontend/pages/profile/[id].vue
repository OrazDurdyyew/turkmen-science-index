<script setup lang="ts">
import { BadgeCheck, Pencil, UserCheck } from 'lucide-vue-next'
import { errorMessage, formatDateTime, initials } from '~/lib/format'

const route = useRoute()
const supabase = useSupabase()
const { user, profile: myProfile, isAdmin, fetchProfile } = useAuth()

const profileId = computed(() => route.params.id as string)

const profile = ref<any>(null)
const publications = ref<any[]>([])
const coauthors = ref<{ id: string; full_name: string; count: number }[]>([])
const myClaim = ref<any>(null)
const state = ref<'loading' | 'ready' | 'error'>('loading')

const editing = ref(false)
const editForm = ref({ full_name: '', full_name_en: '', institution: '', orcid: '' })
const editError = ref('')
const claimOpen = ref(false)
const claimError = ref('')
const busy = ref(false)

const isOwner = computed(() => !!user.value && profile.value?.user_id === user.value.id)
const canEdit = computed(() => isOwner.value || isAdmin.value)
const isUnclaimed = computed(() => profile.value && !profile.value.user_id)
const totalCitations = computed(() => publications.value.reduce((s, p) => s + (p.citation_count || 0), 0))

const load = async () => {
  state.value = 'loading'
  const { data, error } = await supabase.from('profiles').select('*').eq('id', profileId.value).maybeSingle()
  if (error) {
    state.value = 'error'
    return
  }
  profile.value = data
  if (!data) {
    state.value = 'ready'
    return
  }

  const { data: pubData } = await supabase
    .from('publication_authors')
    .select('publications(id, title, published_date, citation_count, journals(title), publication_authors(profiles(id, full_name)))')
    .eq('profile_id', profileId.value)

  const pubs = (pubData || []).map((pa: any) => pa.publications).filter(Boolean)
  publications.value = pubs
    .map((p: any) => ({
      ...p,
      journal_title: p.journals?.title,
      authors: p.publication_authors?.map((x: any) => x.profiles?.full_name).filter(Boolean).join(', '),
    }))
    .sort((a: any, b: any) => (b.citation_count - a.citation_count) || String(b.published_date).localeCompare(String(a.published_date)))

  const counts = new Map<string, { id: string; full_name: string; count: number }>()
  for (const p of pubs) {
    for (const x of p.publication_authors || []) {
      if (!x.profiles || x.profiles.id === profileId.value) continue
      const c = counts.get(x.profiles.id) || { ...x.profiles, count: 0 }
      c.count++
      counts.set(x.profiles.id, c)
    }
  }
  coauthors.value = [...counts.values()].sort((a, b) => b.count - a.count).slice(0, 12)

  myClaim.value = null
  if (user.value && !data.user_id) {
    const { data: claim } = await supabase
      .from('profile_claims')
      .select('id, status')
      .eq('profile_id', profileId.value)
      .eq('user_id', user.value.id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()
    myClaim.value = claim
  }

  editForm.value = {
    full_name: data.full_name || '',
    full_name_en: data.full_name_en || '',
    institution: data.institution || '',
    orcid: data.orcid || '',
  }
  state.value = 'ready'
}

const saveProfile = async () => {
  editError.value = ''
  const orcid = editForm.value.orcid.trim()
  if (orcid && !/^\d{4}-\d{4}-\d{4}-\d{3}[\dX]$/.test(orcid)) {
    editError.value = 'ORCID должен быть в формате 0000-0000-0000-0000'
    return
  }
  if (editForm.value.full_name.trim().length < 3) {
    editError.value = 'Укажите ФИО'
    return
  }
  busy.value = true
  const { error } = await supabase
    .from('profiles')
    .update({
      full_name: editForm.value.full_name.trim(),
      full_name_en: editForm.value.full_name_en.trim() || null,
      institution: editForm.value.institution.trim() || null,
      orcid: orcid || null,
    })
    .eq('id', profileId.value)
  busy.value = false
  if (error) {
    editError.value = error.code === '23505' ? 'Этот ORCID уже привязан к другому профилю' : errorMessage(error)
    return
  }
  editing.value = false
  if (isOwner.value) await fetchProfile()
  await load()
}

const submitClaim = async () => {
  claimError.value = ''
  busy.value = true
  const { error } = await supabase.from('profile_claims').insert({
    profile_id: profileId.value,
    profile_name: profile.value.full_name,
    user_id: user.value!.id,
  })
  busy.value = false
  if (error) {
    claimError.value = error.code === '23505' ? 'Заявка уже отправлена' : errorMessage(error)
    return
  }
  claimOpen.value = false
  await load()
}

useHead(() => ({ title: profile.value ? `${profile.value.full_name} — TSI` : 'Автор — TSI' }))

watch(profileId, load)
await load()
</script>

<template>
  <StateBlock v-if="state === 'loading'" state="loading" />
  <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
  <StateBlock v-else-if="!profile" state="empty" message="Профиль не найден" />

  <div v-else class="grid gap-6 lg:grid-cols-3">
    <div class="space-y-6 lg:col-span-2">
      <Card>
        <CardHeader>
          <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div class="flex items-center gap-4">
              <Avatar class="h-16 w-16 shrink-0">
                <AvatarFallback class="text-lg">{{ initials(profile.full_name) }}</AvatarFallback>
              </Avatar>
              <div class="min-w-0">
                <CardTitle class="flex items-center gap-2 text-xl">
                  {{ profile.full_name || 'Без имени' }}
                  <BadgeCheck v-if="profile.user_id" class="h-5 w-5 text-primary" aria-label="Зарегистрированный автор" />
                </CardTitle>
                <p v-if="profile.full_name_en" class="text-sm text-muted-foreground">{{ profile.full_name_en }}</p>
                <CardDescription v-if="profile.institution">{{ profile.institution }}</CardDescription>
                <a
                  v-if="profile.orcid"
                  :href="`https://orcid.org/${profile.orcid}`"
                  target="_blank"
                  rel="noopener"
                  class="mt-1 block text-xs text-primary hover:underline"
                >ORCID: {{ profile.orcid }}</a>
              </div>
            </div>
            <Button v-if="canEdit && !editing" variant="outline" size="sm" class="gap-1.5" @click="editing = true">
              <Pencil class="h-4 w-4" /> Редактировать
            </Button>
          </div>
        </CardHeader>

        <CardContent v-if="editing" class="space-y-4">
          <div class="grid gap-4 sm:grid-cols-2">
            <div class="space-y-2">
              <Label for="full_name">ФИО</Label>
              <Input id="full_name" v-model="editForm.full_name" />
            </div>
            <div class="space-y-2">
              <Label for="full_name_en">ФИО латиницей</Label>
              <Input id="full_name_en" v-model="editForm.full_name_en" placeholder="Berdyev Ahmet" />
            </div>
            <div class="space-y-2">
              <Label for="institution">Учреждение / вуз</Label>
              <Input id="institution" v-model="editForm.institution" placeholder="Туркменский государственный университет" />
            </div>
            <div class="space-y-2">
              <Label for="orcid">ORCID</Label>
              <Input id="orcid" v-model="editForm.orcid" placeholder="0000-0000-0000-0000" />
            </div>
          </div>
          <p v-if="editError" class="text-sm text-destructive" role="alert">{{ editError }}</p>
          <div class="flex gap-2">
            <Button :disabled="busy" @click="saveProfile">Сохранить</Button>
            <Button variant="outline" @click="editing = false; editError = ''">Отмена</Button>
          </div>
        </CardContent>

        <CardContent v-else>
          <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
            <div><p class="text-2xl font-bold">{{ profile.h_index }}</p><p class="text-xs text-muted-foreground">h-index</p></div>
            <div><p class="text-2xl font-bold">{{ profile.i10_index }}</p><p class="text-xs text-muted-foreground">i10-index</p></div>
            <div><p class="text-2xl font-bold">{{ publications.length }}</p><p class="text-xs text-muted-foreground">публикаций</p></div>
            <div><p class="text-2xl font-bold">{{ totalCitations }}</p><p class="text-xs text-muted-foreground">цитирований</p></div>
          </div>
          <p v-if="profile.h_index_updated_at" class="mt-3 text-xs text-muted-foreground">
            Индексы обновлены: {{ formatDateTime(profile.h_index_updated_at) }}
          </p>
        </CardContent>
      </Card>

      <div v-if="isUnclaimed" class="flex flex-col gap-3 rounded-lg border border-dashed p-4 text-sm sm:flex-row sm:items-center sm:justify-between">
        <p class="text-muted-foreground">
          Профиль создан автоматически по загруженным статьям и не привязан к аккаунту.
        </p>
        <template v-if="user && myProfile">
          <Badge v-if="myClaim?.status === 'pending'" variant="secondary">Ваша заявка на рассмотрении</Badge>
          <Badge v-else-if="myClaim?.status === 'rejected'" variant="destructive">Заявка отклонена</Badge>
          <Button v-else size="sm" class="gap-1.5" @click="claimOpen = true"><UserCheck class="h-4 w-4" /> Это я</Button>
        </template>
        <NuxtLink v-else-if="!user" :to="{ path: '/login', query: { redirect: route.fullPath } }">
          <Button size="sm" variant="outline">Войдите, если это вы</Button>
        </NuxtLink>
      </div>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Публикации</h2>
        <StateBlock v-if="!publications.length" state="empty" message="Публикаций пока нет" />
        <PublicationCard v-for="pub in publications" :key="pub.id" :publication="pub" />
      </section>
    </div>

    <aside class="space-y-3">
      <h2 class="text-lg font-semibold">Соавторы</h2>
      <p v-if="!coauthors.length" class="text-sm text-muted-foreground">Нет соавторов</p>
      <Card v-else>
        <ul class="divide-y">
          <li v-for="c in coauthors" :key="c.id">
            <NuxtLink :to="`/profile/${c.id}`" class="flex items-center justify-between gap-2 px-4 py-2.5 text-sm hover:bg-accent/50">
              <span class="truncate">{{ c.full_name }}</span>
              <span class="shrink-0 text-xs text-muted-foreground">{{ c.count }}</span>
            </NuxtLink>
          </li>
        </ul>
      </Card>
    </aside>

    <AppModal
      v-model:open="claimOpen"
      title="Привязать профиль к аккаунту?"
      :description="`После одобрения администратором статьи «${profile.full_name}» перейдут в ваш профиль, и индексы будут пересчитаны.`"
    >
      <p v-if="claimError" class="mb-3 text-sm text-destructive" role="alert">{{ claimError }}</p>
      <div class="flex justify-end gap-2">
        <Button variant="outline" @click="claimOpen = false">Отмена</Button>
        <Button :disabled="busy" @click="submitClaim">Отправить заявку</Button>
      </div>
    </AppModal>
  </div>
</template>
