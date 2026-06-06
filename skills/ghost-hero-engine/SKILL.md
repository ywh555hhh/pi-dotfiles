---
name: ghost-hero-engine
description: Design and implement the game engine for the Ghost Hero pi-based text RPG. Covers non-numeric state design, CodeAct sandbox API, session-backed state persistence, combat resolution (narrative, not numeric), quest system, inventory management, NPC attitude tracking, and event/flag system. Use when building game logic, adding mechanics, or debugging state flow.
---

# Ghost Hero — Game Engine

## Design Principle: Zero Numbers in UI

The engine calculates. The UI describes. The player never sees `HP: 78/92`.

```typescript
// Engine computes:
const ratio = player.hp / player.maxHp

// Engine maps to narrative tier:
const condition = ratio > 0.8 ? '健康'
  : ratio > 0.6 ? '轻伤'
  : ratio > 0.4 ? '负伤'
  : ratio > 0.2 ? '重伤'
  : '濒死'

// UI receives: { condition: '轻伤', description: '几处擦伤不影响战斗' }
```

Every state field exposed to the UI has a narrative tier, not a number.

---

## State Schema

```typescript
// engine/state.ts

interface GameState {
  meta: {
    version: number
    day: number
    timeOfDay: 'dawn' | 'morning' | 'noon' | 'afternoon' | 'evening' | 'night'
    chapter: string
    turn: number
  }
  
  player: {
    name: string
    title: string               // 称号，随剧情/等级变化
    level: number
    exp: number                 // 内部数值，UI只显示进度条
    condition: ConditionTier    // '健康' | '轻伤' | '负伤' | '重伤' | '濒死'
    conditionDescription: string // "左臂中了一箭，有些发麻"
    
    hp: number; maxHp: number   // 内部数值，不暴露给UI
    mp: number; maxMp: number
    sp: number; maxSp: number
    
    attributes: {
      strength:     AttributeTier  // '凡人' | '过人' | '强者' | '怪物' | '传说'
      agility:      AttributeTier
      intelligence: AttributeTier
      vitality:     AttributeTier
      luck:         AttributeTier
    }
    
    statusEffects: StatusEffect[]  // [{ id, name, icon, turns, description }]
    skills: LearnedSkill[]
    equipment: {
      weapon:    EquipmentSlot | null
      armor:     EquipmentSlot | null
      accessory: EquipmentSlot | null
    }
    inventory: InventoryItem[]
    gold: number                  // 不显示数字，显示"囊中羞涩" / "小有积蓄" / "富甲一方"
  }
  
  world: {
    currentLocation: string
    exploredLocations: string[]
    activeQuests: Quest[]
    completedQuests: string[]
    reputation: Record<string, ReputationTier>  // '敌视' | '冷漠' | '中立' | '友善' | '崇拜'
    npcRelations: Record<string, RelationState> // { attitude, description, secretsKnown }
  }
  
  flags: Record<string, unknown>  // 剧情旗标
  combat: CombatState | null
}

type ConditionTier = '健康' | '轻伤' | '负伤' | '重伤' | '濒死'
type AttributeTier = '凡人' | '过人' | '强者' | '怪物' | '传说'
type ReputationTier = '敌视' | '冷漠' | '中立' | '友善' | '崇拜'

interface StatusEffect {
  id: string; name: string; icon: string
  turns: number; description: string
  onExpire?: string  // 描述消失时的效果
}

interface LearnedSkill {
  id: string; name: string; icon: string
  description: string; cooldown: number
  available: boolean
  mastery: '初学' | '熟练' | '精通' | '化境'
}

interface EquipmentSlot {
  id: string; name: string; icon: string
  grade: 'common' | 'rare' | 'epic' | 'legendary'
  description: string; effects: string[]  // 描述性效果，非数值
}

interface InventoryItem {
  id: string; name: string; icon: string
  type: 'consumable' | 'material' | 'key' | 'equipment'
  rarity: 'common' | 'rare' | 'epic' | 'legendary'
  count: number; description: string
  usable: boolean; effects?: string[]
}

interface Quest {
  id: string; title: string
  description: string; progress: string  // 叙事性进度
  urgency: 'normal' | 'urgent'
  stages: QuestStage[]
  currentStage: number
}

interface QuestStage {
  description: string; completed: boolean
}

interface CombatState {
  turn: number
  player: { name: string; effects: string[]; condition: string }
  enemy: { id: string; name: string; emoji: string; condition: string; effects: string[] }
  availableActions: Action[]
}

interface Action {
  key: string; label: string; icon: string
  description: string; available: boolean
  tooltip: string
}
```

