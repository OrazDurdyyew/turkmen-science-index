<script setup lang="ts">
import {
  ArrowRight, BookOpen, Building2, CheckCircle2, ChevronDown, Clock, FileText, FileUp, GraduationCap,
  Link2, Quote, ScanText, Search, ShieldCheck, TrendingUp, UserCheck, Users,
} from 'lucide-vue-next'

useHead({ title: 'TurkmenScience Index — национальная система научного цитирования' })

const supabase = useSupabase()
const { user } = useAuth()

const query = ref('')
const stats = ref<{ publications: number; authors: number; journals: number; citations: number } | null>(null)
const recent = ref<any[]>([])
const topAuthors = ref<any[]>([])
const state = ref<'loading' | 'ready' | 'error'>('loading')

const load = async () => {
  state.value = 'loading'
  const [statsRes, recentRes, authorsRes] = await Promise.all([
    supabase.rpc('public_stats'),
    supabase.rpc('search_publications', { p_query: '', p_limit: 4, p_sort: 'date' }),
    supabase.rpc('search_authors', { p_query: '', p_limit: 6 }),
  ])
  if (statsRes.error || recentRes.error || authorsRes.error) {
    state.value = 'error'
    return
  }
  stats.value = statsRes.data as any
  recent.value = recentRes.data || []
  topAuthors.value = authorsRes.data || []
  state.value = 'ready'
}

const submit = () => {
  if (query.value.trim()) navigateTo({ path: '/search', query: { q: query.value.trim() } })
}

const statItems = computed(() => stats.value
  ? [
      { label: 'публикаций', value: stats.value.publications, to: '/publications' },
      { label: 'авторов', value: stats.value.authors, to: '/authors' },
      { label: 'журналов', value: stats.value.journals, to: '/journals' },
      { label: 'цитирований', value: stats.value.citations, to: '/publications?sort=citations' },
    ]
  : [])

const steps = [
  {
    icon: FileUp,
    title: 'Загрузка PDF',
    text: 'Автор или редакция журнала загружает статью в формате PDF. Можно добавить статью и вручную, если файла нет.',
  },
  {
    icon: ScanText,
    title: 'Распознавание',
    text: 'Система извлекает название, авторов, аффилиации, аннотацию, DOI и весь список литературы. Перед сохранением всё можно проверить и поправить.',
  },
  {
    icon: Link2,
    title: 'Сопоставление ссылок',
    text: 'Каждая ссылка из списка литературы сравнивается со статьями в базе. Если цитируемая работа найдена, между статьями появляется связь-цитирование.',
  },
  {
    icon: TrendingUp,
    title: 'Метрики',
    text: 'У статей растёт число цитирований, у авторов пересчитываются h-index и i10-index. Профиль автора обновляется автоматически.',
  },
]

const indexing = [
  {
    icon: Users,
    title: 'Профиль у каждого автора',
    text: 'Все авторы из загруженных статей сразу получают профиль — даже без регистрации. Публикации разных лет собираются в одном месте по ФИО.',
  },
  {
    icon: Search,
    title: 'Нечёткое сравнение',
    text: 'Ссылки оформлены по-разному: с сокращениями, опечатками, транслитерацией. Поэтому названия сравниваются по сходству, а не дословно, и дополнительно проверяется год издания.',
  },
  {
    icon: Clock,
    title: 'Индекс обновляется сам',
    text: 'Новые ссылки сопоставляются каждые 10 минут, метрики пересчитываются каждый час. Если сегодня загрузили статью, на которую ссылались раньше, — старые ссылки найдут её.',
  },
  {
    icon: ShieldCheck,
    title: 'Проверка человеком',
    text: 'Спорные случаи разбирают администраторы: привязывают ссылки, которые система не узнала, отвязывают ошибочные, объединяют дубли авторов.',
  },
]

