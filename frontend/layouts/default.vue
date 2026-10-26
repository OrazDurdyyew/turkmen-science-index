<script setup lang="ts">
import { FilePlus2, FileUp, LayoutDashboard, LogOut, Menu, Shield, User, X } from 'lucide-vue-next'
import { initials } from '~/lib/format'

const { user, profile, isAdmin, signOut } = useAuth()
const route = useRoute()

const mobileOpen = ref(false)
const userMenuOpen = ref(false)

watch(() => route.fullPath, () => {
  mobileOpen.value = false
  userMenuOpen.value = false
})

const nav = [
  { to: '/publications', label: 'Публикации' },
  { to: '/authors', label: 'Авторы' },
  { to: '/journals', label: 'Журналы' },
  { to: '/search', label: 'Поиск' },
]

const displayName = computed(() => profile.value?.full_name || user.value?.user_metadata?.full_name || user.value?.email)

const handleSignOut = async () => {
  await signOut()
  await navigateTo('/')
}
</script>

<template>
  <div class="flex min-h-screen flex-col bg-background text-foreground">
    <header class="sticky top-0 z-50 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/70">
      <div class="mx-auto flex h-14 max-w-7xl items-center justify-between gap-4 px-4">
        <div class="flex items-center gap-6">
          <NuxtLink to="/" class="flex items-center gap-2 font-bold">
            <span class="rounded bg-primary px-1.5 py-0.5 text-sm text-primary-foreground">TSI</span>
            <span class="hidden text-sm font-semibold lg:inline">TurkmenScience Index</span>
          </NuxtLink>
          <nav class="hidden items-center gap-5 text-sm md:flex">
            <NuxtLink
              v-for="item in nav"
              :key="item.to"
              :to="item.to"
              class="text-muted-foreground transition-colors hover:text-foreground"
              active-class="!text-foreground font-medium"
            >
              {{ item.label }}
            </NuxtLink>
          </nav>
        </div>

        <div class="flex items-center gap-2">
          <template v-if="user">
            <NuxtLink to="/publications/upload" class="hidden sm:block">
              <Button size="sm" variant="outline" class="gap-1.5">
                <FileUp class="h-4 w-4" /> Загрузить PDF
              </Button>
            </NuxtLink>

            <div class="relative">
              <button
                class="rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                aria-label="Меню пользователя"
                :aria-expanded="userMenuOpen"
                @click="userMenuOpen = !userMenuOpen"
              >
                <Avatar class="h-8 w-8">
                  <AvatarFallback class="text-xs">{{ initials(displayName) }}</AvatarFallback>
                </Avatar>
              </button>
              <div
                v-if="userMenuOpen"
                class="absolute right-0 top-10 z-50 w-60 rounded-md border bg-popover p-1 text-sm shadow-md"
                @mouseleave="userMenuOpen = false"
              >
                <div class="truncate px-3 py-2 text-xs text-muted-foreground">{{ displayName }}</div>
                <NuxtLink to="/dashboard" class="flex items-center gap-2 rounded px-3 py-2 hover:bg-accent">
                  <LayoutDashboard class="h-4 w-4" /> Личный кабинет
                </NuxtLink>
                <NuxtLink v-if="profile" :to="`/profile/${profile.id}`" class="flex items-center gap-2 rounded px-3 py-2 hover:bg-accent">
                  <User class="h-4 w-4" /> Мой профиль
                </NuxtLink>
                <NuxtLink to="/publications/new" class="flex items-center gap-2 rounded px-3 py-2 hover:bg-accent">
                  <FilePlus2 class="h-4 w-4" /> Добавить вручную
                </NuxtLink>
                <NuxtLink v-if="isAdmin" to="/admin" class="flex items-center gap-2 rounded px-3 py-2 hover:bg-accent">
                  <Shield class="h-4 w-4" /> Администрирование
                </NuxtLink>
                <button class="flex w-full items-center gap-2 rounded px-3 py-2 text-left hover:bg-accent" @click="handleSignOut">
                  <LogOut class="h-4 w-4" /> Выйти
                </button>
              </div>
            </div>
          </template>
          <template v-else>
            <NuxtLink to="/login"><Button size="sm" variant="ghost">Войти</Button></NuxtLink>
            <NuxtLink to="/register" class="hidden sm:block"><Button size="sm">Регистрация</Button></NuxtLink>
          </template>

          <Button
            variant="ghost"
            size="icon"
            class="h-9 w-9 md:hidden"
            :aria-label="mobileOpen ? 'Закрыть меню' : 'Открыть меню'"
            :aria-expanded="mobileOpen"
            @click="mobileOpen = !mobileOpen"
          >
            <X v-if="mobileOpen" class="h-5 w-5" />
            <Menu v-else class="h-5 w-5" />
          </Button>
        </div>
      </div>

      <nav v-if="mobileOpen" class="border-t px-4 py-2 md:hidden">
        <NuxtLink
          v-for="item in nav"
          :key="item.to"
          :to="item.to"
          class="block rounded px-2 py-2.5 text-sm hover:bg-accent"
          active-class="font-medium"
        >
          {{ item.label }}
        </NuxtLink>
        <NuxtLink v-if="user" to="/publications/upload" class="block rounded px-2 py-2.5 text-sm hover:bg-accent">
          Загрузить PDF
        </NuxtLink>
        <NuxtLink v-if="!user" to="/register" class="block rounded px-2 py-2.5 text-sm hover:bg-accent">
          Регистрация
        </NuxtLink>
      </nav>
    </header>

    <main class="mx-auto w-full max-w-7xl flex-1 px-4 py-6">
      <slot />
    </main>

    <footer class="border-t">
      <div class="mx-auto flex max-w-7xl flex-col gap-1 px-4 py-6 text-xs text-muted-foreground sm:flex-row sm:justify-between">
        <span>TurkmenScience Index — национальная система научного цитирования</span>
        <span>© {{ new Date().getFullYear() }}</span>
      </div>
    </footer>
  </div>
</template>
