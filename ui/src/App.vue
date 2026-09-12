<script setup>
import { computed, nextTick, onMounted, onUnmounted, reactive, ref, watch } from "vue";
import { nuiPost } from "./api";
import { emojiGroups, searchEmoji } from "./emoji.mjs";
import MessageItem from "./components/MessageItem.vue";
import SuggestionsList from "./components/SuggestionsList.vue";

const CHAT_HIDE_STATES = {
  SHOW_WHEN_ACTIVE: 0,
  ALWAYS_SHOW: 1,
  ALWAYS_HIDE: 2,
};

const defaultMode = {
  name: "all",
  displayName: "",
  color: "#f5f1df",
};

const globalMode = {
  name: "_global",
  displayName: "",
  color: "#d8c59f",
  hidden: true,
  isGlobal: true,
};

const state = reactive({
  showInput: false,
  showWindow: false,
  showHideState: false,
  showEmojiPicker: false,
  hidden: false,
  hideState: CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE,
  message: "",
  messages: [],
  oldMessages: [],
  oldMessagesIndex: -1,
  showOlderMessages: false,
  suggestions: [],
  removedSuggestions: [],
  modes: [defaultMode, globalMode],
  activeModeName: defaultMode.name,
  config: {
    hideOlderMessagesHours: 3,
    historyEnabled: false,
  },
  locale: {
    general: "",
    global: "",
    ooc: "",
    admin: "",
    announcements: "",
    other: "",
    visible: "",
    hidden: "",
    whenActive: "",
    showOlderMessages: "",
    hideOlderMessages: "",
    nameButton: "",
    nameTitle: "",
    localeCode: "en-GB",
    emojiFaces: "",
    emojiPeople: "",
    emojiHearts: "",
    emojiWestern: "",
    emojiAnimals: "",
    emojiWorld: "",
    emojiComponents: "",
    emojiFood: "",
    emojiTravel: "",
    emojiActivities: "",
    emojiObjects: "",
    emojiSymbols: "",
    emojiFlags: "",
    emojiSearch: "",
    emojiNoResults: "",
  },
});

const inputRef = ref(null);
const messagesRef = ref(null);
const activeEmojiGroupKey = ref("emojiWestern");
const emojiQuery = ref("");

let focusTimer = null;
let showWindowTimer = null;
let showHideStateTimer = null;

const visibleSuggestions = computed(() =>
  state.suggestions.filter((item) => !state.removedSuggestions.includes(item.name))
);

const visibleModes = computed(() =>
  state.modes.filter((mode) => !mode.hidden)
);

const activeMode = computed(() => {
  if (!state.modes.length) {
    return defaultMode;
  }

  return state.modes.find((mode) => mode.name === state.activeModeName) || state.modes[0];
});

const activeEmojiGroup = computed(() =>
  emojiGroups.find((group) => group.labelKey === activeEmojiGroupKey.value) || emojiGroups[0]
);

const visibleEmoji = computed(() => {
  if (!emojiQuery.value.trim()) {
    return activeEmojiGroup.value.items;
  }

  return searchEmoji(
    [...new Set(emojiGroups.flatMap((group) => group.items))],
    emojiQuery.value
  );
});

const modePrefix = computed(() => {
  return ">";
});

const hideStateLabel = computed(() => {
  switch (state.hideState) {
    case CHAT_HIDE_STATES.ALWAYS_SHOW:
      return state.locale.visible;
    case CHAT_HIDE_STATES.ALWAYS_HIDE:
      return state.locale.hidden;
    default:
      return state.locale.whenActive;
  }
});

const filteredMessages = computed(() =>
  state.messages.filter((message) => {
    if (activeMode.value?.name === "all") {
      return message.mode === "all" || !message.mode || message.modeData?.isGlobal;
    }

    if (message.modeData?.isChannel || activeMode.value?.isChannel) {
      return message.mode === activeMode.value.name || message.modeData?.isGlobal;
    }

    return true;
  })
);