const guide = [
  { title: 'Найдите себя', text: 'Введите своё ФИО в поиске. Если ваши статьи уже загружал журнал или соавтор, профиль у вас уже есть.' },
  { title: 'Зарегистрируйтесь', text: 'Регистрация бесплатна. После входа появится личный кабинет с вашими метриками.' },
  { title: 'Нажмите «Это я»', text: 'На странице найденного профиля отправьте заявку. После проверки администратором профиль и все его статьи станут вашими.' },
  { title: 'Загрузите статьи', text: 'Добавьте недостающие публикации через «Загрузить PDF». Проверьте распознанные данные и сохраните.' },
]

const audiences = [
  { icon: GraduationCap, title: 'Исследователям', text: 'Видеть, кто и где цитирует ваши работы, и подтверждать научный вклад h-index из национальной базы.' },
  { icon: BookOpen, title: 'Журналам', text: 'Индексировать выпуски целиком: загрузить PDF всех статей номера — и журнал появится в каталоге с цитируемостью.' },
  { icon: Building2, title: 'Организациям', text: 'Оценивать публикационную активность сотрудников и находить экспертов по теме среди авторов страны.' },
]

const faq = [
  {
    q: 'Что такое h-index?',
    a: 'Число h, при котором у автора есть h статей, процитированных не менее h раз каждая. Например, h-index 5 означает: у автора есть 5 статей, на каждую из которых сослались минимум 5 раз.',
  },
  {
    q: 'Что такое i10-index?',
    a: 'Количество статей автора, у которых 10 и более цитирований.',
  },
  {
    q: 'Какие статьи учитываются?',
    a: 'Научные статьи на туркменском, русском и английском языках. Цитирования считаются только между статьями, которые есть в TSI, поэтому чем больше журналов загружено, тем точнее метрики.',
  },
  {
    q: 'Я загрузил статью, а цитирований нет. Почему?',
    a: 'Цитирование появляется, когда в базе есть статья, в списке литературы которой упомянута ваша. Ссылки сопоставляются автоматически каждые 10 минут, так что новые связи появятся без вашего участия.',
  },
  {
    q: 'Система неправильно распознала название или авторов',
    a: 'Перед сохранением все поля можно отредактировать. Уже сохранённую статью может исправить тот, кто её загрузил, или администратор.',
  },
  {
    q: 'Мои статьи оказались в двух разных профилях',
    a: 'Так бывает, если ФИО записано по-разному. Сообщите администратору — профили объединяются вместе с публикациями и метриками.',
  },
]

await load()
</script>

