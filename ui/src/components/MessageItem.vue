<script setup>
import { computed } from "vue";

const props = defineProps({
  message: { type: Object, required: true },
  activeMode: { type: Object, required: true },
  localeCode: { type: String, default: "en-GB" },
});

const args = computed(() => Array.isArray(props.message.args) ? props.message.args.map(String) : []);
const author = computed(() => args.value.length > 1 ? args.value[0] : "");
const text = computed(() => args.value.length > 1 ? args.value.slice(1).join(" ") : (args.value[0] || ""));

const timestampLabel = computed(() => {
  if (!props.message.createdAtMs) return "";
  return new Intl.DateTimeFormat(props.localeCode || "en-GB", {
    day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
  }).format(new Date(props.message.createdAtMs));
});

const timestampTitle = computed(() => {
  if (!props.message.createdAtMs) return "";
  return new Intl.DateTimeFormat(props.localeCode || "en-GB", {
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).format(new Date(props.message.createdAtMs));
});
</script>

<template>
  <div class="msg" :class="{ multiline: message.multiline }">
    <div class="msg-row">
      <span class="msg-line"><strong v-if="author" :style="{ color: message.authorColor || undefined }">{{ author }}:</strong> {{ text }}</span>
      <span v-if="timestampLabel" class="msg-time" :title="timestampTitle">{{ timestampLabel }}</span>
    </div>
  </div>
</template>

<style scoped>
.msg-row { display: flex; align-items: flex-start; justify-content: space-between; gap: 0.8rem; }
.msg-line { min-width: 0; flex: 1 1 auto; white-space: pre-wrap; overflow-wrap: anywhere; }
.msg-time { flex: 0 0 auto; margin-top: 0.08rem; color: var(--chat-muted); font-size: 0.72em;
  font-weight: 600; white-space: nowrap; text-align: right; }
</style>