const oldFilteredMessages = computed(() =>
  filteredMessages.value.filter((message) => message.isOlderThanThreshold)
);

const recentFilteredMessages = computed(() =>
  filteredMessages.value.filter((message) => !message.isOlderThanThreshold)
);

const displayedMessages = computed(() => {
  if (state.showOlderMessages) {
    return filteredMessages.value;
  }

  return recentFilteredMessages.value;
});

const oldMessageButtonLabel = computed(() => {
  const count = oldFilteredMessages.value.length;
  if (count <= 0) {
    return "";
  }

  const baseLabel = state.showOlderMessages
    ? state.locale.hideOlderMessages
    : state.locale.showOlderMessages;

  return `${baseLabel} (${count})`;
});

watch(
  () => state.messages.length,
  async () => {
    if (state.hideState !== CHAT_HIDE_STATES.ALWAYS_HIDE) {
      clearShowWindowTimer();
      state.showWindow = true;
      resetShowWindowTimer();
    }

    await nextTick();
    if (messagesRef.value) {
      messagesRef.value.scrollTop = messagesRef.value.scrollHeight;
    }
  }
);

onMounted(async () => {
  window.addEventListener("message", onMessage);
  document.addEventListener("keydown", onPageKeyDown);
  await nuiPost("loaded");
});

onUnmounted(() => {
  window.removeEventListener("message", onMessage);
  document.removeEventListener("keydown", onPageKeyDown);
  clearInterval(focusTimer);
  clearTimeout(showWindowTimer);
  clearTimeout(showHideStateTimer);
});

function onMessage(event) {
  const item = event.data || event.detail;
  if (!item || !item.type) {
    return;
  }

  const handlers = {
    ON_OPEN: openChat,
    ON_MESSAGE: ({ message }) => addMessage(message),
    ON_CLEAR: clearChat,
    ON_SUGGESTION_ADD: ({ suggestion }) => addSuggestion(suggestion),
    ON_SUGGESTION_REMOVE: ({ name }) => removeSuggestion(name),
    ON_MODE_ADD: ({ mode }) => addMode(mode),
    ON_MODE_REMOVE: ({ name }) => removeMode(name),
    ON_CONFIG: ({ config }) => updateConfig(config),
    ON_THEME: ({ theme }) => updateTheme(theme),
    ON_LOCALE: ({ locale }) => updateLocale(locale),
    ON_SCREEN_STATE_CHANGE: ({ hideState, fromUserInteraction }) =>
      updateScreenState(hideState, fromUserInteraction),
    ON_HIDE_STATE: ({ hidden }) => {
      state.hidden = !!hidden;
    },
    ON_UPDATE_THEMES: () => {},
  };

  const handler = handlers[item.type];
  if (handler) {
    handler(item);
  }
}

function onPageKeyDown(event) {
  if (!state.showInput) {
    return;
  }

  if (event.key === "PageUp" && messagesRef.value) {
    messagesRef.value.scrollTop -= 100;
  } else if (event.key === "PageDown" && messagesRef.value) {
    messagesRef.value.scrollTop += 100;
  }
}

function openChat() {
  state.showInput = true;
  state.showWindow = true;
  state.showEmojiPicker = false;
  clearShowWindowTimer();
  clearInterval(focusTimer);

  focusTimer = window.setInterval(() => {
    if (inputRef.value) {
      inputRef.value.focus();
    }
  }, 100);
}

function addMessage(message) {
  state.messages.push(normalizeIncomingMessage(message));
  const configured = Number(state.config.maximumVisibleMessages);
  const maximum = Number.isFinite(configured) && configured >= 0 ? configured : 100;
  if (state.messages.length > maximum) {
    state.messages.splice(0, state.messages.length - maximum);
  }
}

