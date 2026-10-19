import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import process from "node:process";

export default defineConfig(({ command }) => {
    if (command === "build") process.env.NODE_ENV = "production";

    return {
        plugins: [react()],
        base: "./",
        server: { port: 5191 },
        build: {
            outDir: "../nui",
            emptyOutDir: true,
            // FiveM's CEF is Chromium 103, so newer syntax is lowered for it
            target: "chrome103",
            cssTarget: "chrome103",
        },
    };
});
