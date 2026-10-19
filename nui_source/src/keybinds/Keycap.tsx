import type { ReactNode } from "react";
import styles from "./Keycap.module.css";

interface KeycapProps {
    children: ReactNode;
}

// One key the player presses, such as <Keycap>LMB</Keycap>
const Keycap = ({ children }: KeycapProps) => <kbd className={styles.key}>{children}</kbd>;

export default Keycap;
