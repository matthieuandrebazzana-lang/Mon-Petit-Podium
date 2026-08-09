import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { VitePWA } from "vite-plugin-pwa";
import { readFileSync } from "node:fs";

const { version } = JSON.parse(readFileSync("./package.json", "utf-8"));

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["apple-touch-icon.png"],
      manifest: {
        name: "Mon Petit Podium",
        short_name: "Podium",
        description: "Pronostics Formule 1 entre amis.",
        lang: "fr",
        start_url: "/",
        scope: "/",
        display: "standalone",
        orientation: "portrait",
        background_color: "#F5F0EB",
        theme_color: "#800111",
        icons: [
          { src: "pwa-192x192.png", sizes: "192x192", type: "image/png" },
          { src: "pwa-512x512.png", sizes: "512x512", type: "image/png" },
          {
            src: "pwa-maskable-512x512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable",
          },
        ],
      },
      workbox: {
        globPatterns: ["**/*.{js,css,html,svg,png,woff2}"],
        // Les appels à l'API ne doivent jamais être servis depuis le cache
        // du service worker : les cotes et les classements changent.
        navigateFallbackDenylist: [/^\/api\//],
      },
      devOptions: {
        // Permet de tester l'installation et le manifest en `npm run dev`.
        enabled: true,
        type: "module",
      },
    }),
  ],
  define: {
    __APP_VERSION__: JSON.stringify(version),
  },
});
