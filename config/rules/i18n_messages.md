`next-intl` message catalogs. Example setup: the app ships two locales, `en` and `fr`, and both files must stay in sync.

- **Key parity**: a key added, renamed or removed in one of `messages/en.json` / `messages/fr.json` but not the other. If only one of the two files is in the diff, Read the other before flagging.
- **Placeholder parity**: ICU placeholders (`{name}`, `{count, plural, ...}`, rich-text tags like `<link>`) differ between the `en` and `fr` value of the same key, or are malformed (unbalanced braces, `plural` without `other`).
- **Callers**: a removed or renamed key still referenced via `t("...")` / `useTranslations` / `getTranslations` in the code (Grep for it).
- **Register**: copy that breaks the form of address the repo guidance prescribes (for example formal vs informal "you"), when the guidance names one.
- **Untranslated value**: a non-English value that is identical English text for a full sentence (not brand names or technical terms).
- **JSON**: duplicate keys in the same object (the later one silently wins).

Do not report: wording preferences, punctuation style, or key naming style.