<template>
  <div class="space-y-20 pb-8 sm:space-y-28">
    <!-- Hero -->
    <section class="relative overflow-hidden rounded-2xl border bg-gradient-to-br from-primary/10 via-background to-background px-5 py-12 sm:px-10 sm:py-16 lg:py-20">
      <div class="pointer-events-none absolute -right-24 -top-24 h-72 w-72 rounded-full bg-primary/10 blur-3xl" />
      <div class="relative grid items-center gap-12 lg:grid-cols-[1.15fr_1fr]">
        <div class="min-w-0">
          <span class="inline-flex items-center gap-1.5 rounded-full border bg-background/80 px-3 py-1 text-xs font-medium text-muted-foreground">
            <span class="h-1.5 w-1.5 rounded-full bg-primary" /> Национальный индекс научного цитирования
          </span>
          <h1 class="mt-5 text-3xl font-bold leading-tight tracking-tight sm:text-5xl">
            Вся наука Туркменистана
            <span class="block text-primary">в одном индексе</span>
          </h1>
          <p class="mt-5 max-w-xl text-base text-muted-foreground sm:text-lg">
            TSI собирает научные статьи отечественных журналов, сам находит, кто на кого ссылается,
            и считает цитирования, h-index и i10-index для каждого автора.
          </p>
          <form class="mt-8 flex max-w-xl flex-col gap-2 sm:flex-row" @submit.prevent="submit">
            <div class="relative flex-1">
              <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input v-model="query" placeholder="Статья, автор или ключевые слова…" class="h-11 bg-background pl-9" aria-label="Поиск" />
            </div>
            <Button type="submit" class="h-11 px-6">Найти</Button>
          </form>
          <div class="mt-5 flex flex-wrap gap-x-5 gap-y-2 text-sm">
            <NuxtLink v-if="!user" to="/register" class="inline-flex items-center gap-1 font-medium text-primary hover:underline">
              Создать профиль автора <ArrowRight class="h-4 w-4" />
            </NuxtLink>
            <NuxtLink v-else to="/publications/upload" class="inline-flex items-center gap-1 font-medium text-primary hover:underline">
              Загрузить статью <ArrowRight class="h-4 w-4" />
            </NuxtLink>
            <a href="#how" class="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground">
              Как это работает <ChevronDown class="h-4 w-4" />
            </a>
          </div>
        </div>

        <!-- Illustration: a parsed article whose reference was matched -->
        <div class="relative mx-auto w-full max-w-md pb-8" aria-hidden="true">
          <div class="rounded-xl border bg-card p-5 pb-8 shadow-xl shadow-primary/5">
            <div class="flex items-center gap-2 text-xs text-muted-foreground">
              <FileText class="h-4 w-4 text-primary" /> statya.pdf · распознано
            </div>
            <p class="mt-3 font-semibold leading-snug">Влияние засоления почв на урожайность хлопчатника</p>
            <p class="mt-1 text-sm text-muted-foreground">Аманов Б. Б., Оразова Г. К.</p>
            <div class="mt-4 space-y-2 border-t pt-4 text-xs">
              <p class="font-medium text-muted-foreground">Список литературы · 18 ссылок</p>
              <div class="flex items-start gap-2 rounded-md bg-primary/5 p-2.5">
                <CheckCircle2 class="mt-0.5 h-4 w-4 shrink-0 text-primary" />
                <span><span class="font-medium">Найдено в TSI:</span> Мелиорация засолённых земель Ахалского велаята, 2024</span>
              </div>
              <div class="flex items-start gap-2 rounded-md p-2.5 text-muted-foreground">
                <Quote class="mt-0.5 h-4 w-4 shrink-0" />
                <span>Ковда В. А. Основы учения о почвах. — М.: Наука, 1973</span>
              </div>
            </div>
          </div>
          <div class="absolute bottom-0 -left-2 flex items-center gap-3 rounded-xl border bg-card px-4 py-3 shadow-lg sm:-left-8">
            <TrendingUp class="h-5 w-5 text-primary" />
            <div class="text-xs">
              <p class="text-muted-foreground">h-index автора</p>
              <p class="text-lg font-bold leading-none">4 → 5</p>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Live stats -->
    <section v-if="stats" class="grid grid-cols-2 gap-3 md:grid-cols-4">
      <NuxtLink
        v-for="item in statItems"
        :key="item.label"
        :to="item.to"
        class="rounded-xl border bg-card p-5 text-center transition-colors hover:border-primary/40 hover:bg-accent/40"
      >
        <p class="text-3xl font-bold tracking-tight sm:text-4xl">{{ item.value.toLocaleString('ru-RU') }}</p>
        <p class="mt-1 text-sm text-muted-foreground">{{ item.label }} в индексе</p>
      </NuxtLink>
    </section>

    <!-- How it works -->
    <section id="how" class="scroll-mt-20">
      <div class="mx-auto max-w-2xl text-center">
        <p class="text-sm font-semibold uppercase tracking-wider text-primary">Как это работает</p>
        <h2 class="mt-2 text-2xl font-bold tracking-tight sm:text-3xl">От PDF до индекса Хирша — за четыре шага</h2>
        <p class="mt-3 text-muted-foreground">Ручного ввода почти нет: всё, что можно извлечь из статьи, система извлекает сама.</p>
      </div>
      <ol class="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <li v-for="(step, i) in steps" :key="step.title" class="relative rounded-xl border bg-card p-6">
          <div class="flex items-center justify-between">
            <div class="flex h-11 w-11 items-center justify-center rounded-lg bg-primary/10 text-primary">
              <component :is="step.icon" class="h-5 w-5" />
            </div>
            <span class="text-4xl font-bold text-muted-foreground/20">{{ i + 1 }}</span>
          </div>
          <h3 class="mt-4 font-semibold">{{ step.title }}</h3>
          <p class="mt-2 text-sm leading-relaxed text-muted-foreground">{{ step.text }}</p>
        </li>
      </ol>
    </section>

    <!-- Indexing details -->
    <section class="grid gap-10 lg:grid-cols-[1fr_1.6fr] lg:gap-16">
      <div>
        <p class="text-sm font-semibold uppercase tracking-wider text-primary">Индексирование</p>
        <h2 class="mt-2 text-2xl font-bold tracking-tight sm:text-3xl">Как TSI находит цитирования</h2>
        <p class="mt-4 text-muted-foreground">
          Главная задача индекса — понять, что строка «Аманов Б.Б. Мелиорация… // Наука и техника. 2024. № 3»
          в одной статье и статья в другом журнале — одна и та же работа. Вот как это устроено.
        </p>
        <div class="mt-6 rounded-xl border bg-muted/40 p-5 text-sm">
          <p class="font-medium">Пример сопоставления</p>
          <p class="mt-3 text-muted-foreground">Ссылка в статье:</p>
          <p class="mt-1 font-mono text-xs leading-relaxed">Аманов Б. Мелиорация засоленных земель Ахалского велаята // Наука и техника в Туркменистане. — 2024. — № 3.</p>
          <p class="mt-3 text-muted-foreground">Статья в базе:</p>
          <p class="mt-1 font-mono text-xs leading-relaxed">Мелиорация засолённых земель Ахалского велаята · 2024</p>
          <p class="mt-3 inline-flex items-center gap-1.5 font-medium text-primary">
            <CheckCircle2 class="h-4 w-4" /> Название совпадает, год совпадает — цитирование засчитано
          </p>
        </div>
      </div>
      <div class="grid gap-4 sm:grid-cols-2">
        <div v-for="item in indexing" :key="item.title" class="rounded-xl border bg-card p-6">
          <component :is="item.icon" class="h-6 w-6 text-primary" />
          <h3 class="mt-4 font-semibold">{{ item.title }}</h3>
          <p class="mt-2 text-sm leading-relaxed text-muted-foreground">{{ item.text }}</p>
        </div>
      </div>
    </section>

    <!-- Author guide -->
    <section class="rounded-2xl border bg-card px-5 py-10 sm:px-10 sm:py-14">
      <div class="grid gap-10 lg:grid-cols-[1fr_1.6fr] lg:gap-16">
        <div>
          <div class="flex h-11 w-11 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <UserCheck class="h-5 w-5" />
          </div>
          <h2 class="mt-4 text-2xl font-bold tracking-tight sm:text-3xl">Инструкция для автора</h2>
          <p class="mt-3 text-muted-foreground">
            Возможно, ваш профиль уже есть: он создаётся автоматически, как только в TSI загружают статью с вашим именем.
          </p>
          <div class="mt-6 flex flex-wrap gap-2">
            <NuxtLink v-if="!user" to="/register"><Button>Зарегистрироваться</Button></NuxtLink>
            <NuxtLink v-else to="/dashboard"><Button>Личный кабинет</Button></NuxtLink>
            <NuxtLink to="/search?tab=authors"><Button variant="outline">Найти свой профиль</Button></NuxtLink>
          </div>
        </div>
        <ol class="space-y-6">
          <li v-for="(item, i) in guide" :key="item.title" class="flex gap-4">
            <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-sm font-semibold text-primary-foreground">{{ i + 1 }}</span>
            <div>
              <h3 class="font-semibold">{{ item.title }}</h3>
              <p class="mt-1 text-sm leading-relaxed text-muted-foreground">{{ item.text }}</p>
            </div>
          </li>
        </ol>
      </div>
    </section>

    <!-- Audiences -->
    <section>
      <div class="mx-auto max-w-2xl text-center">
        <p class="text-sm font-semibold uppercase tracking-wider text-primary">Для кого</p>
        <h2 class="mt-2 text-2xl font-bold tracking-tight sm:text-3xl">Кому полезен TSI</h2>
      </div>
      <div class="mt-10 grid gap-4 md:grid-cols-3">
        <div v-for="item in audiences" :key="item.title" class="rounded-xl border bg-card p-6">
          <component :is="item.icon" class="h-6 w-6 text-primary" />
          <h3 class="mt-4 font-semibold">{{ item.title }}</h3>
          <p class="mt-2 text-sm leading-relaxed text-muted-foreground">{{ item.text }}</p>
        </div>
      </div>
    </section>

    <!-- Live content -->
    <section v-if="state === 'loading'"><StateBlock state="loading" /></section>
    <section v-else-if="state === 'error'"><StateBlock state="error" @retry="load" /></section>
    <section v-else-if="recent.length || topAuthors.length" class="grid gap-8 lg:grid-cols-3">
      <div class="min-w-0 space-y-3 lg:col-span-2">
        <div class="flex items-center justify-between">
          <h2 class="text-xl font-semibold">Недавно в индексе</h2>
          <NuxtLink to="/publications" class="text-sm text-primary hover:underline">Все публикации →</NuxtLink>
        </div>
        <PublicationCard v-for="pub in recent" :key="pub.id" :publication="pub" />
      </div>
      <div class="min-w-0 space-y-3 self-start">
        <div class="flex items-center justify-between">
          <h2 class="text-xl font-semibold">Ведущие авторы</h2>
          <NuxtLink to="/authors" class="text-sm text-primary hover:underline">Все →</NuxtLink>
        </div>
        <AuthorCard v-for="a in topAuthors" :key="a.id" :author="a" />
      </div>
    </section>

    <!-- FAQ -->
    <section class="mx-auto max-w-3xl">
      <h2 class="text-center text-2xl font-bold tracking-tight sm:text-3xl">Частые вопросы</h2>
      <div class="mt-8 divide-y rounded-xl border bg-card">
        <details v-for="item in faq" :key="item.q" class="group px-5 py-4">
          <summary class="flex cursor-pointer list-none items-center justify-between gap-4 font-medium [&::-webkit-details-marker]:hidden">
            {{ item.q }}
            <ChevronDown class="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" />
          </summary>
          <p class="mt-3 text-sm leading-relaxed text-muted-foreground">{{ item.a }}</p>
        </details>
      </div>
    </section>

    <!-- CTA -->
    <section class="rounded-2xl bg-primary px-6 py-12 text-center text-primary-foreground sm:py-16">
      <h2 class="text-2xl font-bold tracking-tight sm:text-3xl">Добавьте свои работы в национальный индекс</h2>
      <p class="mx-auto mt-3 max-w-xl text-primary-foreground/80">
        Загрузите PDF — остальное TSI сделает сам: распознает статью, найдёт цитирования и посчитает метрики.
      </p>
      <div class="mt-8 flex flex-wrap justify-center gap-3">
        <NuxtLink :to="user ? '/publications/upload' : '/register'">
          <Button variant="secondary" size="lg" class="gap-2">
            <FileUp class="h-4 w-4" /> {{ user ? 'Загрузить PDF' : 'Начать бесплатно' }}
          </Button>
        </NuxtLink>
        <NuxtLink to="/publications">
          <Button size="lg" variant="outline" class="border-primary-foreground/30 bg-transparent text-primary-foreground hover:bg-primary-foreground/10 hover:text-primary-foreground">
            Смотреть каталог
          </Button>
        </NuxtLink>
      </div>
    </section>
  </div>
</template>
