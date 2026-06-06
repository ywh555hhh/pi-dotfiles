---
name: ghost-hero-ui
description: Build the browser frontend for the "Ghost Hero" pi-based text RPG. Covers Vue 3 component architecture, Tailwind styling, GSAP animations, hover tooltip system, panel layout that never overflows, combat HUD overlay, scene transitions, particle backgrounds, and responsive game-shell design. Use when building or modifying the game's browser UI.
---

# Ghost Hero — UI Architecture

## Stack

```
Vue 3 (Composition API + <script setup>)
Vite (dev server + build)
Tailwind CSS v4 + @tailwindcss/typography
GSAP (animations)
Lucide Icons (SVG icons, tree-shaken)
marked (markdown → HTML)
tsParticles (ambient particles only, no gameplay function)
```

## Layout: The "Never Overflow" Grid

The entire viewport is a strict CSS Grid. No scrollbar on body. Internal panels have `overflow-y: auto`.

```html
<div id="app" class="h-screen grid grid-cols-[280px_1fr] grid-rows-[1fr_auto]">
  <!-- Left: Side Panel (fixed 280px, scrolls internally) -->
  <aside class="row-span-2 overflow-y-auto">...</aside>
  
  <!-- Right top: Narrative Feed (flex-grow, scrolls internally) -->
  <main class="overflow-y-auto">...</main>
  
  <!-- Right bottom: Input Area (fixed height, never grows) -->
  <footer class="h-20">...</footer>
</div>
```

**Golden rule**: Zero elements overflow the viewport. No `vh` tricks. Grid handles everything.

### Overflow containment checklist (MUST verify for every component):
- [ ] Panel is inside a grid cell with a constrained size
- [ ] Panel has `overflow-y: auto` or `overflow: hidden`
- [ ] Text has `break-words` or `truncate` on bounded containers
- [ ] Tooltips use `position: fixed` + Popper.js logic (no layout shift)
- [ ] Images/emojis have `max-width: 100%` and `object-fit` bounds
- [ ] No `position: absolute` without a `position: relative` parent with bounded size
- [ ] Animation targets stay within their container (no `translate(200vw, 0)`)

---

## Component Tree

```
App.vue
├── ParticleBackground.vue     # z-index: -10, fixed, 纯氛围
├── SceneTransition.vue        # z-index: 50, 场景切换 wipe/fade
├── CombatHUD.vue              # z-index: 40, 底部战斗条，条件渲染
│
├── <aside> SidePanel.vue
│   ├── CharacterPortrait.vue  # 角色头像 + 称号 + 等级
│   ├── ConditionDisplay.vue   # 状态描述 + 心形图标
│   ├── AttributeBars.vue      # 力量/敏捷/体质/魔力 (标签+描述)
│   ├── SkillBar.vue           # 技能按钮 + tooltip
│   ├── BuffList.vue           # 增益/减益图标列表
│   ├── InventoryGrid.vue      # 背包格子网格 + tooltip
│   └── QuestLog.vue           # 任务列表
│
├── <main> NarrativeFeed.vue
│   └── MessageBubble.vue × N  # 每条消息
│       └── markdown 渲染内容
│
├── <footer> InputBar.vue      # 输入框 + 快捷行动按钮
│
└── Teleported overlays (不在 DOM 层级内):
    ├── TooltipPortal.vue       # 悬浮提示，position: fixed
    ├── ModalOverlay.vue        # 选择/确认对话框
    └── ToastStack.vue          # 右上角通知
```

---

## Tooltip System

Every interactive element that needs explanation gets a tooltip. Tooltips are NOT title attributes — they are Vue components rendered into a teleported `position: fixed` layer.

### Tooltip component contract

```vue
<!-- TooltipProvider wraps the entire app -->
<TooltipProvider :delay="400">
  <!-- Anything here can trigger tooltips -->
</TooltipProvider>

<!-- Usage anywhere -->
<SkillButton 
  icon="⚔️" 
  name="暗影斩"
  tooltip="凝聚暗影之力，向前方敌人发动突刺。造成大量伤害，有一定几率附加出血。"
  :cooldown="2"
/>
```

### Tooltip behavior rules

| Rule | Implementation |
|------|---------------|
| Show after 400ms hover | `setTimeout` + `clearTimeout` on leave |
| Position dynamically | Prefer above, fallback below if no room |
| Never overflow viewport | Clamp to `max-width: 280px` + boundary check |
| Instant hide on scroll | `wheel` event → hide |
| Instant hide on leave | No delay on mouseleave |
| No tooltip on touch | `@media (hover: hover)` guard |
| Rich content allowed | Accept slot with any HTML |

### Tooltip implementation (Popper-like, no dependency)

