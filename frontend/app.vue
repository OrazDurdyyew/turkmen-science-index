<script setup lang="ts">
useHead({
  titleTemplate: t => (t && t.includes('TSI') ? t : t ? `${t} — TSI` : 'TurkmenScience Index'),
  htmlAttrs: { lang: 'ru' },
  meta: [{ name: 'description', content: 'TurkmenScience Index — национальная система научного цитирования Туркменистана' }],
})
</script>

<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
  <AppToasts />
</template>