function normalizeIncomingMessage(message) {
  const normalizedCreatedAtMs = resolveMessageTimestamp(message.createdAt);
  const thresholdMs = getOldMessageThresholdMs();

  return {
    ...message,
    mode: message.mode || "all",
    id: `${Date.now()}-${Math.random()}`,
    modeData: state.modes.find((mode) => mode.name === (message.mode || "all")),
    createdAtMs: normalizedCreatedAtMs,
    isOlderThanThreshold: Date.now() - normalizedCreatedAtMs > thresholdMs,
  };
}

function getOldMessageThresholdMs() {
  const hours = Number(state.config.hideOlderMessagesHours);
  return (Number.isFinite(hours) && hours > 0 ? hours : 3) * 60 * 60 * 1000;
}

function resolveMessageTimestamp(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value > 1_000_000_000_000 ? value : value * 1000;
  }

  if (typeof value === "string" && value) {
    const parsedNumber = Number(value);
    if (!Number.isNaN(parsedNumber)) {
      return parsedNumber > 1_000_000_000_000 ? parsedNumber : parsedNumber * 1000;
    }

    const parsedDate = Date.parse(value);
    if (!Number.isNaN(parsedDate)) {
      return parsedDate;
    }
  }

  return Date.now();
}

function clearChat() {
  state.messages = [];
  state.oldMessages = [];
  state.oldMessagesIndex = -1;
  state.showOlderMessages = false;
}

function addSuggestion(suggestion) {
  state.removedSuggestions = state.removedSuggestions.filter((name) => name !== suggestion.name);
  const existing = state.suggestions.find((item) => item.name === suggestion.name);

  if (existing) {
    existing.help = suggestion.help || "";
    existing.params = suggestion.params || [];
    return;
  }

  state.suggestions.push({
    ...suggestion,
    params: suggestion.params || [],
  });
}

function removeSuggestion(name) {
  state.suggestions = state.suggestions.filter((item) => item.name !== name);
  state.removedSuggestions = state.removedSuggestions.filter((item) => item !== name);
}

function addMode(mode) {
  state.modes = [...state.modes.filter((item) => item.name !== mode.name), mode];
  state.messages = state.messages.map((message) => ({
    ...message,
    modeData: state.modes.find((entry) => entry.name === (message.mode || "all")) || message.modeData,
  }));
}

function updateConfig(config) {
  state.config = {
    ...state.config,
    ...config,
  };

  state.messages = state.messages.map((message) => ({
    ...message,
    isOlderThanThreshold: Date.now() - message.createdAtMs > getOldMessageThresholdMs(),
  }));

  const accessibility = state.config.accessibility || {};
  const scale = Math.min(1.5, Math.max(0.8, Number(accessibility.fontScale) || 1));
  document.documentElement.style.setProperty("--chat-font-scale", String(scale));
  document.documentElement.classList.toggle("reduced-motion", accessibility.reducedMotion === true);
  document.documentElement.classList.toggle("compact-chat", accessibility.density === "compact");
}

function updateTheme(theme) {
  const tokens = theme?.tokens || {};
  const mapping = {
    background: "--chat-background", panel: "--chat-panel", border: "--chat-border",
    primary: "--chat-primary", muted: "--chat-muted", danger: "--chat-danger",
  };
  Object.entries(mapping).forEach(([key, property]) => {
    if (typeof tokens[key] === "string") document.documentElement.style.setProperty(property, tokens[key]);
  });
}

function updateLocale(locale) {
  state.locale = {
    ...state.locale,
    ...locale,
  };

  // Mutate through the reactive `state.modes` entries (not the raw defaultMode/globalMode
  // objects) so Vue's reactivity actually picks up the change and the tab labels re-render.
  const generalEntry = state.modes.find((mode) => mode.name === defaultMode.name);
  if (generalEntry) generalEntry.displayName = state.locale.general;
  const globalEntry = state.modes.find((mode) => mode.name === globalMode.name);
  if (globalEntry) globalEntry.displayName = state.locale.global;

  // Keep the raw template objects in sync too, since they're reused as fallbacks
  // (e.g. activeMode()'s empty-state default, removeMode()'s reset) outside state.modes.
  defaultMode.displayName = state.locale.general;
  globalMode.displayName = state.locale.global;
}

