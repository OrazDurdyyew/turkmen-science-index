<script setup lang="ts">
import { AlertCircle, Inbox, Loader2 } from 'lucide-vue-next'

// One component for the three non-content states of a list or page
defineProps<{
  state: 'loading' | 'empty' | 'error'
  message?: string
}>()

defineEmits<{ retry: [] }>()
</script>

<template>
  <div class="flex flex-col items-center justify-center gap-3 py-16 text-center text-muted-foreground" role="status">
    <Loader2 v-if="state === 'loading'" class="h-6 w-6 animate-spin" />
    <Inbox v-else-if="state === 'empty'" class="h-8 w-8" />
    <AlertCircle v-else class="h-8 w-8 text-destructive" />
    <p class="text-sm">
      {{ message || (state === 'loading' ? 'Загрузка…' : state === 'empty' ? 'Здесь пока ничего нет' : 'Не удалось загрузить данные') }}
    </p>
    <Button v-if="state === 'error'" variant="outline" size="sm" @click="$emit('retry')">
      Повторить
    </Button>
    <slot />
  </div>
</template>
