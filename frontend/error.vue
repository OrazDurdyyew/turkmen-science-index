<script setup lang="ts">
import type { NuxtError } from '#app'

const props = defineProps<{ error: NuxtError }>()

const title = computed(() => {
  if (props.error.statusCode === 404) return 'Страница не найдена'
  if (props.error.statusCode === 403) return 'Нет доступа'
  return 'Произошла ошибка'
})
</script>

<template>
  <NuxtLayout>
    <div class="flex flex-col items-center justify-center gap-4 py-24 text-center">
      <p class="text-5xl font-bold text-muted-foreground">{{ error.statusCode }}</p>
      <h1 class="text-xl font-semibold">{{ title }}</h1>
      <p v-if="error.statusMessage && error.statusCode !== 404" class="text-sm text-muted-foreground">
        {{ error.statusMessage }}
      </p>
      <Button @click="clearError({ redirect: '/' })">На главную</Button>
    </div>
  </NuxtLayout>
</template>
