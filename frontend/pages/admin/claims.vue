<script setup lang="ts">
import { Check, X } from 'lucide-vue-next'
import { errorMessage, formatDateTime } from '~/lib/format'

definePageMeta({ middleware: 'admin' })
useHead({ title: 'Заявки на профили · Администрирование' })

const supabase = useSupabase()
const toast = useToast()

const status = ref<'pending' | 'resolved'>('pending')
const rows = ref<any[]>([])
const claimants = ref<Record<string, any>>({})
const state = ref<'loading' | 'ready' | 'error'>('loading')
const busyId = ref<string | null>(null)

const STATUS_LABEL: Record<string, string> = {
  approved: 'одобрена',
  rejected: 'отклонена',
  merged: 'профиль объединён',
}

const load = async () => {
  state.value = 'loading'
  let req = supabase
    .from('profile_claims')
    .select('id, profile_id, profile_name, user_id, status, created_at, resolved_at, profile:profile_id(id, full_name, institution, publication_authors(count))')
    .order('created_at', { ascending: false })
    .limit(100)
  req = status.value === 'pending' ? req.eq('status', 'pending') : req.neq('status', 'pending')
  const { data, error } = await req
  if (error) {
    state.value = 'error'
    return
  }
  rows.value = data || []

  // claim.user_id is an auth user; their profile has the same user_id
  const ids = [...new Set(rows.value.map(r => r.user_id))]
  if (ids.length) {
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, user_id, full_name, institution, orcid, publication_authors(count)')
      .in('user_id', ids)
    claimants.value = Object.fromEntries((profiles || []).map(p => [p.user_id, p]))
  }
  state.value = 'ready'
}

const resolve = async (claim: any, approve: boolean) => {
  busyId.value = claim.id
  const { error } = await supabase.rpc('admin_resolve_claim', { p_claim_id: claim.id, p_approve: approve })
  busyId.value = null
  if (error) return toast.show(errorMessage(error), 'error')
  toast.show(approve ? 'Заявка одобрена, статьи перенесены' : 'Заявка отклонена')
  load()
}

watch(status, load)
await load()
</script>

<template>
  <AdminShell title="Заявки на профили" description="Пользователи просят привязать к своему аккаунту профиль, созданный из загруженных статей">
    <div class="flex gap-1">
      <Button size="sm" :variant="status === 'pending' ? 'secondary' : 'ghost'" @click="status = 'pending'">Ожидают</Button>
      <Button size="sm" :variant="status === 'resolved' ? 'secondary' : 'ghost'" @click="status = 'resolved'">Рассмотренные</Button>
    </div>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
    <StateBlock v-else-if="!rows.length" state="empty" :message="status === 'pending' ? 'Новых заявок нет' : 'Рассмотренных заявок нет'" />

    <div v-else class="space-y-3">
      <Card v-for="c in rows" :key="c.id">
        <CardContent class="grid gap-4 p-4 md:grid-cols-[1fr_auto_1fr_auto] md:items-center">
          <div class="text-sm">
            <p class="text-xs uppercase text-muted-foreground">Пользователь</p>
            <NuxtLink v-if="claimants[c.user_id]" :to="`/profile/${claimants[c.user_id].id}`" class="font-medium text-primary hover:underline">
              {{ claimants[c.user_id].full_name }}
            </NuxtLink>
            <p v-if="claimants[c.user_id]?.institution" class="text-muted-foreground">{{ claimants[c.user_id].institution }}</p>
            <p v-if="claimants[c.user_id]" class="text-xs text-muted-foreground">статей в аккаунте: {{ claimants[c.user_id].publication_authors?.[0]?.count ?? 0 }}</p>
          </div>
          <span class="hidden text-muted-foreground md:block">→</span>
          <div class="text-sm">
            <p class="text-xs uppercase text-muted-foreground">Претендует на профиль</p>
            <NuxtLink v-if="c.profile" :to="`/profile/${c.profile.id}`" class="font-medium text-primary hover:underline">{{ c.profile.full_name }}</NuxtLink>
            <p v-else class="font-medium">{{ c.profile_name }}</p>
            <p v-if="c.profile" class="text-xs text-muted-foreground">статей: {{ c.profile.publication_authors?.[0]?.count ?? 0 }}</p>
            <p class="text-xs text-muted-foreground">подана {{ formatDateTime(c.created_at) }}</p>
          </div>
          <div class="flex gap-2 md:justify-end">
            <template v-if="c.status === 'pending'">
              <Button size="sm" class="gap-1.5" :disabled="busyId === c.id" @click="resolve(c, true)"><Check class="h-4 w-4" /> Одобрить</Button>
              <Button size="sm" variant="outline" class="gap-1.5" :disabled="busyId === c.id" @click="resolve(c, false)"><X class="h-4 w-4" /> Отклонить</Button>
            </template>
            <Badge v-else :variant="c.status === 'approved' ? 'default' : 'secondary'">{{ STATUS_LABEL[c.status] || c.status }}</Badge>
          </div>
        </CardContent>
      </Card>
    </div>
  </AdminShell>
</template>
