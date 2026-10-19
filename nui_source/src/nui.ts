import { useEffect, useRef } from "react";
import type { LuaMessages } from "./types";

interface NuiMessage {
    event?: string;
    data?: unknown;
}

const nuiWindow = window as unknown as { GetParentResourceName?: () => string };

// Subscribes to a SendNUIMessage event from Lua; the latest handler is always used
export const useNuiEvent = <K extends keyof LuaMessages>(event: K, handler: (data: LuaMessages[K]) => void) => {
    const savedHandler = useRef(handler);

    useEffect(() => {
        savedHandler.current = handler;
    }, [handler]);

    useEffect(() => {
        const listener = (e: MessageEvent<NuiMessage>) => {
            if (!e.data || e.data.event !== event) return;

            savedHandler.current(e.data.data as LuaMessages[K]);
        };

        window.addEventListener("message", listener);

        return () => window.removeEventListener("message", listener);
    }, [event]);
};

// Calls a RegisterNUICallback of this resource. Outside the game there is nothing to call
export const postNui = (endpoint: string, data: unknown = {}) => {
    if (!nuiWindow.GetParentResourceName) return;

    void fetch(`https://${nuiWindow.GetParentResourceName()}/${endpoint}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data),
    }).catch(() => undefined);
};
