// One prompt of the panel: what it does and the caps of the keys that do it
export interface KeybindItemPayload {
    label: string;
    keys: string[];
}

// The panel as client/keybinds.lua sends it. No items hides it
export interface KeybindPanelPayload {
    items: KeybindItemPayload[];
    title?: string;
    // Shown beside the title, such as a heading
    detail?: string;
    // Why what the panel is about can not be done
    warning?: string;
}

export interface LuaMessages {
    SetKeybinds: KeybindPanelPayload;
}
