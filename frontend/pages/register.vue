<script setup lang="ts">
definePageMeta({ layout: 'auth', middleware: 'guest' })

const { signUp } = useAuth()

const fullName = ref('')
const email = ref('')
const password = ref('')
const error = ref('')
const isLoading = ref(false)
const needsConfirmation = ref(false)

const handleRegister = async () => {
  error.value = ''
  if (fullName.value.trim().split(/\s+/).length < 2) {
    error.value = 'Укажите фамилию и имя полностью — так вас будет проще связать с вашими статьями'
    return
  }
  isLoading.value = true
  try {
    const data = await signUp(email.value.trim(), password.value, fullName.value.trim().replace(/\s+/g, ' '))
    if (data.session) {
      await navigateTo('/dashboard')
    } else {
      needsConfirmation.value = true
    }
  } catch (e: any) {
    error.value = e?.message === 'User already registered' ? 'Пользователь с таким email уже зарегистрирован' : e?.message || 'Ошибка регистрации'
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
        <CardTitle>Регистрация</CardTitle>
        <CardDescription>Создайте аккаунт в TurkmenScience Index</CardDescription>
      </CardHeader>
      <CardContent>
        <div v-if="needsConfirmation" class="space-y-4 text-center">
          <p class="text-sm text-muted-foreground">Мы отправили письмо на {{ email }}. Подтвердите адрес, затем войдите.</p>
          <NuxtLink to="/login"><Button variant="outline">Перейти ко входу</Button></NuxtLink>
        </div>
        <form v-else class="space-y-4" @submit.prevent="handleRegister">
          <div class="space-y-2">
            <Label for="fullName">ФИО</Label>
            <Input id="fullName" v-model="fullName" autocomplete="name" placeholder="Бердыев Ахмет Гурбанович" required />
            <p class="text-xs text-muted-foreground">В том виде, как оно указано в ваших статьях: Фамилия Имя Отчество</p>
          </div>
          <div class="space-y-2">
            <Label for="email">Email</Label>
            <Input id="email" v-model="email" type="email" autocomplete="email" placeholder="user@example.com" required />
          </div>
          <div class="space-y-2">
            <Label for="password">Пароль</Label>
            <Input id="password" v-model="password" type="password" autocomplete="new-password" placeholder="Минимум 6 символов" minlength="6" required />
          </div>
          <p v-if="error" class="text-sm text-destructive" role="alert">{{ error }}</p>
          <Button type="submit" class="w-full" :disabled="isLoading">{{ isLoading ? 'Регистрация…' : 'Зарегистрироваться' }}</Button>
        </form>
      </CardContent>
      <CardFooter class="flex-col gap-2">
        <p class="text-sm text-muted-foreground">
          Уже есть аккаунт? <NuxtLink to="/login" class="text-primary hover:underline">Войти</NuxtLink>
        </p>
        <NuxtLink to="/" class="text-xs text-muted-foreground hover:underline">← На главную</NuxtLink>
      </CardFooter>
    </Card>
  </div>
</template>
