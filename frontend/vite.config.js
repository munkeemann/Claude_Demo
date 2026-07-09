import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dashboard dev server. The backend runs separately on :8000 (see start.bat).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
  },
});
