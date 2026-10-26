<script setup lang="ts">
import { type HTMLAttributes } from 'vue'
import { cn } from '~/lib/utils'

// Native <select> styled like Input — accessible and works on mobile out of the box
const model = defineModel<string>({ default: '' })
const props = defineProps<{ class?: HTMLAttributes['class'] }>()
</script>

<template>
  <select
    v-model="model"
    :class="cn('flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50', props.class)"
  >
    <slot />
  </select>
</template>