function removeMode(name) {
  state.modes = state.modes.filter((item) => item.name !== name);
  if (!state.modes.length) {
    state.modes = [defaultMode];
  }
  if (state.activeModeName === name) {
    state.activeModeName = state.modes[0].name;
  }
}

function toggleOlderMessages() {
  state.showOlderMessages = !state.showOlderMessages;
}

function updateScreenState(hideState, fromUserInteraction) {
  state.hideState = hideState;

  if (hideState === CHAT_HIDE_STATES.ALWAYS_HIDE) {
    if (!state.showInput) {
      state.showWindow = false;
    }
  } else if (hideState === CHAT_HIDE_STATES.ALWAYS_SHOW) {
    state.showWindow = true;
    clearShowWindowTimer();
  } else {
    resetShowWindowTimer();
  }

  if (fromUserInteraction) {
    state.showHideState = true;
    clearTimeout(showHideStateTimer);
    showHideStateTimer = window.setTimeout(() => {
      state.showHideState = false;
    }, 1500);
  }
}

function clearShowWindowTimer() {
  clearTimeout(showWindowTimer);
}

function resetShowWindowTimer() {
  clearShowWindowTimer();
  const configuredDelay = Number(state.config.fadeDelayMs);
  showWindowTimer = window.setTimeout(() => {
    if (state.hideState !== CHAT_HIDE_STATES.ALWAYS_SHOW && !state.showInput) {
      state.showWindow = false;
    }
  }, Number.isFinite(configuredDelay) && configuredDelay >= 0 ? configuredDelay : 10000);
}

function cycleMode(backwards = false) {
  if (state.modes.length <= 1) {
    return;
  }

  let idx = state.modes.findIndex((mode) => mode.name === state.activeModeName);
  if (idx < 0) idx = 0;

  do {
    if (backwards) {
      idx -= 1;
      if (idx < 0) {
        idx = state.modes.length - 1;
      }
    } else {
      idx = (idx + 1) % state.modes.length;
    }
  } while (state.modes[idx].hidden);

  state.activeModeName = state.modes[idx].name;
}

function selectModeByName(name) {
  const mode = state.modes.find((item) => item.name === name && !item.hidden);
  if (mode) {
    state.activeModeName = mode.name;
  }
}

function moveMessageHistory(up) {
  if (up && state.oldMessages.length > state.oldMessagesIndex + 1) {
    state.oldMessagesIndex += 1;
    state.message = state.oldMessages[state.oldMessagesIndex];
  } else if (!up && state.oldMessagesIndex - 1 >= 0) {
    state.oldMessagesIndex -= 1;
    state.message = state.oldMessages[state.oldMessagesIndex];
  } else if (!up && state.oldMessagesIndex - 1 === -1) {
    state.oldMessagesIndex = -1;
    state.message = "";
  }
}

function resizeInput() {
  const input = inputRef.value;
  if (!input) {
    return;
  }

  input.style.height = "5px";
  input.style.height = `${input.scrollHeight}px`;
}

function onInputKeydown(event) {
  if (event.key === "Escape") {
    hideInput(true);
    return;
  }

  if (event.key === "ArrowUp") {
    event.preventDefault();
    moveMessageHistory(true);
  } else if (event.key === "ArrowDown") {
    event.preventDefault();
    moveMessageHistory(false);
  } else if (event.key === "Tab") {
    event.preventDefault();
    cycleMode(event.shiftKey || event.altKey);
  }

  window.setTimeout(resizeInput, 0);
}

async function send() {
  if (state.message.trim() === "") {
    await hideInput(true);
    return;
  }

  await nuiPost("chatResult", {
    message: state.message,
    mode: activeMode.value.name,
  });

  state.oldMessages.unshift(state.message);
  if (state.oldMessages.length > 50) state.oldMessages.length = 50;
  state.oldMessagesIndex = -1;
  if (state.config.submitCloses !== false) {
    await hideInput(false);
  } else {
    state.message = "";
    await nextTick();
    inputRef.value?.focus();
  }
}

