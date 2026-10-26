<script setup lang="ts">
import { X } from 'lucide-vue-next'

const open = defineModel<boolean>('open', { required: true })

defineProps<{ title: string; description?: string }>()

const onKey = (e: KeyboardEvent) => {
  if (e.key === 'Escape') open.value = false
}

watch(open, (v) => {
  if (v) document.addEventListener('keydown', onKey)
  else document.removeEventListener('keydown', onKey)
})

onBeforeUnmount(() => document.removeEventListener('keydown', onKey))
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-[100] flex items-end justify-center bg-black/50 p-0 sm:items-center sm:p-4"
      @mousedown.self="open = false"
    >
      <div
        class="max-h-[90vh] w-full overflow-y-auto rounded-t-lg border bg-background p-5 shadow-lg sm:max-w-lg sm:rounded-lg"
        role="dialog"
        aria-modal="true"
        :aria-label="title"
      >
        <div class="mb-4 flex items-start justify-between gap-4">
          <div>
            <h2 class="text-lg font-semibold">{{ title }}</h2>
            <p v-if="description" class="mt-1 text-sm text-muted-foreground">{{ description }}</p>
          </div>
          <Button variant="ghost" size="icon" class="h-8 w-8 shrink-0" aria-label="Закрыть" @click="open = false">
            <X class="h-4 w-4" />
          </Button>
        </div>
        <slot />
      </div>
    </div>
  </Teleport>
</template>
