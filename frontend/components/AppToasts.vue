<script setup lang="ts">
const { toasts } = useToast()
</script>

<template>
  <div class="pointer-events-none fixed inset-x-0 bottom-4 z-[200] flex flex-col items-center gap-2 px-4" aria-live="polite">
    <div
      v-for="t in toasts"
      :key="t.id"
      class="pointer-events-auto max-w-md rounded-md px-4 py-2.5 text-sm shadow-lg"
      :class="t.kind === 'error' ? 'bg-destructive text-destructive-foreground' : 'bg-foreground text-background'"
      :role="t.kind === 'error' ? 'alert' : 'status'"
    >
      {{ t.text }}
    </div>
  </div>
</template>