async function hideInput(canceled) {
  await nextTick();

  if (canceled) {
    await nuiPost("chatResult", { canceled: true });
  }

  if (inputRef.value) {
    inputRef.value.style.height = "";
  }

  state.message = "";
  state.showInput = false;
  state.showEmojiPicker = false;
  clearInterval(focusTimer);

  if (state.hideState !== CHAT_HIDE_STATES.ALWAYS_HIDE) {
    resetShowWindowTimer();
  } else {
    state.showWindow = false;
  }
}

function toggleEmojiPicker() {
  state.showEmojiPicker = !state.showEmojiPicker;
  if (state.showEmojiPicker) {
    emojiQuery.value = "";
  }
  if (!state.showEmojiPicker && inputRef.value) {
    inputRef.value.focus();
  }
}

async function openDisplayNameMenu() {
  state.showEmojiPicker = false;
  await nuiPost("openDisplayNameMenu");
  state.showInput = false;
}

async function addEmoji(emoji) {
  state.message += emoji;
  await nextTick();
  resizeInput();
  if (inputRef.value) {
    inputRef.value.focus();
  }
}

watch(
  () => activeMode.value?.name,
  (name) => {
    state.showOlderMessages = false;
    if (state.config.historyEnabled && name && name !== "_global") {
      nuiPost("selectChannel", {
        channelKey: name === "all" ? "local.say" : name,
      });
    }
  }
);
</script>

<template>
  <div class="chat-shell">
    <section class="chat-window" :class="{ hidden: !state.showWindow || state.hidden }">
      <div v-if="visibleModes.length > 1" class="chat-tabs">
        <button
          v-for="mode in visibleModes"
          :key="mode.name"
          type="button"
          class="chat-tab"
          :class="{ active: activeMode.name === mode.name }"
          :style="{ '--tab-color': mode.color || '#ffffff' }"
          @click="selectModeByName(mode.name)"
        >
          {{ mode.displayName }}
        </button>
      </div>
      <div class="chat-messages" ref="messagesRef">
        <button
          v-if="oldFilteredMessages.length"
          type="button"
          class="older-messages-toggle"
          @click="toggleOlderMessages"
        >
          {{ oldMessageButtonLabel }}
        </button>
        <MessageItem
          v-for="message in displayedMessages"
          :key="message.id"
          :message="message"
          :active-mode="activeMode"
          :locale-code="state.locale.localeCode"
        />
      </div>
    </section>

    <section class="chat-input-shell" :class="{ hidden: state.hidden }">
      <div v-if="state.showInput" class="chat-input-row">
        <span class="mode-pill" :style="{ color: activeMode.color }">{{ modePrefix }}</span>
        <textarea
          ref="inputRef"
          v-model="state.message"
          rows="1"
          spellcheck="false"
          autofocus
          class="chat-input"
          @input="resizeInput"
          @keydown.enter.exact.prevent="send"
          @keydown="onInputKeydown"
        />
        <button v-if="state.config.displayNamePreferences" type="button" class="settings-button" :title="state.locale.nameTitle" @click="openDisplayNameMenu">
          ⚙
        </button>
        <button type="button" class="emoji-button" @click="toggleEmojiPicker">
          <span class="native-emoji emoji-button-icon" aria-hidden="true">🤠</span>
        </button>
      </div>

      <div v-if="state.showInput && state.showEmojiPicker" class="emoji-panel">
        <div class="emoji-toolbar">
          <button
            v-for="group in emojiGroups"
            :key="group.labelKey"
            type="button"
            class="emoji-category"
            :class="{ active: activeEmojiGroup.labelKey === group.labelKey && !emojiQuery }"
            :title="state.locale[group.labelKey] || group.labelKey"
            :aria-label="state.locale[group.labelKey] || group.labelKey"
            @click="activeEmojiGroupKey = group.labelKey; emojiQuery = ''"
          >
            <span class="native-emoji emoji-heading" aria-hidden="true">{{ group.icon }}</span>
          </button>
        </div>
        <input
          v-model="emojiQuery"
          type="search"
          class="emoji-search"
          :placeholder="state.locale.emojiSearch"
          :aria-label="state.locale.emojiSearch"
        />
        <div class="emoji-group">
          <div class="emoji-group-title">
            <span class="native-emoji emoji-heading" aria-hidden="true">{{ activeEmojiGroup.icon }}</span>
            <span>{{ state.locale[activeEmojiGroup.labelKey] || activeEmojiGroup.labelKey }}</span>
            <span class="emoji-count">{{ visibleEmoji.length }}</span>
          </div>
          <div class="emoji-grid">
            <button
              v-for="emoji in visibleEmoji"
              :key="emoji"
              type="button"
              class="emoji-chip"
              @click="addEmoji(emoji)"
            >
              <span class="native-emoji emoji-picker-item">{{ emoji }}</span>
            </button>
          </div>
          <div v-if="visibleEmoji.length === 0" class="emoji-empty">
            {{ state.locale.emojiNoResults }}
          </div>
        </div>
      </div>

      <SuggestionsList :message="state.message" :suggestions="visibleSuggestions" />

      <div v-if="state.showHideState" class="hide-state-indicator">
        {{ hideStateLabel }}
      </div>
    </section>
  </div>
