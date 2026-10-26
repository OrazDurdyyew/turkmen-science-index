<script setup lang="ts">
import { plural } from '~/lib/format'

const supabase = useSupabase()
const journals = ref<any[]>([])
const state = ref<'loading' | 'ready' | 'error'>('loading')

const load = async () => {
  state.value = 'loading'
  const { data, error } = await supabase.rpc('journals_with_counts')
  if (error) {
    state.value = 'error'
    return
  }
  journals.value = data || []
  state.value = 'ready'
}

await load()
</script>

<template>
  <div class="space-y-6">
    <h1 class="text-2xl font-bold">Журналы</h1>

    <StateBlock v-if="state === 'loading'" state="loading" />
    <StateBlock v-else-if="state === 'error'" state="error" @retry="load" />
    <StateBlock v-else-if="!journals.length" state="empty" message="Журналы пока не добавлены" />

    <div v-else class="grid gap-3 sm:grid-cols-2">
      <NuxtLink v-for="j in journals" :key="j.id" :to="`/journals/${j.id}`" class="block">
        <Card class="h-full transition-colors hover:bg-accent/50">
          <CardHeader class="p-4">
            <CardTitle class="text-base leading-snug">{{ j.title }}</CardTitle>
            <CardDescription>
              <span v-if="j.title_en">{{ j.title_en }}</span>
              <span v-if="j.issn"> · ISSN {{ j.issn }}</span>
            </CardDescription>
          </CardHeader>
          <CardContent class="flex gap-4 px-4 pb-4 pt-0 text-sm">
            <span><strong>{{ j.publication_count }}</strong> {{ plural(Number(j.publication_count), 'статья', 'статьи', 'статей') }}</span>
            <span><strong>{{ j.citation_count }}</strong> цит.</span>
          </CardContent>
        </Card>
      </NuxtLink>
    </div>
  </div>
</template>
