import Keycap from "./Keycap";
import styles from "./KeybindItem.module.css";

interface KeybindItemProps {
    label: string;
    keys: string[];
}

// The keys of one prompt and what they do
const KeybindItem = ({ label, keys }: KeybindItemProps) => (
    <div className={styles.item}>
        <div className={styles.keys}>
            {keys.map((name) => (
                <Keycap key={name}>{name}</Keycap>
            ))}
        </div>
        <p className={styles.label}>{label}</p>
    </div>
);

export default KeybindItem;
