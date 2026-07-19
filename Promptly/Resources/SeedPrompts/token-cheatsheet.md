---
name: Token cheatsheet
keywords: [tokens, clipboard, date, cursor, help]
---
Promptly token grammar (Stage 3+):

{{clipboard}}  — contents of your clipboard at paste time
{{date}}       — today's date (ISO 8601)
{{cursor}}     — where the caret lands after paste (AX path only; falls back to end-of-text)
{{ask:label}}  — interactive fill-in (Stage 4): palette transforms in place, you type the answer

Unknown tokens stay literal so typos are visible.
Empty known tokens log a warning.