</template>

<style>
:root {
  --chat-font-scale: 1;
  --chat-background: #16120fcc;
  --chat-panel: #211a16ee;
  --chat-border: #6e543a;
  --chat-primary: #f4ebdd;
  --chat-muted: #b7aa97;
  --chat-danger: #e06c5f;
}

.reduced-motion *, .reduced-motion *::before, .reduced-motion *::after {
  animation-duration: 0.001ms !important;
  transition-duration: 0.001ms !important;
}

.compact-chat .chat-messages { line-height: 1.1; }

:root {
  font-family: "Lato", Helvetica, Arial, sans-serif;
}

html,
body,
#app {
  margin: 0;
  width: 100%;
  height: 100%;
  overflow: hidden;
  background: transparent !important;
  background-color: transparent !important;
}

body {
  user-select: none;
  background: transparent !important;
  background-color: transparent !important;
}

.chat-shell {
  position: relative;
  width: 100vw;
  height: 100vh;
  background: transparent !important;
  background-color: transparent !important;
  color: white;
  text-shadow: none;
}

.color-0 {
  color: #ffffff;
}

.color-1 {
  color: #ff4444;
}

.color-2 {
  color: #99cc00;
}

.color-3 {
  color: #ffbb33;
}

.color-4 {
  color: #0099cc;
}

.color-5 {
  color: #33b5e5;
}

.color-6 {
  color: #aa66cc;
}

.color-8 {
  color: #cc0000;
}

.color-9 {
  color: #cc0068;
}

.gameColor-w {
  color: #ffffff;
}

.gameColor-r {
  color: #ff4444;
}

.gameColor-g {
  color: #99cc00;
}

.gameColor-y {
  color: #ffbb33;
}

.gameColor-b {
  color: #33b5e5;
}

.chat-window {
  position: absolute;
  top: 4.2%;
  left: 0.8%;
  width: 38%;
  max-width: 42rem;
  min-width: 28rem;
  height: 22%;
  transition: opacity 0.18s ease, transform 0.18s ease;
  color: var(--chat-primary);
  font-size: calc(1em * var(--chat-font-scale));
}

.chat-tabs {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  margin: 0 1% 0.25rem;
  flex-wrap: wrap;
}

.chat-tab {
  border: 0;
  border-radius: 4px;
  padding: 0.28rem 0.55rem;
  background: var(--chat-panel);
  color: var(--chat-muted);
  font-size: 1.2vh;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  cursor: pointer;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.06);
}

.chat-tab.active {
  color: var(--tab-color);
  background: rgba(0, 0, 0, 0.8);
  box-shadow: inset 0 -2px 0 0 var(--tab-color);
}

