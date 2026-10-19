import { useState } from "react";
import { useNuiEvent } from "../nui";
import type { KeybindPanelPayload } from "../types";
import KeybindItem from "./KeybindItem";
import styles from "./KeybindPanel.module.css";

const empty: KeybindPanelPayload = { items: [] };

// The instructional keybinds: the prompts Lua shows at the power unit, while the arms are set and while a lift is
// placed, with a detail beside the title and why it can not be done. The last panel stays in place while it slides
// out, so it does not empty on the way
const KeybindPanel = () => {
    const [panel, setPanel] = useState(empty);
    const [shown, setShown] = useState(false);

    // An empty Lua table may arrive as an object instead of an array
    useNuiEvent("SetKeybinds", (data) => {
        const next = Array.isArray(data?.items) && data.items.length > 0 ? data : null;

        if (next) setPanel(next);

        setShown(next !== null);
    });

    return (
        <div className={styles.wrapper}>
            <div className={shown ? `${styles.panel} ${styles.shown}` : styles.panel}>
                {panel.title && (
                    <div className={styles.header}>
                        <span className={styles.title}>{panel.title}</span>
                        {panel.detail && <span className={styles.detail}>{panel.detail}</span>}
                    </div>
                )}

                {panel.warning && <div className={styles.warning}>{panel.warning}</div>}

                <div className={styles.body}>
                    {panel.items.map((item, index) => (
                        <KeybindItem key={`${item.label}-${index}`} label={item.label} keys={item.keys} />
                    ))}
                </div>
            </div>
        </div>
    );
};

export default KeybindPanel;
