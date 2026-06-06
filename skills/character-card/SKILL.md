---
name: character-card
description: Create, parse, and manipulate AI roleplay character cards (PNG metadata + JSON). Covers the Character Card v2/v3 spec, PNG chunk manipulation, batch processing, format conversion (W++/Boostyle/PList/plain), and extracting character data from SillyTavern. Use when creating or editing character cards programmatically or in bulk.
---

# Character Card Tools

## Character Card Specification

### PNG-based Card (v2/v3)
Character data is embedded in PNG `tEXt` chunks with key `chara`.

```bash
# Read character data from a PNG card
exiftool -b -chara character.png | python3 -m json.tool

# Or with Node.js
node -e "
const fs = require('fs');
const buffer = fs.readFileSync('character.png');
// Find tEXt chunk with 'chara' keyword
// Parse JSON from chunk data
"
```

### JSON Structure (v2)
```json
{
  "name": "Character Name",
  "description": "Physical description...",
  "personality": "Personality traits...",
  "scenario": "Current scenario...",
  "first_mes": "Hello, I am {{char}}...",
  "mes_example": "<START>\n{{char}}: ...\n{{user}}: ...",
  "creator_notes": "Author's notes",
  "system_prompt": "Custom system prompt override",
  "post_history_instructions": "Instructions after chat history",
  "alternate_greetings": ["Alt greeting 1", "Alt greeting 2"],
  "character_book": { ... },
  "tags": ["fantasy", "elf", "mage"],
  "creator": "Author name",
  "character_version": "1.0",
  "extensions": { ... }
}
```

### JSON Structure (v3 / Spec v3)
Adds `spec_version`, `spec`, and restructured fields. Check the official spec for latest format.

## Common Operations

### Batch extract character metadata
```bash
# List all character cards in SillyTavern
for f in SillyTavern/data/default-user/characters/*.png; do
  echo "=== $(basename "$f") ==="
  exiftool -b -chara "$f" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name','?'), '-', d.get('tags',[]))"
done
```

### Convert between formats
```bash
# W++ to plain text (simplified)
# See references/format-conversion.md
```

### Create a character card from scratch
```bash
# Using Python with Pillow
python3 << 'EOF'
import json
from PIL import Image

char_data = {
    "name": "My Character",
    "description": "A brave knight from the northern kingdoms.",
    "personality": "Noble, courageous, sometimes reckless.",
    "scenario": "Meeting a stranger at the tavern.",
    "first_mes": "*The knight looks up from her drink.* 'Well met, traveler.'",
    "mes_example": "<START>\n{{char}}: *Draws sword.* 'Stand back!'\n{{user}}: I'm not your enemy!\n{{char}}: *Lowers blade slowly.* '...Prove it.'",
}

# Create a blank image (or use an existing one)
img = Image.new('RGB', (400, 600), color='white')
img.save('character.png', pnginfo=None)
# Need proper pnginfo embedding - use exiftool or png-chunk tools
EOF
```

## SillyTavern Character Storage

Characters are stored in `data/default-user/characters/` as:
- `.png` files with embedded JSON (primary format)
- `.charx.json` files (extracted character data cache/history)

## Tooling

| Tool | Use |
|------|-----|
| exiftool | Read/write PNG metadata |
| Pillow (Python) | Programmatic image manipulation |
| sharp (Node.js) | Node.js image processing |
| png-chunk-* (npm) | Low-level PNG chunk manipulation |

## Batch Processing Script Template

See [references/batch-process.py] for a full Python script that:
- Reads all character cards from a directory
- Extracts JSON metadata
- Validates against spec
- Outputs a summary CSV
