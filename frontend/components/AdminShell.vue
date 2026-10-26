<script setup lang="ts">
import { BookOpen, FileText, LayoutGrid, Link2, UserCheck, Users } from 'lucide-vue-next'

defineProps<{ title: string; description?: string }>()

const items = [
  { to: '/admin', label: 'Обзор', icon: LayoutGrid, exact: true },
  { to: '/admin/publications', label: 'Публикации', icon: FileText },
  { to: '/admin/references', label: 'Ссылки', icon: Link2 },
  { to: '/admin/people', label: 'Авторы и пользователи', icon: Users },
  { to: '/admin/claims', label: 'Заявки на профили', icon: UserCheck },
  { to: '/admin/journals', label: 'Журналы', icon: BookOpen },
]

const route = useRoute()
const isActive = (item: (typeof items)[number]) =>
  item.exact ? route.path === item.to : route.path.startsWith(item.to)
</script>

<template>
  <div class="flex flex-col gap-6 lg:flex-row">
    <nav class="-mx-4 flex gap-1 overflow-x-auto border-b px-4 pb-2 lg:mx-0 lg:w-56 lg:shrink-0 lg:flex-col lg:overflow-visible lg:border-b-0 lg:border-r lg:px-0 lg:pb-0 lg:pr-4" aria-label="Администрирование">
      <p class="hidden px-3 pb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground lg:block">Администрирование</p>
      <NuxtLink
        v-for="item in items"
        :key="item.to"
        :to="item.to"
        class="flex shrink-0 items-center gap-2 whitespace-nowrap rounded-md px-3 py-2 text-sm transition-colors hover:bg-accent"
        :class="isActive(item) ? 'bg-accent font-medium' : 'text-muted-foreground'"
      >
        <component :is="item.icon" class="h-4 w-4" />
        {{ item.label }}
      </NuxtLink>
    </nav>

    <section class="min-w-0 flex-1 space-y-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 class="text-2xl font-bold">{{ title }}</h1>
          <p v-if="description" class="text-sm text-muted-foreground">{{ description }}</p>
        </div>
        <slot name="actions" />
      </div>
      <slot />
    </section>
  </div>
</template>