.chat-window.hidden {
  opacity: 0;
}

.chat-messages {
  position: relative;
  height: calc(95% - 2.1rem);
  font-size: 1.95vh;
  margin: 1%;
  overflow-x: hidden;
  overflow-y: auto;
  padding-right: 0.35rem;
  font-weight: 600;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.75);
  scrollbar-width: thin;
  scrollbar-color: rgba(255, 255, 255, 0.22) rgba(0, 0, 0, 0.14);
}

.older-messages-toggle {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  margin: 0 0 0.7rem;
  border: 0;
  border-radius: 4px;
  padding: 0.42rem 0.75rem;
  background: rgba(16, 16, 16, 0.76);
  color: rgba(255, 255, 255, 0.88);
  font-size: 1.15vh;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  cursor: pointer;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.08);
}

.older-messages-toggle:hover {
  background: rgba(24, 24, 24, 0.86);
}

.chat-messages::-webkit-scrollbar {
  width: 0.42rem;
}

.chat-messages::-webkit-scrollbar-track {
  background: rgba(0, 0, 0, 0.14);
  border-radius: 999px;
}

.chat-messages::-webkit-scrollbar-thumb {
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.28), rgba(215, 215, 215, 0.16));
  border-radius: 999px;
}

.chat-messages::-webkit-scrollbar-thumb:hover {
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.38), rgba(230, 230, 230, 0.24));
}

.chat-input-shell {
  font-size: 1.65vh;
  position: absolute;
  top: 27.2%;
  left: 0.8%;
  width: 38%;
  max-width: 42rem;
}

.chat-input-row {
  position: relative;
  display: flex;
  align-items: stretch;
  width: 100%;
  box-sizing: border-box;
  background:
    linear-gradient(180deg, rgba(64, 32, 24, 0.3), rgba(32, 16, 12, 0.22)),
    url("../img/background.png");
  background-size: 100% 100%;
  background-repeat: no-repeat;
  border: 1px solid var(--chat-border);
  border-radius: 5px;
  padding: 0;
  gap: 0;
  box-shadow: none;
  backdrop-filter: none;
}

.mode-pill {
  height: 100%;
  vertical-align: middle;
  text-transform: uppercase;
  font-weight: 700;
  display: inline-block;
  padding-top: 0.8vh;
  padding-left: 2vh;
  min-width: auto;
  border-right: 0;
  font-size: 1.65vh;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.7);
}

.chat-input {
  font-size: 1.65vh;
  line-height: 1.85vh;
  display: block;
  box-sizing: content-box;
  padding: 1vh;
  padding-left: 0.5vh;
  color: white;
  border-width: 0;
  min-height: 1.85vh;
  overflow: hidden;
  text-overflow: ellipsis;
  flex: 1;
  background-color: transparent;
  font-weight: 600;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.7);
}

.chat-input:focus {
  outline: none;
}

.emoji-button {
  flex: 0 0 auto;
  align-self: center;
  width: 4vh;
  height: 4vh;
  margin: 0.42vh 0.8vh 0 0;
  border: 0;
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.08);
  color: white;
  font-size: 1.7vh;
  line-height: 1;
  font-family: "Segoe UI Symbol", "Noto Color Emoji", "Apple Color Emoji", sans-serif;
  cursor: pointer;
}

.settings-button {
  flex: 0 0 auto;
  align-self: center;
  width: 4vh;
  height: 4vh;
  padding: 0;
  margin: 0.42vh 0.4vh 0 0;
  border: 0;
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.08);
  color: white;
  font-size: 1.8vh;
  font-weight: 700;
  line-height: 1;
  font-family: "Segoe UI Symbol", "Noto Color Emoji", "Apple Color Emoji", sans-serif;
  cursor: pointer;
}

