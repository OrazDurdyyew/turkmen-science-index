<script setup lang="ts">
definePageMeta({ layout: 'auth', middleware: 'guest' })

const { signIn } = useAuth()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref('')
const isLoading = ref(false)

// Only same-site paths, never an absolute URL from the query string
const redirectTo = computed(() => {
  const r = route.query.redirect
  return typeof r === 'string' && r.startsWith('/') && !r.startsWith('//') ? r : '/dashboard'
})

const handleLogin = async () => {
  error.value = ''
  isLoading.value = true
  try {
    await signIn(email.value.trim(), password.value)
    await navigateTo(redirectTo.value)
  } catch (e: any) {
    error.value = e?.message === 'Invalid login credentials' ? 'Неверный email или пароль' : e?.message || 'Ошибка входа'
  } finally {
    isLoading.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center px-4">
    <Card class="w-full max-w-md">
      <CardHeader class="text-center">
        <NuxtLink to="/" class="mx-auto mb-2 rounded bg-primary px-2 py-0.5 text-sm font-bold text-primary-foreground">TSI</NuxtLink>
        <CardTitle>Вход в TSI</CardTitle>
        <CardDescription>Введите email и пароль</CardDescription>
      </CardHeader>
      <CardContent>
        <form class="space-y-4" @submit.prevent="handleLogin">
          <div class="space-y-2">
            <Label for="email">Email</Label>
            <Input id="email" v-model="email" type="email" autocomplete="email" placeholder="user@example.com" required />
          </div>
          <div class="space-y-2">
            <Label for="password">Пароль</Label>
            <Input id="password" v-model="password" type="password" autocomplete="current-password" required />
          </div>
          <p v-if="error" class="text-sm text-destructive" role="alert">{{ error }}</p>
          <Button type="submit" class="w-full" :disabled="isLoading">{{ isLoading ? 'Вход…' : 'Войти' }}</Button>
        </form>
      </CardContent>
      <CardFooter class="flex-col gap-2">
        <p class="text-sm text-muted-foreground">
          Нет аккаунта?
          <NuxtLink :to="{ path: '/register', query: route.query }" class="text-primary hover:underline">Зарегистрироваться</NuxtLink>
        </p>
        <NuxtLink to="/" class="text-xs text-muted-foreground hover:underline">← На главную</NuxtLink>
      </CardFooter>
    </Card>
  </div>
</template>
