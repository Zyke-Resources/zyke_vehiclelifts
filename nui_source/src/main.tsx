import { createRoot } from "react-dom/client";
import App from "./App";
import "./page.css";

const start = async () => {
    // Outside the game a mock sends the panel the power unit would. The mocks in dev/ stay out of git,
    // so a fresh copy has none, and DEV keeps them out of the build
    if (import.meta.env.DEV) {
        const mocks = import.meta.glob<{ installDevPanel: () => void }>("./dev/devPanel.ts");

        for (const load of Object.values(mocks)) (await load()).installDevPanel();
    }

    createRoot(document.getElementById("root") as HTMLElement).render(<App />);
};

start();