```typescript
// composables/useTooltip.ts
function computePosition(triggerEl: HTMLElement, tooltipEl: HTMLElement) {
  const trigger = triggerEl.getBoundingClientRect()
  const tip = tooltipEl.getBoundingClientRect()
  const vw = window.innerWidth
  const vh = window.innerHeight
  
  // Try above first
  let top = trigger.top - tip.height - 8
  let left = trigger.left + trigger.width / 2 - tip.width / 2
  
  // Clamp horizontal
  if (left < 8) left = 8
  if (left + tip.width > vw - 8) left = vw - tip.width - 8
  
  // Fall below if needed
  if (top < 8) {
    top = trigger.bottom + 8
    if (top + tip.height > vh - 8) top = vh - tip.height - 8
  }
  
  return { top: `${top}px`, left: `${left}px` }
}
```

---

## Inventory Grid

Items are rendered as a grid of cells with hover tooltips showing full item details.

```vue
<!-- InventoryGrid.vue -->
<template>
  <div class="p-3">
    <h3 class="text-xs font-bold text-zinc-500 uppercase tracking-wider mb-2">
      🎒 背包 ({{ items.length }}/{{ capacity }})
    </h3>
    <div class="grid grid-cols-4 gap-1.5">
      <InventoryCell 
        v-for="item in items" :key="item.id"
        v-bind="item"
      />
      <!-- Empty slots for visual consistency -->
      <div v-for="i in emptySlots" :key="'e'+i"
        class="aspect-square rounded border border-zinc-800/50 bg-zinc-900/30"
      />
    </div>
  </div>
</template>
```

```vue
<!-- InventoryCell.vue -->
<template>
  <div 
    class="relative aspect-square rounded border transition-all duration-200 cursor-default
           hover:border-amber-500/50 hover:bg-zinc-800/50 group"
    :class="rarityBorderClass"
  >
    <!-- Icon -->
    <div class="absolute inset-0 flex items-center justify-center text-xl">
      {{ item.icon }}
    </div>
    
    <!-- Count badge -->
    <div v-if="item.count > 1"
      class="absolute bottom-0.5 right-0.5 text-[10px] font-bold text-zinc-300
             bg-zinc-950/80 px-1 rounded"
    >
      {{ item.count }}
    </div>
    
    <!-- Tooltip (only on hover, via TooltipProvider) -->
    <template #tooltip>
      <div class="w-64">
        <div class="flex items-center gap-2 mb-1">
          <span class="text-lg">{{ item.icon }}</span>
          <span class="font-bold" :class="rarityTextClass">{{ item.name }}</span>
        </div>
        <div class="text-xs text-zinc-400 mb-2">{{ item.type }} · {{ item.rarity }}</div>
        <p class="text-sm text-zinc-300 leading-relaxed">{{ item.description }}</p>
        <div v-if="item.effects" class="mt-2 pt-2 border-t border-zinc-700">
          <div v-for="(v, k) in item.effects" :key="k" class="text-xs text-amber-400">
            {{ k }}: {{ v }}
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  item: {
    icon: string; name: string; count: number
    type: string; rarity: 'common' | 'rare' | 'epic' | 'legendary'
    description: string; effects?: Record<string, string>
  }
}>()

const rarityBorderClass = computed(() => ({
  common: 'border-zinc-700',
  rare: 'border-blue-800',
  epic: 'border-purple-800',
  legendary: 'border-amber-700',
}[props.item.rarity]))

const rarityTextClass = computed(() => ({
  common: 'text-zinc-300',
  rare: 'text-blue-400',
  epic: 'text-purple-400',
  legendary: 'text-amber-400',
}[props.item.rarity]))
</script>
```

---

## Combat HUD

Non-numeric combat. When `state.inCombat` is true, a HUD slides down from the bottom.