---

## CodeAct Sandbox API

```typescript
// engine/codeact-sandbox.d.ts

// ── Query (read-only, always available) ──
declare function status(): Readonly<GameState>;
declare function lookupLocation(id: string): LocationData | null;
declare function lookupNpc(id: string): NpcData | null;
declare function lookupSkill(id: string): SkillData | null;
declare function lookupItem(id: string): ItemData | null;
declare function lookupQuest(id: string): QuestData | null;

// ── Combat (narrative resolution) ──
declare function initiateCombat(enemyId: string): CombatInitResult;
declare function resolveAction(
  action: 'attack' | 'defend' | 'skill' | 'item' | 'flee',
  detail?: string   // skillId or itemId
): ActionResult;
// Result is narrative: { outcome: '命中' | '偏斜' | '重创' | '招架', 
//                         description: string, effects: string[] }

// ── State mutation (protected paths, engine-enforced) ──
declare function adjustCondition(
  direction: 'improve' | 'worsen',
  severity: 'slight' | 'moderate' | 'severe',
  reason: string
): void;

declare function addStatusEffect(effectId: string): void;
declare function removeStatusEffect(effectId: string): void;

declare function addItem(itemId: string, count: number): void;
declare function removeItem(itemId: string, count: number): boolean;
declare function equipItem(itemId: string): void;
declare function unequipItem(slot: 'weapon' | 'armor' | 'accessory'): void;
declare function useItem(itemId: string): ItemUseResult;

declare function learnSkill(skillId: string): void;
declare function improveSkill(skillId: string): void;

declare function advanceTime(minutes: number, reason: string): AdvanceResult;
declare function travel(locationId: string): TravelResult;

declare function updateRelation(npcId: string, direction: 'improve' | 'worsen', reason: string): void;
declare function updateReputation(faction: string, direction: 'improve' | 'worsen', reason: string): void;

declare function updateQuest(questId: string, stageDescription: string): void;
declare function completeQuest(questId: string): void;

declare function setFlag(key: string, value: unknown): void;
declare function getFlag(key: string): unknown;

// ── Random (deterministic-seedable for replay) ──
declare function roll(sides: number, modifier?: number): RollResult;
declare function pickWeighted<T>(items: [T, number][]): T;
```

---

## Combat: Narrative Resolution

No damage formulas. No HP subtraction. Combat is a state machine driven by narrative logic.

```
Player: "我用暗影斩攻击他"

Engine (resolveAction):
  1. roll(20) → 14 + bonus from skill mastery
  2. vs enemy defense threshold
  3. Result:
     roll >= 18 → '重创': "一剑刺穿护甲，血花四溅"
     roll >= 12 → '命中': "剑锋划过，留下一道伤口"
     roll >= 6  → '轻伤': "擦过衣角，划破一层皮"
     roll < 6   → '偏斜': "对方侧身躲过"

  4. Apply narrative condition changes:
     '重创' → adjustCondition('worsen', 'severe')
     '命中' → adjustCondition('worsen', 'moderate')
     '轻伤' → adjustCondition('worsen', 'slight')
     '偏斜' → no change

  5. Return ActionResult:
     { outcome: '重创', description: "...", 
       enemyCondition: '重伤', effects: ['出血'] }
```

GM receives the result and narrates it. The engine guarantees the mechanical outcome.
The GM cannot "forget" to apply damage. The narrative quality and the mechanical consistency are separated.

---

## Engine ↔ UI Bridge

The engine runs inside pi's CodeAct sandbox. The extension bridge serializes state changes:

```typescript
// server/game-socket.ts

interface GameUpdate {
  type: 'game_update'
  narrative: string           // Markdown, from GM
  sceneMood?: string          // CSS class for ambiance
  combat?: CombatState | null // null = combat ended
  stateDiff: Partial<PanelState>  // Only changed fields
  newNpcs?: NpcPresence[]     // NPCs entering scene
  effects?: VisualEffect[]    // shake, flash, particles
}

interface VisualEffect {
  type: 'shake' | 'flashRed' | 'healPulse' | 'particleBurst'
  target: string              // CSS selector
  duration: number
}
```

Frontend `gameState` store receives `stateDiff` → deep-merge into reactive state → Vue auto-updates DOM → GSAP triggers visuals.