.emoji-panel {
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
  width: 100%;
  box-sizing: border-box;
  margin-top: 0.35rem;
  max-height: 22vh;
  overflow-y: auto;
  padding: 0.65rem 0.75rem;
  font-size: 1.65vh;
  color: white;
  background-color: rgba(0, 0, 0, 0.78);
  border-radius: 4px;
  scrollbar-width: thin;
  scrollbar-color: rgba(255, 255, 255, 0.2) rgba(0, 0, 0, 0.12);
}

.emoji-panel::-webkit-scrollbar {
  width: 0.4rem;
}

.emoji-panel::-webkit-scrollbar-track {
  background: rgba(0, 0, 0, 0.12);
  border-radius: 999px;
}

.emoji-panel::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.24);
  border-radius: 999px;
}

.emoji-toolbar {
  display: grid;
  grid-template-columns: repeat(11, minmax(0, 1fr));
  gap: 0.25rem;
  position: sticky;
  top: -0.65rem;
  z-index: 1;
  padding: 0.45rem 0;
  background: rgba(0, 0, 0, 0.94);
}

.emoji-category {
  border: 0;
  border-bottom: 2px solid transparent;
  padding: 0.3rem 0;
  background: transparent;
  cursor: pointer;
}

.emoji-category:hover,
.emoji-category.active {
  border-bottom-color: var(--chat-border);
  background: rgba(255, 255, 255, 0.1);
}

.emoji-search {
  width: 100%;
  box-sizing: border-box;
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 4px;
  padding: 0.42rem 0.55rem;
  color: var(--chat-primary);
  background: rgba(255, 255, 255, 0.08);
  outline: none;
}

.emoji-search:focus {
  border-color: var(--chat-border);
}

.emoji-group {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.emoji-group-title {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 1.35vh;
  font-weight: 700;
  color: #d8d8d8;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.emoji-count {
  margin-left: auto;
  color: var(--chat-muted);
}

.emoji-empty {
  padding: 0.8rem 0;
  color: var(--chat-muted);
  text-align: center;
}

.emoji-group-icon {
  font-size: 1.5vh;
}

.native-emoji {
  display: inline-block;
  font-family: "Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji", sans-serif;
  font-style: normal;
  font-weight: 400;
  line-height: 1;
  pointer-events: none;
}

.emoji-button-icon {
  font-size: 1.15rem;
}

.emoji-heading {
  font-size: 1.5vh;
}

.emoji-picker-item {
  font-size: 1.05rem;
}

.emoji-grid {
  display: grid;
  grid-template-columns: repeat(8, minmax(0, 1fr));
  gap: 0.35rem;
}

.emoji-chip {
  border: 0;
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.08);
  padding: 0.38rem 0;
  cursor: pointer;
  font-size: 1.05rem;
  line-height: 1;
}

.emoji-chip:hover {
  background: rgba(255, 255, 255, 0.16);
}

.msg {
  margin-bottom: 0.28%;
  font-weight: 600;
}

.multiline {
  white-space: pre-line;
  border-radius: 5px;
  padding: 7px;
  margin-bottom: 10px;
  background-image: url("../img/background.png");
  background-size: 100% 100%;
  background-repeat: no-repeat;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.72);
  background-color: rgba(0, 0, 0, 0.2);
  background-blend-mode: multiply;
}

.suggestions {
  list-style-type: none;
  padding: 0.5%;
  padding-left: 1.4%;
  font-size: 1.65vh;
  box-sizing: border-box;
  color: white;
  background-color: rgba(0, 0, 0, 0.78);
  width: 100%;
  border-radius: 4px;
}

.help,
.disabled {
  color: #b0bbbd;
}

.suggestion {
  margin-bottom: 0.5%;
}

.hidden {
  opacity: 0;
}

.hide-state-indicator {
  text-transform: uppercase;
  margin-left: 0.05vw;
  font-size: 1.65vh;
}

@media (max-width: 1200px) {
  .chat-window,
  .chat-input-shell {
    width: 48vw;
    min-width: 0;
  }
}

@media (max-width: 800px) {
  .chat-window,
  .chat-input-shell {
    width: 92vw;
  }

  .chat-window {
    height: 28vh;
  }
}
</style>
