import { useEffect } from "react";
import KeybindPanel from "./keybinds/KeybindPanel";
import { postNui } from "./nui";

// What zyke_vehiclelifts draws over the game: the keybind panel at the power unit and while the arms are set. It
// never takes focus, so the game keeps its input
const App = () => {
    // Lua sends the panel again once the page can take it
    useEffect(() => {
        postNui("KeybindsReady");
    }, []);

    return <KeybindPanel />;
};

export default App;