```vue
<!-- CombatHUD.vue -->
<template>
  <Transition name="combat-slide">
    <div v-if="inCombat" 
      class="border-t-2 border-red-900 bg-gradient-to-r from-red-950/90 via-zinc-950/95 to-red-950/90 
             px-8 py-5 backdrop-blur"
    >
      <div class="flex items-center justify-between max-w-4xl mx-auto">
        
        <!-- Player side -->
        <div class="flex items-center gap-4 min-w-0">
          <span class="text-3xl flex-shrink-0">🧑</span>
          <div class="min-w-0">
            <div class="font-bold text-zinc-200">{{ combat.player.name }}</div>
            <div class="flex items-center gap-1 mt-0.5">
              <span v-for="e in combat.player.effects" :key="e" 
                class="text-xs px-1.5 py-0.5 rounded bg-zinc-800">{{ e }}</span>
            </div>
          </div>
        </div>
        
        <!-- Center: Turn indicator -->
        <div class="flex flex-col items-center flex-shrink-0 mx-6">
          <span class="text-4xl font-black text-red-700 animate-pulse">⚔️</span>
          <span class="text-xs text-zinc-600 mt-1">回合 {{ combat.turn }}</span>
        </div>
        
        <!-- Enemy side -->
        <div class="flex items-center gap-4 min-w-0">
          <span class="text-3xl flex-shrink-0">{{ combat.enemy.emoji }}</span>
          <div class="min-w-0">
            <div class="font-bold text-zinc-200">{{ combat.enemy.name }}</div>
            <div class="text-sm text-zinc-500">{{ combat.enemy.condition }}</div>
          </div>
        </div>
      </div>
      
      <!-- Action buttons -->
      <div class="flex gap-3 justify-center mt-4">
        <ActionButton v-for="action in combatActions" :key="action.key"
          v-bind="action" @click="$emit('action', action.key)"
        />
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.combat-slide-enter-active { transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1); }
.combat-slide-leave-active { transition: all 0.3s ease-in; }
.combat-slide-enter-from,
.combat-slide-leave-to { opacity: 0; transform: translateY(100%); }
</style>
```

---

## Scene Transitions

When the player moves between locations: overlay fade to black → new scene description → fade in.

```vue
<!-- SceneTransition.vue -->
<template>
  <Transition name="scene">
    <div v-if="active" class="fixed inset-0 z-50 flex items-center justify-center">
      <!-- Overlay -->
      <div class="absolute inset-0 bg-black transition-opacity duration-700"
        :class="phase === 'fadeIn' || phase === 'fadeOut' ? 'opacity-100' : 'opacity-0'" />
      
      <!-- Scene title -->
      <div v-if="phase === 'showTitle'" 
        class="relative z-10 text-center animate-fade-in">
        <div class="text-5xl mb-3">{{ scene.icon }}</div>
        <h2 class="text-2xl font-bold text-amber-400 tracking-wider">
          {{ scene.location }}
        </h2>
        <p class="text-zinc-500 mt-2">{{ scene.time }}</p>
      </div>
    </div>
  </Transition>
</template>

<script setup lang="ts">
// phases: 'fadeIn' (0ms) → 'showTitle' (700ms) → 'fadeOut' (2000ms) → inactive
// Duration: ~3s total
</script>
```

---

## Animation Library

Centralized GSAP tweens. No inline `style` animations. Every animation is a named tween in a composable.

```typescript
// composables/useAnimations.ts
export function useAnimations() {
  function shakeElement(el: string | HTMLElement) {
    return gsap.to(el, {
      x: [-4, 4, -4, 4, 0],
      duration: 0.4,
      ease: 'power2.out'
    })
  }
  
  function flashRed(el: string | HTMLElement) {
    return gsap.fromTo(el,
      { boxShadow: 'inset 0 0 40px rgba(220,38,38,0.6)' },
      { boxShadow: 'inset 0 0 0px rgba(220,38,38,0)', duration: 0.6 }
    )
  }
  
  function healPulse(el: string | HTMLElement) {
    return gsap.fromTo(el,
      { boxShadow: '0 0 20px rgba(34,197,94,0.5)' },
      { boxShadow: '0 0 0px rgba(34,197,94,0)', duration: 0.8 }
    )
  }
  
  function staggerFadeIn(selector: string, staggerDelay = 0.05) {
    return gsap.from(selector, {
      opacity: 0, y: 16, duration: 0.4,
      stagger: staggerDelay, ease: 'power2.out'
    })
  }
  
  return { shakeElement, flashRed, healPulse, staggerFadeIn }
}
```

---

## Font & Typography

```css
/* src/styles/main.css */
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;500;700&family=Noto+Serif+SC:wght@400;700&display=swap');

@layer base {
  body {
    @apply bg-zinc-950 text-zinc-200 font-sans;
    /* font-sans = Noto Sans SC (Tailwind default override) */
  }
  
  .font-narrative {
    font-family: 'Noto Serif SC', serif;
  }
}
```

Narrative text uses serif (`font-narrative`). UI text uses sans (default). Tooltips use sans at `text-sm`. Combat HUD uses sans at `text-xs` for effects, `text-lg` for names.

---

## Responsive & Accessibility Notes

- Minimum supported width: 1024px (no mobile — this is a desktop game)
- All interactive elements have `cursor-default` or `cursor-pointer`
- Tooltips hidden on touch devices (`@media (hover: hover)`)
- Keyboard: `Enter` submits input, `Escape` closes modals
- Focus ring on input: `ring-1 ring-amber-500`
