---
name: ghost-hero-narrative
description: Design the narrative system for the Ghost Hero pi-based text RPG. Covers GM prompt architecture, NPC sub-agent design, non-numeric combat narration, scene mood management, world-building data structures, quest design patterns, and progressive disclosure of story information. Use when writing GM prompts, creating NPCs, building world data, or designing quest lines.
---

# Ghost Hero — Narrative System

## GM Prompt Architecture

GM prompt is layered: stable identity at top, dynamic context injected per-turn.

```
┌─ Layer 1: Stable Identity ─────────────────────┐
│  你是《鬼畜英雄》这个世界的GM。                     │
│  规则：叙事层在Markdown，机械层不显示给玩家。       │
│  文风：黑暗奇幻，压抑但非绝望。                    │
│  硬规则：不超过5条。                              │
└─────────────────────────────────────────────────┘
┌─ Layer 2: World Context (per turn injection) ──┐
│  当前场景：歪嘴酒馆 · 黄昏                         │
│  在场NPC：酒馆老板(😰紧张)，陌生旅人(🧥冷淡)       │
│  可用工具：status, lookupNpc, travel, ...        │
└─────────────────────────────────────────────────┘
┌─ Layer 3: Player Input ────────────────────────┐
│  玩家说："我走到老板面前，问他商队的事。"           │
└─────────────────────────────────────────────────┘
┌─ Layer 4: Dynamic Reminders ───────────────────┐
│  本轮提醒：                                      │
│  · 老板被黑箭团威胁过——提到商队他应该会紧张        │
│  · 旅人在暗中观察——如果玩家操作太明显应该有所反应   │
│  · status()检查老板的好感度，会影响他是否开口       │
│  · 不要替玩家做决定                              │
└─────────────────────────────────────────────────┘
```

Dynamic reminders are injected by the extension before each turn, based on:
- Current location's active NPCs and their states
- Active quest objectives that are actionable in this scene
- Upcoming plot triggers (flags that are about to trip)
- Combat state (if applicable)

---

## NPC Sub-Agent Design

Only split NPCs when they have secrets, hidden motivations, or need different voice/perspective from GM.

### Sub-agent prompt template

```markdown
你是 <NPC名称>，在《鬼畜英雄》的世界中。

## 你的身份
<一句话定位>

## 你知道的事
- <公开信息>
- <只有你知道的秘密> ← 这才是拆agent的理由

## 你不知道的事
- <其他NPC的秘密>
- <GM手中的完整世界状态>
- <玩家的真实目标>

## 你的性格与说话方式
- <2-3条核心特征>

## 当前处境
<GM通过task参数注入的场景信息>

## 输出
只输出你的台词、动作、神态。不要接管GM的叙事职能。
如果是内心活动，用 *斜体* 包裹。
```

### When NOT to split

- Shopkeeper who just sells items → no subagent, GM plays them
- Quest-giver with no secrets → GM plays them
- Enemy who exists only for combat → pure GM narration
- Background NPC with < 3 lines of dialogue → GM narration

---

## Scene Mood System

Each scene has a mood that controls UI ambiance:

```typescript
interface SceneMood {
  location: string          // "歪嘴酒馆"
  timeOfDay: TimeOfDay
  mood: 'peaceful' | 'tense' | 'eerie' | 'triumphant' | 'somber' | 'romantic' | 'chaotic'
  bgClass: string           // CSS class applied to body
  particleTheme: string     // tsParticles config preset
  colorAccent: string       // "#c9a96e" for warm, "#8b0000" for danger
  soundscape?: string       // Description for music selection (future)
}

// Frontend maps mood to CSS:
// 'peaceful' → warm light, slow particles, amber accent
// 'tense'   → desaturated, faster particles, red accent
// 'eerie'   → dark, fog-like particles, purple accent
// 'chaotic' → red overlay, spark particles, crimson accent
```

Scene mood changes when:
- Player enters combat → `tense` or `chaotic`
- Combat ends → revert to previous mood
- Major plot reveal → brief `eerie`, then resolve
- Time of day changes → natural transition

---

## World Data Structure

```json
// data/world.json
{
  "worldName": "鬼畜英雄",
  "premise": "一句话世界观...",
  "history": "简史...",
  "factions": [
    { "id": "black_arrow", "name": "黑箭强盗团", "description": "...", "territory": "..." }
  ]
}
```

```json
// data/locations.json
{
  "locations": [
    {
      "id": "tavern_crooked",
      "name": "歪嘴酒馆",
      "type": "tavern",
      "description": "...",
      "mood": "seedy",
      "connections": ["town_square", "back_alley"],
      "npcsPresent": ["innkeeper_grim", "traveler_mysterious"],
      "events": ["merchant_talk", "brawl_trigger", "secret_meeting"],
      "discoverable": false
    }
  ]
}
```

```json
// data/npcs.json
{
  "npcs": [
    {
      "id": "innkeeper_grim",
      "name": "格里姆",
      "role": "酒馆老板",
      "emoji": "😰",
      "description": "...",
      "personality": ["胆小", "重情义"],
      "secrets": ["知道商队路线", "被黑箭团威胁", "女儿被挟持"],
      "relations": {
        "black_arrow": "恐惧",
        "merchant_guild": "旧识"
      },
      "questGiver": true,
      "subagent": true
    }
  ]
}
```

---

## Quest Design Patterns

```typescript
// Quest archetypes mapped to engine flow:

// 1. 情报收集
// Player gathers clues from multiple NPCs/locations
// Engine tracks: flags["clue_innkeeper"], flags["clue_alley"], ...
// When all flags set → quest progresses

// 2. 护送/护送
// Player escorts NPC through dangerous route
// Engine triggers: random encounters per travel segment
// Each encounter resolved → advanceTime + condition changes

// 3. 猎杀
// Player tracks and defeats a specific enemy
// Engine tracks: tracking progress, enemy location
// When found → initiateCombat

// 4. 解谜
// Player pieces together fragments
// Engine tracks: fragmentsFound[], solutionAttempted[]
// When correct → setFlag('puzzle_solved', true)
```

All quests use flags + relations + reputation, never raw state manipulation by the player.

---

## Progressive Disclosure

Information reaches the player through natural channels:

| Channel | Example |
|---------|---------|
| GM direct narration | Scene description |
| NPC dialogue | "那批货...前天走的南路" |
| Item descriptions | 破旧的账本："3月15日，黑箭团，30金币" |
| Scene details | "墙上有一道新鲜的剑痕" |
| Player intuition | GM after successful perception: "你觉得老板在说谎" |

Never dump exposition. Always let the player *discover*.
