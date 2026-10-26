import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2025-03-20',
  devtools: { enabled: true },
  ssr: false,

  devServer: {
    port: 3050,
    host: '0.0.0.0'
  },

  modules: [
    'shadcn-nuxt',
  ],

  shadcn: {
    prefix: '',
    componentDir: './components/ui',
  },

  vite: {
    plugins: [tailwindcss()],
  },

  css: ['~/assets/css/tailwind.css'],

  runtimeConfig: {
    public: {
      supabaseUrl: process.env.SUPABASE_URL || 'http://127.0.0.1:54321',
      supabaseKey: process.env.SUPABASE_KEY || '',
      parserUrl: process.env.PARSER_URL || 'http://localhost:8000',
    },
  },
})
